# Roast → RoastEx gap mapping (handoff)

**Upstream:** https://github.com/Shopify/roast (Ruby gem `roast-ai`, MIT, Shopify)  
**This repo:** `roast_ex/` — Elixir MVP rewrite, **not** a line-by-line port.  
**Goal of this doc:** an agent on another machine can implement missing pieces without rediscovering the Ruby architecture.

Read upstream first:

- `README.md`
- `lib/roast/workflow.rb`
- `lib/roast/cog.rb`
- `lib/roast/execution_manager.rb` (if present; execution lives around `ExecutionManager` / `ExecutionContext`)
- `lib/roast/control_flow.rb`
- `lib/roast/cogs/` and `lib/roast/system_cogs/`
- `tutorial/`
- `examples/`

Current Elixir tree:

```
roast_ex/
  mix.exs
  README.md
  GAP_MAPPING.md          ← this file
  examples/analyze_codebase.exs
  lib/roast_ex.ex
  lib/roast_ex/dsl.ex
  lib/roast_ex/context.ex
  lib/roast_ex/helpers.ex
  lib/roast_ex/output.ex
  lib/roast_ex/runner.ex
  lib/roast_ex/cogs.ex
  lib/roast_ex/cogs/{chat,cmd,agent,elixir_cog}.ex
  lib/mix/tasks/roast.execute.ex
```

Environment note: the sandbox that created this MVP **did not have Elixir/Mix**. Nothing here has been compiled. First task on a real machine: `mix deps.get && mix compile` and fix whatever breaks.

---

## 0. Status legend

| Tag | Meaning |
|-----|---------|
| DONE | present in RoastEx, good enough as MVP |
| PARTIAL | exists but missing semantics / edge cases |
| MISSING | not implemented |
| WONT | intentionally different in Elixir; document, don’t clone blindly |

Priority for handoff: **P0** must-have for Roast-like workflows, **P1** parity, **P2** polish.

---

## 1. Feature matrix

### 1.1 DSL surface

| Roast (Ruby) | RoastEx | Status | Pri | Notes for implementer |
|---|---|---|---|---|
| `config do ... end` | `config do %{...} end` | PARTIAL | P0 | Ruby uses nested DSL (`config { chat { provider :anthropic } }`). Elixir only accepts a map/keyword today. Replicate nested macros **or** keep map and document it. |
| `execute do ... end` | `execute do ... end` | PARTIAL | P0 | No named scopes (`execute :scope_name`). Steps accumulated via module attribute. |
| `execute(:scope) { }` | — | MISSING | P0 | Needed for `call`. |
| `use :my_cog` / `use :foo, from: "gem"` | — | MISSING | P1 | Loads cog class into registry. |
| `chat(:name) { prompt }` | `chat :name do prompt end` | PARTIAL | P0 | Helpers need explicit `ctx`. No per-call config block. |
| `agent(:name) { prompt }` | `agent :name do ... end` | PARTIAL | P0 | Same. |
| `cmd(:name) { "shell" }` | `cmd(:name, "shell")` | PARTIAL | P0 | Block form exists in macro but example uses string. Capture stderr separately. cwd / env / timeout missing. |
| `ruby(:name) { ... }` | `ruby` / `elixir_cog` | PARTIAL | P1 | Exists as `:elixir` step. Rename consistently. |
| `map(:name) { ... }` | `map_cog` | PARTIAL | P0 | Runner supports `%{collection, mapper}` or list. **No DSL matching Roast map API.** Macro barely usable. |
| `repeat(:name) { ... }` | — | MISSING | P0 | Loop until condition. See `lib/roast/system_cogs/repeat.rb`. |
| `call(:scope, value)` | — | MISSING | P0 | Invoke named execute scope with a scope value. |
| `chat!(:name)` / `cmd!(:name)` | `chat!(ctx, :name)` | WONT/PARTIAL | P1 | Elixir cannot have implicit receiver like Ruby `instance_exec`. Keep `ctx` **or** use process dict / a tiny DSL server. Do not fake Ruby’s implicit `self`. |
| `skip!` `fail!` `next!` `break!` | — | MISSING | P0 | `lib/roast/control_flow.rb`. Implemented as exceptions in Ruby. Use `throw/catch` or dedicated exception modules. |
| anonymous cogs (no name) | — | MISSING | P2 | Ruby can generate UUID name. |
| workflow params / targets | `params` on Context, unused by DSL | PARTIAL | P1 | Wire into CLI and `params(ctx)`. |

### 1.2 Runtime / engine

| Roast | RoastEx | Status | Pri | Notes |
|---|---|---|---|---|
| `Workflow.from_file` + tmpdir | Mix task `Code.require_file` | PARTIAL | P1 | No tmpdir, no EventMonitor wrap. |
| `prepare!` then `start!` | single `Runner.run/2` | PARTIAL | P2 | Fine for MVP; split if you add config-time validation. |
| `Cog::Registry` | hard-coded `case type` in Runner | MISSING | P0 | Must become behaviour + registry before custom cogs. |
| `ExecutionManager` + barriers | sequential `Enum.reduce` | PARTIAL | P1 | Ruby can overlap independent cogs via `Async::Barrier`. Elixir: only `map` is parallel. |
| `CogInputContext` / `instance_exec` | anonymous `fn ctx ->` | PARTIAL | P1 | Input objects + coerce/validate missing. |
| `TaskContext.begin_cog` | — | MISSING | P2 | Logging / tracing hook. |
| `EventMonitor` | — | MISSING | P1 | Lifecycle events for UI/logs. |
| `OutputRouter` / pretty logs | `inspect` in Mix task | MISSING | P1 | |
| `abort_on_failure` default true | always raise | PARTIAL | P1 | Make configurable per cog / global. |
| ControlFlow::Break at top-level = stop quietly | — | MISSING | P0 | |

### 1.3 Cogs — chat

| Capability | Status | Pri |
|---|---|---|
| OpenAI | PARTIAL (Req, happy path only) | P0 |
| Anthropic | PARTIAL | P0 |
| Gemini | PARTIAL | P1 |
| Perplexity | MISSING | P1 |
| `ROAST_DEFAULT_CHAT_PROVIDER` | DONE | P1 |
| `OPENAI_API_BASE` / Anthropic / Gemini base | PARTIAL | P1 |
| model from config | PARTIAL | P0 |
| system prompt, temperature, max_tokens | MISSING | P1 |
| multi-message / history | MISSING | P2 |
| streaming | MISSING | P2 |
| JSON mode / tools | MISSING | P2 |
| retries, rate-limit, timeout | MISSING | P1 |
| structured output types (`Output.Chat`) | DONE | P1 |

Upstream refs: `lib/roast/cogs/chat/` (input, output, config).

### 1.4 Cogs — agent

| Capability | Status | Pri |
|---|---|---|
| provider `:pi` via CLI | PARTIAL | P0 |
| provider `:claude` via CLI | PARTIAL | P0 |
| `ROAST_DEFAULT_AGENT_PROVIDER` | DONE | P1 |
| pass cwd = workflow_dir | MISSING | P0 |
| extra CLI flags / model | MISSING | P1 |
| parse structured agent output | MISSING | P2 |
| missing-binary error UX | MISSING | P1 |

Upstream: `lib/roast/cogs/agent/`.

### 1.5 Cogs — cmd

| Capability | Status | Pri |
|---|---|---|
| run shell, capture stdout | PARTIAL (`stderr_to_stdout: true`) | P0 |
| separate stderr | MISSING | P1 |
| exit status on output | DONE | P0 |
| raise on non-zero (configurable) | MISSING | P0 |
| cwd, env, timeout | MISSING | P1 |
| array argv vs string | MISSING | P2 |

Upstream: `lib/roast/cogs/cmd.rb`.

### 1.6 System cogs

| Cog | Status | Pri | Upstream |
|---|---|---|---|
| `map` serial/parallel | PARTIAL | P0 | `lib/roast/system_cogs/map.rb` |
| `repeat` | MISSING | P0 | `lib/roast/system_cogs/repeat.rb` |
| `call` | MISSING | P0 | `lib/roast/system_cogs/call.rb` |
| `ruby` | PARTIAL as elixir | P1 | `lib/roast/cogs/ruby.rb` |

Map must support: collection expression, item binding, index, nested cogs inside mapper (this last one is the hard part — Ruby evaluates nested DSL in a child execution manager).

**Handoff warning:** a real `map`/`call`/`repeat` is not “run a lambda”. In Roast they spawn nested execution scopes so inner `chat`/`cmd` work. RoastEx `map` today only maps a user function that returns values — **cannot nest cogs**. This is the largest architectural gap.

### 1.7 Config system

| Roast | RoastEx | Status | Pri |
|---|---|---|---|
| `ConfigManager` + `ConfigContext` | one map on module | PARTIAL | P1 |
| per-cog class `Cog::Config` | keyword opts on step | PARTIAL | P1 |
| env default vs workflow override | PARTIAL for provider only | P1 |
| invalid provider raises | PARTIAL (chat raises on unknown) | P1 |

Upstream shims: `sorbet/rbi/shims/lib/roast/config_context.rbi`, `lib/roast/cog/config.rb`.

### 1.8 CLI / packaging

| Roast | RoastEx | Status | Pri |
|---|---|---|---|
| `bin/roast execute FILE` | `mix roast.execute FILE --module X` | PARTIAL | P1 |
| gem `roast-ai` | mix app only, no Hex | MISSING | P2 |
| params CLI flags | — | MISSING | P1 |
| tutorial runner | — | MISSING | P2 |
| escript / mix install | — | MISSING | P2 |

### 1.9 Observability

| Roast | RoastEx | Status | Pri |
|---|---|---|---|
| EventMonitor start/stop | — | MISSING | P1 |
| Rainbow colored logs | — | MISSING | P2 |
| task annotations | — | MISSING | P2 |
| workflow success/fail summary | inspect map | MISSING | P1 |

### 1.10 Tests & docs

| Item | Status | Pri |
|---|---|---|
| ExUnit unit tests | MISSING | P0 |
| ExUnit for DSL compile | MISSING | P0 |
| HTTP client mocked | MISSING | P0 |
| port Roast `examples/` as fixtures | MISSING | P1 |
| tutorial chapters 1–9 | MISSING | P2 |
| `@moduledoc` completeness | PARTIAL | P2 |
| typespecs | PARTIAL | P2 |
| CI | MISSING | P2 |

### 1.11 Dependencies

Roast Ruby: activesupport, async, rainbow, ruby_llm, type_toolkit, zeitwerk, sorbet.  
RoastEx: jason, req only.

No HTTP mock lib, no CLI parser beyond OptionParser, no telemetry.

---

## 2. Architectural gaps (read this before coding)

### 2.1 Nested execution (the big one)

Ruby:

```
execute do
  map(:files) do
    collection cmd!(:list).lines
    chat(:one) { "review #{item}" }
  end
end
```

Inner `chat` is a real cog run by a child `ExecutionManager` with its own scope value (`item`).

Elixir today: `map` expects `%{collection: list, mapper: fn ctx, item -> value end}`. No inner cog graph.

**Required design before implementing map/call/repeat properly:**

1. Steps are data (`%Step{type, name, opts, fun}`).
2. `Runner.run_steps(steps, ctx)` is recursive.
3. `call` / `map` / `repeat` create child ctx (maybe inherit outputs, override `scope_value` / `scope_index`).
4. Named scopes stored as `%{nil => [steps], :foo => [steps]}` like Ruby `@execution_procs`.

Do **not** implement map as “just Enum.map” if the goal is Roast parity.

### 2.2 Cog behaviour

Replace `case type` in `runner.ex` with:

```elixir
defmodule RoastEx.Cog do
  @callback run(input :: term(), opts :: keyword(), ctx :: RoastEx.Context.t()) :: struct()
  @callback validate_input(term()) :: :ok | {:error, term()}
end
```

Registry: `%{chat: RoastEx.Cogs.Chat, cmd: RoastEx.Cogs.Cmd, ...}` plus user modules.

### 2.3 Control flow

Map Ruby exceptions:

| Ruby | Suggested Elixir |
|---|---|
| `ControlFlow::SkipCog` | `throw {:roast, :skip, msg}` |
| `ControlFlow::FailCog` | `throw {:roast, :fail, msg}` or exception |
| `ControlFlow::Next` | `throw {:roast, :next, msg}` |
| `ControlFlow::Break` | `throw {:roast, :break, msg}` |

Catch in runner / map / repeat. Top-level `break` ends workflow without failure (Ruby does this).

### 2.4 Implicit vs explicit context

Do not try to make `cmd!(:x)` work via `instance_eval` equivalent unless you accept `Process.put/get` or a custom eval env. Recommended: keep `ctx` as first argument; optionally add `RoastEx.DSL` macros that rewrite `cmd!(:x)` → `cmd!(ctx, :x)` at compile time (macro hygiene). That is a good P1 quality-of-life task.

### 2.5 Don’t port

- Sorbet / RBI
- Zeitwerk
- ActiveSupport (use Elixir stdlib)
- `instance_eval` of raw file source as the *primary* API (`.exs` modules are fine)
- Exact class hierarchy names unless they help navigation

---

## 3. Suggested implementation order

Work in PRs/commits in this order. Each step should leave `mix compile` green and add tests.

### Slice A — foundation (unblocks everything)

1. `mix compile` + fix DSL bugs (`config` attribute, step order, unused Helpers import inside fun).
2. Cog behaviour + registry.
3. Tests with fake cog (no network).
4. Control-flow throws + `abort_on_failure`.

### Slice B — nested engine

5. Named `execute :scope do`.
6. `call` system cog.
7. Real `map` (serial + parallel) with nested steps **or** documented subset if nested is too large; prefer nested.
8. `repeat`.

### Slice C — cog parity

9. Cmd: cwd, env, timeout, raise-on-nonzero.
10. Chat: Perplexity, generation params, retries, better errors.
11. Agent: cwd=workflow_dir, binary-not-found, flags.
12. Config nested DSL **or** freeze map API and document.

### Slice D — product

13. CLI params, default module guess hardened.
14. Event log / summary.
15. Port 2–3 upstream examples.
16. Hex + README status table update.

---

## 4. Acceptance checks (agent should not mark done without these)

**A. Foundation**

- [ ] `mix test` exists and passes without API keys.
- [ ] Fake workflow: `cmd` + `elixir` + read output via `cmd!/2`.
- [ ] Unknown cog name / missing output raises a clear error.

**B. Nested**

- [ ] `execute :inner do chat(:x) do ... end end` + `call(:inner, item)` runs and writes outputs without colliding names (define namespacing policy and test it).
- [ ] `map` over 3 items with nested `elixir` cog returns 3 values; `:parallel` and serial both work.
- [ ] `repeat` stops on condition; infinite-loop guard (max iterations).

**C. Control flow**

- [ ] `skip!` leaves no output / marked skipped; workflow continues.
- [ ] `fail!` + `abort_on_failure: true` stops workflow.
- [ ] `fail!` + `abort_on_failure: false` records failure and continues.
- [ ] `break!` in top-level stops remaining steps without exception leak.

**D. Chat/agent**

- [ ] Provider selected from env and overridden by workflow config.
- [ ] Missing API key raises a one-line actionable error.
- [ ] Agent invoked with `cd` = workflow_dir (test with a stub script on PATH).

**E. CLI**

- [ ] `mix roast.execute examples/analyze_codebase.exs --module AnalyzeCodebase` loads file.
- [ ] Optional `--param key=value`.

---

## 5. Known issues in current MVP (fix early)

1. **DSL `config`**: `@roast_config unquote(block)` is fragile; compile a real example on Mix.
2. **Helpers imported at module level** but blocks are `fn ctx ->`; `cmd!/2` works only if arity matches. Verify after compile.
3. **`var!(ctx) = ctx`** inside generated fun — confirm no warning / hygiene issues.
4. **`RoastEx.Cogs` empty module** — only exists so `alias RoastEx.Cogs` + `Cogs.Cmd` works; fine.
5. **Chat uses `System.fetch_env!`** — blows up before nice error.
6. **Cmd merges stderr into stdout.**
7. **Map DSL `map_cog` not demonstrated** in the example.
8. **No `.gitignore`**, no `test/`, no `formatter.exs`.
9. **Req not started** — Mix task runs `app.start` which should start req; double-check.
10. **Agent CLI args** (`pi [prompt]`, `claude -p`) may be wrong vs current CLIs; verify against upstream `agent` cog and current Pi/Claude flags.

---

## 6. File-level mapping (where to look / where to write)

| Upstream Ruby | Elixir target |
|---|---|
| `lib/roast/workflow.rb` | `lib/roast_ex.ex` + future `workflow.ex` |
| `lib/roast/cog.rb` | new `lib/roast_ex/cog.ex` behaviour |
| `lib/roast/execution_manager.rb` | `lib/roast_ex/runner.ex` (grow this) |
| `lib/roast/execution_context.rb` | empty in Ruby; logic is in managers — don’t cargo-cult |
| `lib/roast/cog_input_context.rb` | helpers + optional input structs |
| `lib/roast/control_flow.rb` | new `lib/roast_ex/control_flow.ex` |
| `lib/roast/config_manager.rb` | new `lib/roast_ex/config.ex` |
| `lib/roast/cogs/chat/*` | `lib/roast_ex/cogs/chat.ex` |
| `lib/roast/cogs/agent/*` | `lib/roast_ex/cogs/agent.ex` |
| `lib/roast/cogs/cmd.rb` | `lib/roast_ex/cogs/cmd.ex` |
| `lib/roast/cogs/ruby.rb` | `lib/roast_ex/cogs/elixir_cog.ex` |
| `lib/roast/system_cogs/map.rb` | new `lib/roast_ex/cogs/map.ex` + runner nested |
| `lib/roast/system_cogs/repeat.rb` | new `lib/roast_ex/cogs/repeat.ex` |
| `lib/roast/system_cogs/call.rb` | new `lib/roast_ex/cogs/call.ex` |
| `lib/roast/event_monitor.rb` | new `lib/roast_ex/events.ex` |
| `exe/` / `bin/` | `lib/mix/tasks/roast.execute.ex` |
| `tutorial/` | later `tutorial/` |
| `examples/` | `examples/` |
| `test/` | `test/` |

---

## 7. Out of scope unless product owner asks

- Pixel-perfect log format
- Sorbet types
- Supporting eval of raw `.rb` Roast files
- Multi-node distributed workflows
- Web UI
- Storing run history / DB

---

## 8. One-paragraph brief you can paste into the next agent

> Continue the Elixir rewrite of Shopify Roast in `roast_ex/`. This is an MVP: sequential runner, map/chat/cmd/agent stubs, no tests, never compiled in the original sandbox. Do not translate Ruby file-by-file. Implement a recursive step runner, Cog behaviour+registry, control-flow throws, then nested `call`/`map`/`repeat` so inner cogs work. Keep `ctx` explicit unless you add a compile-time rewrite of `cmd!(:name)`. Match providers and env vars from upstream README. Add ExUnit with no network. Follow `GAP_MAPPING.md` slices A→D and do not mark map/call done if they cannot nest cogs.

---

## 9. Copy-paste command list for the next machine

```bash
cd roast_ex
mix deps.get
mix compile
mix test
mix roast.execute examples/analyze_codebase.exs --module AnalyzeCodebase
```

Expect compile and example (chat/agent) to fail until keys/CLIs exist; `cmd`-only tests should pass after Slice A.
