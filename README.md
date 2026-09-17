# RoastEx

Rewrite Elixir dari [Shopify Roast](https://github.com/Shopify/roast) — DSL untuk *structured AI workflows*.

Roast asli adalah gem Ruby: workflow ditulis deklaratif, lalu “cogs” (`chat`, `agent`, `cmd`, `map`, …) dijalankan berantai. Output satu step bisa dipakai step berikutnya. RoastEx meniru model itu dengan **macro Elixir + Task** (bukan terjemahan 1:1 setiap file Ruby).

## Kenapa Elixir cocok

| Roast (Ruby) | RoastEx (Elixir) |
|---|---|
| `instance_eval` + proc | macro `use RoastEx.DSL` |
| `Async::Barrier` (gem `async`) | `Task.async_stream` |
| named cog output `chat!(:x)` | `chat!(ctx, :x)` |
| `cmd` lewat shell | `System.cmd` |
| provider HTTP | `Req` |

BEAM sudah kuat untuk I/O paralel (map over files, banyak call LLM). Itu bagian yang di Ruby harus dipasang gem async.

## Status rewrite

MVP, bukan port lengkap 889 commit:

- [x] DSL `execute` / `config` / `chat` / `cmd` / `agent` / `elixir` / `map`
- [x] Context + named outputs
- [x] Chat: OpenAI, Anthropic, Gemini
- [x] Agent: shell ke CLI `pi` atau `claude` (sama seperti Roast)
- [x] `mix roast.execute`
- [ ] `repeat`, `call` (reusable scopes), `skip!` / `fail!` / `break!`
- [ ] custom cog registry + `use MyCog`
- [ ] event monitor / pretty logger setara Roast
- [ ] tutorial 9 chapter

## Install

Butuh Elixir 1.16+ dan Mix.

```bash
cd roast_ex
mix deps.get
```

Env yang sama dengan Roast:

```bash
export OPENAI_API_KEY=...
# atau ANTHROPIC_API_KEY / GEMINI_API_KEY
export ROAST_DEFAULT_CHAT_PROVIDER=openai
export ROAST_DEFAULT_AGENT_PROVIDER=pi
```

## Contoh (padanan README Roast)

Ruby:

```ruby
execute do
  cmd(:recent_changes) { "git diff --name-only HEAD~5..HEAD" }

  agent(:review) do
    files = cmd!(:recent_changes).lines
    <<~PROMPT
      Review these recently changed files:
      #{files.join("\n")}
    PROMPT
  end

  chat(:summary) do
    "Summarize:\n\n#{agent!(:review).response}"
  end
end
```

Elixir (`examples/analyze_codebase.exs`):

```elixir
defmodule AnalyzeCodebase do
  use RoastEx.DSL

  config do
    %{chat: %{provider: :openai, model: "gpt-4o-mini"}}
  end

  execute do
    cmd(:recent_changes, "git diff --name-only HEAD~5..HEAD")

    agent :review do
      files = cmd!(ctx, :recent_changes).stdout
      """
      Review these recently changed files:
      #{files}
      """
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
```

Di dalam block, variabel `ctx` selalu di-bind. Helper: `cmd!/2`, `chat!/2`, `agent!/2`, `output!/2`.

## Arsitektur

```
Workflow module (macro)
        │
        ▼
  list of steps  [%{type, name, opts, fun}]
        │
        ▼
  RoastEx.Runner  (reduce + Context)
        │
        ├── Cogs.Cmd
        ├── Cogs.Chat   (Req → provider HTTP)
        ├── Cogs.Agent  (System.cmd → pi/claude)
        └── Cogs.ElixirCog
```

Tidak ada `instance_eval` string file (anti-pattern di Elixir). File `.exs` adalah modul biasa.

## Langkah berikutnya kalau mau mendekati Roast penuh

1. `repeat` + control flow (`skip`, `fail`, `next`, `break`) sebagai exception/`throw`.
2. `call` scope: named `execute :scope_name do` + rekursi Runner.
3. Behaviour `RoastEx.Cog` supaya cog custom di-compile, bukan hanya atom type.
4. Structured logging (teardown EventMonitor).
5. Tes ExUnit yang mem-port `examples/` Roast sebagai fixture.

## Lisensi

Roast asli MIT (Shopify). Port ini juga MIT; API dan ide workflow milik upstream.
