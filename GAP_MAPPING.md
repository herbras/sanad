# Roast → Sanad gap mapping (handoff)

**Upstream:** https://github.com/Shopify/roast (Ruby gem `roast-ai`, MIT, Shopify)  
**This repo:** `sanad/` — Elixir MVP rewrite, **not** a line-by-line port.  
**Goal of this doc:** an agent on another machine can implement missing pieces without rediscovering the Ruby architecture.

Read upstream first:

- `README.md`
- `lib/sanad/workflow.rb`
- `lib/sanad/cog.rb`
- `lib/sanad/execution_manager.rb` (if present; execution lives around `ExecutionManager` / `ExecutionContext`)
- `lib/sanad/control_flow.rb`
- `lib/sanad/cogs/` and `lib/sanad/system_cogs/`
- `tutorial/`
- `examples/`

Current Elixir tree:

```
sanad/
  mix.exs
  README.md
  GAP_MAPPING.md          ← this file
  examples/analyze_codebase.exs
  lib/sanad.ex
  lib/sanad/dsl.ex
  lib/sanad/context.ex
  lib/sanad/helpers.ex
  lib/sanad/output.ex
  lib/sanad/runner.ex
  lib/sanad/cogs.ex
  lib/sanad/cogs/{chat,cmd,agent,elixir_cog}.ex
  lib/mix/tasks/sanad.execute.ex
```

Environment note: the machine this is developed on has no Elixir on PATH. Use `./bin/mix`, which runs mix inside `elixir:1.18-alpine` with the repo mounted. CI runs the same gates natively.

---

## 0. Status legend

| Tag | Meaning |
|-----|---------|
| DONE | present in Sanad, good enough as MVP |
| PARTIAL | exists but missing semantics / edge cases |
| MISSING | not implemented |
| WONT | intentionally different in Elixir; document, don’t clone blindly |

Priority for handoff: **P0** must-have for Roast-like workflows, **P1** parity, **P2** polish.

---

## 1. Feature matrix

### 1.1 DSL surface

| Roast (Ruby) | Sanad | Status | Pri | Notes for implementer |
|---|---|---|---|---|
| `config do ... end` | `config do %{...} end` plus scoped form | DONE | P0 | Both forms: the map, and `global(...)` / `chat(:name, ...)` / `chat(~r/.../, ...)`. Resolution order matches `config_for`. |
| `execute do ... end` | `execute do ... end` | PARTIAL | P0 | No named scopes (`execute :scope_name`). Steps accumulated via module attribute. |
| `execute(:scope) { }` | — | MISSING | P0 | Needed for `call`. |
| `use :my_cog` / `use :foo, from: "gem"` | — | MISSING | P1 | Loads cog class into registry. |
| `chat(:name) { prompt }` | `chat :name do prompt end` | PARTIAL | P0 | Helpers need explicit `ctx`. No per-call config block. |
| `agent(:name) { prompt }` | `agent :name do ... end` | PARTIAL | P0 | Same. |
| `cmd(:name) { "shell" }` | `cmd(:name, "shell")` | PARTIAL | P0 | Block form exists in macro but example uses string. Capture stderr separately. cwd / env / timeout missing. |
| `ruby(:name) { ... }` | `ruby` / `elixir_cog` | PARTIAL | P1 | Exists as `:elixir` step. Rename consistently. |
| `map(:name) { ... }` | `map_cog` | PARTIAL | P0 | Runner supports `%{collection, mapper}` or list. **No DSL matching Roast map API.** Macro barely usable. |
| `repeat(:name) { ... }` | — | MISSING | P0 | Loop until condition. See `lib/sanad/system_cogs/repeat.rb`. |
| `call(:scope, value)` | — | MISSING | P0 | Invoke named execute scope with a scope value. |
| `chat!(:name)` / `cmd!(:name)` | `chat!(ctx, :name)` | WONT/PARTIAL | P1 | Elixir cannot have implicit receiver like Ruby `instance_exec`. Keep `ctx` **or** use process dict / a tiny DSL server. Do not fake Ruby’s implicit `self`. |
| `skip!` `fail!` `next!` `break!` | — | MISSING | P0 | `lib/sanad/control_flow.rb`. Implemented as exceptions in Ruby. Use `throw/catch` or dedicated exception modules. |
| anonymous cogs (no name) | — | MISSING | P2 | Ruby can generate UUID name. |
| workflow params / targets | `params` on Context, unused by DSL | PARTIAL | P1 | Wire into CLI and `params(ctx)`. |

### 1.2 Runtime / engine

| Roast | Sanad | Status | Pri | Notes |
|---|---|---|---|---|
| `Workflow.from_file` + tmpdir | Mix task `Code.require_file` | PARTIAL | P1 | No tmpdir, no EventMonitor wrap. |
| `prepare!` then `start!` | single `Runner.run/2` | PARTIAL | P2 | Fine for MVP; split if you add config-time validation. |
| `Cog::Registry` | hard-coded `case type` in Runner | MISSING | P0 | Must become behaviour + registry before custom cogs. |
| `ExecutionManager` + barriers | sequential `Enum.reduce` | PARTIAL | P1 | Ruby can overlap independent cogs via `Async::Barrier`. Elixir: only `map` is parallel. |
| `CogInputContext` / `instance_exec` | anonymous `fn ctx ->` | PARTIAL | P1 | Input objects + coerce/validate missing. |
| `TaskContext.begin_cog` | — | MISSING | P2 | Logging / tracing hook. |
| `EventMonitor` | `Sanad.Events` + `Sanad.Event` | DONE | P1 | `:telemetry` spans for workflow/scope/cog plus stdout/stderr/block/log. No monitor process, so no global order — documented. |
| `OutputRouter` / pretty logs | `Sanad.Events.Renderer` | PARTIAL | P1 | Roast log format on stderr. A workflow's own `IO.puts` is not captured: that needs a group-leader process, deliberately not built. |
| `abort_on_failure` default true | always raise | PARTIAL | P1 | Make configurable per cog / global. |
| ControlFlow::Break at top-level = stop quietly | — | MISSING | P0 | |

### 1.3 Cogs — chat

| Capability | Status | Pri |
|---|---|---|
| OpenAI | PARTIAL (Req, happy path only) | P0 |
| Anthropic | PARTIAL | P0 |
| Gemini | PARTIAL | P1 |
| Perplexity | MISSING | P1 |
| `SANAD_DEFAULT_CHAT_PROVIDER` | DONE | P1 |
| `OPENAI_API_BASE` / Anthropic / Gemini base | PARTIAL | P1 |
| model from config | PARTIAL | P0 |
| system prompt, temperature, max_tokens | MISSING | P1 |
| multi-message / history | MISSING | P2 |
| streaming | MISSING | P2 |
| JSON mode / tools | MISSING | P2 |
| model aliases + `:claude` provider alias | DONE | P2 |
| retries, rate-limit, timeout | MISSING | P1 |
| structured output types (`Output.Chat`) | DONE | P1 |

Upstream refs: `lib/sanad/cogs/chat/` (input, output, config).

### 1.4 Cogs — agent

| Capability | Status | Pri |
|---|---|---|
| provider `:pi` via CLI | PARTIAL | P0 |
| provider `:claude` via CLI | PARTIAL | P0 |
| `SANAD_DEFAULT_AGENT_PROVIDER` | DONE | P1 |
| pass cwd = workflow_dir | MISSING | P0 |
| extra CLI flags / model | MISSING | P1 |
| parse structured agent output | MISSING | P2 |
| missing-binary error UX | MISSING | P1 |

Upstream: `lib/sanad/cogs/agent/`.

### 1.5 Cogs — cmd

| Capability | Status | Pri |
|---|---|---|
| run shell, capture stdout | PARTIAL (`stderr_to_stdout: true`) | P0 |
| separate stderr | MISSING | P1 |
| exit status on output | DONE | P0 |
| raise on non-zero (configurable) | MISSING | P0 |
| cwd, env, timeout | MISSING | P1 |
| array argv vs string | MISSING | P2 |

Upstream: `lib/sanad/cogs/cmd.rb`.

### 1.6 System cogs

| Cog | Status | Pri | Upstream |
|---|---|---|---|
| `map` serial/parallel | PARTIAL | P0 | `lib/sanad/system_cogs/map.rb` |
| `repeat` | MISSING | P0 | `lib/sanad/system_cogs/repeat.rb` |
| `call` | MISSING | P0 | `lib/sanad/system_cogs/call.rb` |
| `ruby` | PARTIAL as elixir | P1 | `lib/sanad/cogs/ruby.rb` |

Map must support: collection expression, item binding, index, nested cogs inside mapper (this last one is the hard part — Ruby evaluates nested DSL in a child execution manager).

**Handoff warning:** a real `map`/`call`/`repeat` is not “run a lambda”. In Roast they spawn nested execution scopes so inner `chat`/`cmd` work. Sanad `map` today only maps a user function that returns values — **cannot nest cogs**. This is the largest architectural gap.

### 1.7 Config system

| Roast | Sanad | Status | Pri |
|---|---|---|---|
| `ConfigManager` + `ConfigContext` | one map on module | PARTIAL | P1 |
| per-cog class `Cog::Config` | keyword opts on step | PARTIAL | P1 |
| env default vs workflow override | PARTIAL for provider only | P1 |
| invalid provider raises | PARTIAL (chat raises on unknown) | P1 |

Upstream shims: `sorbet/rbi/shims/lib/sanad/config_context.rbi`, `lib/sanad/cog/config.rb`.

### 1.8 CLI / packaging

| Roast | Sanad | Status | Pri |
|---|---|---|---|
| `bin/sanad execute FILE` | `mix sanad.execute FILE --module X` | PARTIAL | P1 |
| gem `roast-ai` | mix app only, no Hex | MISSING | P2 |
| params CLI flags | — | MISSING | P1 |
| tutorial runner | — | MISSING | P2 |
| escript / mix install | — | MISSING | P2 |

### 1.9 Observability

| Roast | Sanad | Status | Pri |
|---|---|---|---|
| EventMonitor start/stop | `[:sanad, _, :start \| :stop]` | DONE | P1 |
| Rainbow colored logs | — | MISSING | P2 |
| task annotations | — | MISSING | P2 |
| workflow success/fail summary | `Sanad.Summary` (top-level only) | PARTIAL | P1 |

### 1.10 Tests & docs

| Item | Status | Pri |
|---|---|---|
| ExUnit unit tests | DONE (128 tests) | P0 |
| ExUnit for DSL compile | DONE | P0 |
| HTTP client mocked | DONE (`Req.Test`) | P0 |
| port Roast `examples/` as fixtures | MISSING | P1 |
| tutorial chapters 1–9 | MISSING | P2 |
| `@moduledoc` completeness | PARTIAL | P2 |
| typespecs | PARTIAL | P2 |
| CI | MISSING | P2 |

### 1.11 Dependencies

Roast Ruby: activesupport, async, rainbow, ruby_llm, type_toolkit, zeitwerk, sorbet.  
Sanad: jason, req only.

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
defmodule Sanad.Cog do
  @callback run(input :: term(), opts :: keyword(), ctx :: Sanad.Context.t()) :: struct()
  @callback validate_input(term()) :: :ok | {:error, term()}
end
```

Registry: `%{chat: Sanad.Cogs.Chat, cmd: Sanad.Cogs.Cmd, ...}` plus user modules.

### 2.3 Control flow

Map Ruby exceptions:

| Ruby | Suggested Elixir |
|---|---|
| `ControlFlow::SkipCog` | `throw {:sanad, :skip, msg}` |
| `ControlFlow::FailCog` | `throw {:sanad, :fail, msg}` or exception |
| `ControlFlow::Next` | `throw {:sanad, :next, msg}` |
| `ControlFlow::Break` | `throw {:sanad, :break, msg}` |

Catch in runner / map / repeat. Top-level `break` ends workflow without failure (Ruby does this).

### 2.4 Implicit vs explicit context

Do not try to make `cmd!(:x)` work via `instance_eval` equivalent unless you accept `Process.put/get` or a custom eval env. Recommended: keep `ctx` as first argument; optionally add `Sanad.DSL` macros that rewrite `cmd!(:x)` → `cmd!(ctx, :x)` at compile time (macro hygiene). That is a good P1 quality-of-life task.

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

## 3b. Status per 19 September 2026

Slice A sampai D selesai sebelumnya. Sesudah itu:

* **Slice 0** toolchain container (`bin/mix`) dan CI.
* **Slice E** event system: span workflow/scope/cog lewat `:telemetry`, path event ikut ke proses
  anak `map` karena hidup di `Sanad.Context`, stdout streaming dari cmd, block untuk prompt dan
  response, renderer ala Roast di stderr (`--quiet` untuk mematikannya).
* **Slice F** `outputs` dan `outputs!` sebagai nilai balik scope.
* **Slice G** config per nama dan per pola, bentuk map lama tetap jalan.
* **Slice J1** alias provider `:claude` dan alias model (`:opus`, `:sonnet`, `:haiku`, `:fable`).

Belum: streaming chat, JSON mode dan tool calls, normalisasi session agent (Slice H); stats dan
usage pi (J2); ringkasan yang diturunkan dari event (E4); preflight validasi config (G3);
tutorial 1-9 dan publish Hex (I).

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

- [ ] `mix sanad.execute examples/analyze_codebase.exs --module AnalyzeCodebase` loads file.
- [ ] Optional `--param key=value`.

---

## 5. Known issues in current MVP (fix early)

1. **DSL `config`**: `@roast_config unquote(block)` is fragile; compile a real example on Mix.
2. **Helpers imported at module level** but blocks are `fn ctx ->`; `cmd!/2` works only if arity matches. Verify after compile.
3. **`var!(ctx) = ctx`** inside generated fun — confirm no warning / hygiene issues.
4. **`Sanad.Cogs` empty module** — only exists so `alias Sanad.Cogs` + `Cogs.Cmd` works; fine.
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
| `lib/sanad/workflow.rb` | `lib/sanad.ex` + future `workflow.ex` |
| `lib/sanad/cog.rb` | new `lib/sanad/cog.ex` behaviour |
| `lib/sanad/execution_manager.rb` | `lib/sanad/runner.ex` (grow this) |
| `lib/sanad/execution_context.rb` | empty in Ruby; logic is in managers — don’t cargo-cult |
| `lib/sanad/cog_input_context.rb` | helpers + optional input structs |
| `lib/sanad/control_flow.rb` | new `lib/sanad/control_flow.ex` |
| `lib/sanad/config_manager.rb` | new `lib/sanad/config.ex` |
| `lib/sanad/cogs/chat/*` | `lib/sanad/cogs/chat.ex` |
| `lib/sanad/cogs/agent/*` | `lib/sanad/cogs/agent.ex` |
| `lib/sanad/cogs/cmd.rb` | `lib/sanad/cogs/cmd.ex` |
| `lib/sanad/cogs/ruby.rb` | `lib/sanad/cogs/elixir_cog.ex` |
| `lib/sanad/system_cogs/map.rb` | new `lib/sanad/cogs/map.ex` + runner nested |
| `lib/sanad/system_cogs/repeat.rb` | new `lib/sanad/cogs/repeat.ex` |
| `lib/sanad/system_cogs/call.rb` | new `lib/sanad/cogs/call.ex` |
| `lib/sanad/event_monitor.rb` | new `lib/sanad/events.ex` |
| `exe/` / `bin/` | `lib/mix/tasks/sanad.execute.ex` |
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

> Continue the Elixir rewrite of Shopify Roast in `sanad/`. This is an MVP: sequential runner, map/chat/cmd/agent stubs, no tests, never compiled in the original sandbox. Do not translate Ruby file-by-file. Implement a recursive step runner, Cog behaviour+registry, control-flow throws, then nested `call`/`map`/`repeat` so inner cogs work. Keep `ctx` explicit unless you add a compile-time rewrite of `cmd!(:name)`. Match providers and env vars from upstream README. Add ExUnit with no network. Follow `GAP_MAPPING.md` slices A→D and do not mark map/call done if they cannot nest cogs.

---

## 9. Copy-paste command list for the next machine

```bash
cd sanad
mix deps.get
mix compile
mix test
mix sanad.execute examples/analyze_codebase.exs --module AnalyzeCodebase
```

Expect compile and example (chat/agent) to fail until keys/CLIs exist; `cmd`-only tests should pass after Slice A.
