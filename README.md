# RoastEx

Rewrite Elixir dari [Shopify Roast](https://github.com/Shopify/roast) — DSL untuk *structured AI workflows*.

Roast asli adalah gem Ruby: workflow ditulis deklaratif, lalu "cogs" (`chat`, `agent`, `cmd`, `map`, …) dijalankan berantai. Output satu step bisa dipakai step berikutnya. RoastEx meniru model itu dengan **macro Elixir + Task** (bukan terjemahan 1:1 file Ruby).

## Kenapa Elixir cocok

| Roast (Ruby) | RoastEx (Elixir) |
|---|---|
| `instance_eval` + proc | macro `use RoastEx.DSL` |
| `Async::Barrier` (gem `async`) | `Task.Supervisor` + message-based monitoring |
| named cog output `chat!(:x)` | `chat!(ctx, :x)` (ctx eksplisit) |
| `cmd` lewat Open3 | `Port` (stdout/stderr terpisah, timeout) |
| provider HTTP | `Req` |
| scope nested (`call`/`map`/`repeat`) | child `Context` terisolasi + `from`/`collect`/`reduce` |

BEAM sudah kuat untuk I/O paralel; itu bagian yang di Ruby harus dipasang gem async.

## Status

**MVP+ — siap dipakai untuk workflow nyata, dengan divergensi yang didokumentasikan.**

| Area | Status |
|---|---|
| DSL `config` / `execute` / `execute :scope` | ✅ |
| Cogs: `chat`, `cmd`, `agent`, `elixir_cog` (`ruby`), `map_cog`, `call_cog`, `repeat_cog` | ✅ |
| Control flow `skip!` / `fail!` / `next!` / `break!` + `abort_on_failure` | ✅ |
| Nested engine (child context terisolasi, `from`/`collect`/`reduce`) | ✅ |
| Chat: OpenAI, Anthropic, Gemini, Perplexity (+ base_url/api_key/key_env per workflow) | ✅ |
| Agent: `pi`, `claude`, `opencode`, `agy` (prompt via stdin/argv, JSON protocol pi/claude) | ✅ |
| Cmd: stdout/stderr terpisah, `cwd`, `env`, `timeout`, `fail_on_error` | ✅ |
| CLI: `mix roast.execute` + escript `roast`, `--module`, `--param` | ✅ |
| Ringkasan run (status + durasi per cog) | ✅ |
| Tes ExUnit offline (Req.Test, stub CLI, E2E subprocess) | ✅ 72 tes |
| Event monitor setara Roast (render `🔥`, block events, dst.) | ⬜ belum |
| Scope `outputs { }` / `outputs! { }` | ⬜ belum |
| Config per-nama/regex (`chat(:x) do …`) | ⬜ belum |
| Streaming, JSON mode/tools, session normalization penuh | ⬜ belum |
| Tutorial 1–9, publish Hex | ⬜ ditunda |

## Install

Butuh Elixir 1.16+ dan Mix.

```bash
cd roast_ex
mix deps.get
mix test
```

## Quickstart (tanpa API key)

```bash
mix roast.execute examples/local_pipeline.exs
# atau:
mix escript.build && ./roast examples/local_pipeline.exs
```

`examples/local_pipeline.exs` memakai `cmd` + `elixir_cog` + `call_cog` + `map_cog` (paralel) + `repeat_cog` — tidak butuh network.

## Workflow

```elixir
defmodule AnalyzeCodebase do
  use RoastEx.DSL

  config do
    %{
      chat: %{provider: :openai, model: "gpt-4o-mini"},
      agent: %{provider: :pi},
      abort_on_failure: true
    }
  end

  execute do
    cmd(:recent_changes, "git diff --name-only HEAD~5..HEAD")

    agent :review do
      files = cmd!(ctx, :recent_changes).stdout
      "Review these recently changed files:\n\n#{files}"
    end

    chat :summary do
      "Summarize:\n\n#{agent!(ctx, :review).response}"
    end
  end
end
```

Jalankan:

```bash
mix roast.execute examples/analyze_codebase.exs --module AnalyzeCodebase
mix roast.execute examples/params_demo.exs --param name=world --param loud=true
```

Di dalam block input, `ctx` selalu ter-bind. Helper yang tersedia:

| Helper | Keterangan |
|---|---|
| `cmd!/2`, `chat!/2`, `agent!/2`, `elixir!/2`, `output!/2` | baca output bernama (error jelas kalau belum jalan / skipped / failed) |
| `params/1` | map params dari CLI |
| `status/2` | `:ok` / `:skipped` / `:failed` |
| `skip!/1`, `fail!/1`, `next!/1`, `break!/1` | control flow |
| `from/2`, `collect/1,2`, `reduce/3` | akses hasil scope nested |

### Cogs

```elixir
cmd(:name, "shell command")                       # :cwd, :env, :timeout, :fail_on_error
cmd :name, fail_on_error: false do "…" end
elixir_cog(:name, do: 1 + 1)                      # nilai mentah (padanan `ruby`)
map_cog :name, scope: :one_item, parallel: 4 do [1, 2, 3] end
call_cog :name, scope: :inner, index: 0 do some_value end
repeat_cog :name, scope: :one_iteration, max_iterations: 10 do initial_value end
chat :name do "prompt" end
agent :name do "prompt" end
```

### Chat providers

| provider | key env | base URL env |
|---|---|---|
| `:openai` | `OPENAI_API_KEY` | `OPENAI_API_BASE` |
| `:anthropic` | `ANTHROPIC_API_KEY` | `ANTHROPIC_API_BASE` |
| `:gemini` | `GEMINI_API_KEY` | `GEMINI_API_BASE` |
| `:perplexity` | `PERPLEXITY_API_KEY` | `PERPLEXITY_API_BASE` |

Default provider via `ROAST_DEFAULT_CHAT_PROVIDER`. Endpoint OpenAI-compatible (OpenRouter, Cloudflare Workers AI, dst.) bisa lewat config workflow:

```elixir
config do
  %{chat: %{provider: :openai, model: "vendor/model",
            base_url: "https://openrouter.ai/api/v1",
            key_env: "OPENROUTER_API_KEY"}}
end
```

Opsi per step: `:provider`, `:model`, `:system_prompt`, `:temperature`, `:max_tokens`, `:api_key`, `:key_env`, `:base_url`, `:timeout`, `:max_retries`, `:req_options`. Request POST di-retry dengan `retry: :transient`; error HTTP/transport melempar `RoastEx.ChatError` dengan status.

### Agent providers

| provider | invocation | prompt | response |
|---|---|---|---|
| `:pi` (default) | `pi --mode json -p … (--fork SID \| --no-session)` | stdin | JSON protocol v3 (parse teks + session id) |
| `:claude` | `claude -p --verbose --output-format stream-json …` | stdin | stream-json (`result`) |
| `:opencode` | `opencode run <prompt>` | argv | teks |
| `:agy` | `agy -p <prompt>` | argv | teks |

Default provider via `ROAST_DEFAULT_AGENT_PROVIDER`. `cd` default = `workflow_dir`; binary hilang → `RoastEx.MissingExecutableError`; opsi: `:model`, `:system_prompt`, `:append_system_prompt`, `:session`, `:skip_permissions`, `:command`, `:env`, `:timeout`.

### Control flow

```elixir
elixir_cog :maybe do
  skip!()   # step ditandai :skipped, workflow lanjut
end

elixir_cog :checked do
  fail!("data invalid")   # abort kalau abort_on_failure: true (default)
end
```

- `skip!` — tanpa output, status `:skipped`, lanjut.
- `fail!` — status `:failed`; abort bila `abort_on_failure` (step opts › config › default `true`). Error lain **selalu** abort.
- `next!` — mengakhiri scope saat ini (diam-diam).
- `break!` — mengakhiri scope + membatalkan sibling yang masih jalan di `map` (hasil yang sudah selesai dipertahankan, slot yang tidak jalan `nil`); di scope teratas menghentikan step selanjutnya.

### Nested scopes

```elixir
execute :review_one do
  elixir_cog(:upper, do: String.upcase(ctx.scope_value))
end

execute do
  map_cog :reviewed, scope: :review_one, parallel: 2 do
    ["a", "b", "c"]
  end

  call_cog :one, scope: :review_one do "x" end

  elixir_cog :report do
    upper = from(output!(ctx, :one), fn child -> output!(child, :upper) end)
    collected = collect(output!(ctx, :reviewed))
    reduced = reduce(output!(ctx, :reviewed), "", fn acc, item -> acc <> item end)
    {upper, collected, reduced}
  end
end
```

Setiap scope nested berjalan di `Context` anak yang terisolasi: output dalam tidak terlihat dari luar (dan sebaliknya); akses lewat `from/2`, `collect/1,2`, `reduce/3`. `scope_value`/`scope_index` meneruskan item/index; `map_cog` mendukung `parallel: false | true | 0 | n`, `:timeout`, `:initial_index`; `repeat_cog` meneruskan output akhir iterasi ke iterasi berikutnya (guard default 1000 iterasi; `nil`/`:infinity` mematikan guard).

## CLI

```bash
mix roast.execute path/to/workflow.exs [--module M] [--param key=value ...]
mix escript.build        # menghasilkan binary ./roast
./roast path/to/workflow.exs --param key=value
```

Output berisi ringkasan (status + durasi per cog) lalu inspect output lengkap. Workflow gagal → exit code non-zero dengan pesan error.

## Testing

```bash
mix test
```

Semua tes offline:

- DSL/runner/control flow/nested engine: unit + integrasi tanpa network.
- Chat: `Req.Test` (plug test-only) untuk 4 provider, error HTTP/transport, config override.
- Agent: stub executable `pi`/`claude`/`opencode`/`agy`.
- E2E: subprocess `mix roast.execute` untuk pipeline penuh, scope, params, control flow, dan jalur gagal.

## Divergensi yang didokumentasikan

- `ruby` → `elixir_cog` (nilai mentah; tidak ada evaluasi string Ruby).
- Belum ada `outputs { }` / `outputs! { }` untuk nilai balik scope (default: output cog terakhir).
- Belum ada config per-nama/regex ala Roast (`chat(:x) do … end`); pakai opsi step.
- Event rendering Roast (`🔥`, `❯`, block events) belum direplikasi; RoastEx punya ringkasan run.
- `MaxTokensExceededError` heuristik upstream tidak direplikasi.
- `cmd :timeout` adalah tambahan RoastEx (upstream tidak punya).

## Lisensi

MIT. Port ini juga MIT; API dan ide workflow milik upstream (Shopify/roast).
