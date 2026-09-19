# Sanad

Rewrite Elixir dari [Shopify Roast](https://github.com/Shopify/roast), DSL untuk structured AI workflows.

Roast asli adalah gem Ruby. Workflow ditulis deklaratif, lalu "cogs" (`chat`, `agent`, `cmd`, `map`, dan lainnya) dijalankan berantai. Output satu step bisa dipakai step berikutnya. Sanad meniru model itu dengan macro Elixir dan Task, bukan terjemahan baris per baris dari file Ruby.

## Kenapa Elixir

| Roast (Ruby) | Sanad (Elixir) |
|---|---|
| `instance_eval` + proc | macro `use Sanad.DSL` |
| `Async::Barrier` (gem `async`) | `Task.Supervisor` dengan pemantauan pesan |
| named output `chat!(:x)` | `chat!(ctx, :x)`, ctx eksplisit |
| `cmd` lewat Open3 | `Port`, stdout/stderr terpisah, ada timeout |
| provider HTTP | `Req` |
| scope nested (`call`/`map`/`repeat`) | `Context` anak terisolasi + `from`/`collect`/`reduce` |

BEAM sudah kuat untuk I/O paralel. Itu bagian yang di Ruby harus dipasang gem async.

## Status

MVP+ dengan divergensi yang didokumentasikan. Sudah bisa dipakai untuk workflow nyata.

| Area | Status |
|---|---|
| DSL `config` / `execute` / `execute :scope` | Ya |
| Cogs: `chat`, `cmd`, `agent`, `elixir_cog` (`ruby`), `map_cog`, `call_cog`, `repeat_cog` | Ya |
| Control flow `skip!` / `fail!` / `next!` / `break!` + `abort_on_failure` | Ya |
| Nested engine (child context terisolasi, `from`/`collect`/`reduce`) | Ya |
| Chat: OpenAI, Anthropic, Gemini, Perplexity, plus base_url/api_key/key_env per workflow | Ya |
| Agent: `pi`, `claude`, `opencode`, `agy` (prompt via stdin atau argv) | Ya |
| Cmd: stdout/stderr terpisah, `cwd`, `env`, `timeout`, `fail_on_error` | Ya |
| CLI: `mix sanad.execute` + escript `sanad`, `--module`, `--param` | Ya |
| Ringkasan run (status dan durasi per cog) | Ya |
| Tes ExUnit offline (Req.Test, stub CLI, E2E subprocess) | 123 tes |
| Event run (span workflow/scope/cog, stdout/stderr, block) + renderer ala Roast | Ya |
| Scope `outputs` / `outputs!` | Ya |
| Config per-nama dan regex (`chat(:x, ...)`, `chat(~r/.../, ...)`) | Ya |
| Streaming chat, JSON mode/tools, session normalization penuh | Belum |
| Tutorial 1-9, publish Hex | Ditunda |

## Install

Butuh Elixir 1.16+ dan Mix.

```bash
cd roast_ex
mix deps.get
mix test
```

## Quickstart tanpa API key

```bash
mix sanad.execute examples/local_pipeline.exs
# atau:
mix escript.build && ./sanad examples/local_pipeline.exs
```

`examples/local_pipeline.exs` memakai `cmd`, `elixir_cog`, `call_cog`, `map_cog` (paralel), dan `repeat_cog`. Tidak butuh network.

`examples/pi_and_claude.exs` menunjukkan jalur lengkapnya: agent `pi` mereview tiap file yang
berubah, Claude mengubah tiap review jadi satu baris putusan, dengan config per nama dan
`outputs` per scope. Butuh binary `pi` di PATH dan `ANTHROPIC_API_KEY`.

## Workflow

```elixir
defmodule AnalyzeCodebase do
  use Sanad.DSL

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
mix sanad.execute examples/analyze_codebase.exs --module AnalyzeCodebase
mix sanad.execute examples/params_demo.exs --param name=world --param loud=true
```

Di dalam block input, `ctx` selalu ter-bind. Helper yang tersedia:

| Helper | Keterangan |
|---|---|
| `cmd!/2`, `chat!/2`, `agent!/2`, `elixir!/2`, `output!/2` | baca output bernama, error jelas kalau belum jalan, skipped, atau failed |
| `params/1` | map params dari CLI |
| `status/2` | `:ok`, `:skipped`, atau `:failed` |
| `skip!/1`, `fail!/1`, `next!/1`, `break!/1` | control flow |
| `from/2`, `collect/1,2`, `reduce/3` | akses hasil scope nested |

### Cogs

```elixir
cmd(:name, "shell command")                       # :cwd, :env, :timeout, :fail_on_error
cmd :name, fail_on_error: false do "..." end
elixir_cog(:name, do: 1 + 1)                      # nilai mentah, padanan `ruby`
map_cog :name, scope: :one_item, parallel: 4 do [1, 2, 3] end
call_cog :name, scope: :inner, index: 0 do some_value end
repeat_cog :name, scope: :one_iteration, max_iterations: 10 do initial_value end
chat :name do "prompt" end
agent :name do "prompt" end
```

### Nilai balik scope

```elixir
execute :review_one do
  elixir_cog(:draft, do: String.upcase(ctx.scope_value))

  outputs do
    %{item: ctx.scope_value, draft: output!(ctx, :draft)}
  end
end
```

Tanpa `outputs`, sebuah scope mengembalikan output cog terakhirnya. Dengan
`outputs`, nilai itulah yang diterima `call`, tiap iterasi `map`, dan tiap
iterasi `repeat` (termasuk yang diteruskan ke iterasi berikutnya).

`skip!` dan `next!` di dalam blok membuat nilainya `nil`; `break!` juga, sambil
mengakhiri loop; `fail!` melempar `Sanad.OutputsFailedError`. Membaca cog yang
tidak sempat jalan karena `break!` ditelan (nilainya `nil`) supaya pemanggil
tidak perlu kode penjaga — pakai `outputs!` kalau ingin dilempar. Nama yang
tidak pernah dideklarasikan di scope itu selalu melempar, karena itu typo.

### Config per nama dan pola

```elixir
config do
  global(abort_on_failure: true)
  chat(provider: :openai, model: "gpt-4o-mini")
  chat(~r/^review_/, temperature: 0.0)
  chat(:summary, model: "gpt-4o")
end
```

Urutan merge, dari paling umum ke paling khusus: `global`, config umum per tipe
cog, semua pola yang cocok dengan nama cog (sesuai urutan penulisan), nama
persis, lalu opsi step yang tetap menang. Bentuk map yang lama tetap berlaku dan
tidak berubah artinya.

### Event run

Selama workflow jalan, CLI mencetak jejaknya ke stderr:

```
🔥🔥🔥 Workflow Starting
cmd(:echo) Starting
cmd(:echo) ❯ hello
map(:lengths) -> {:string_length}[2] Complete
🔥🔥🔥 Workflow Complete
```

Event dipancarkan lewat `:telemetry` dengan nama `[:sanad, :workflow | :scope |
:cog, :start | :stop | :exception]` plus `[:sanad, :cog, :stdout | :stderr |
:block | :log]`. Pasang handler sendiri lewat `Sanad.Event.names/0`, atau
matikan renderer bawaan dengan `--quiet`.

### Chat providers

| provider | key env | base URL env |
|---|---|---|
| `:openai` | `OPENAI_API_KEY` | `OPENAI_API_BASE` |
| `:anthropic` (alias `:claude`) | `ANTHROPIC_API_KEY` | `ANTHROPIC_API_BASE` |
| `:gemini` | `GEMINI_API_KEY` | `GEMINI_API_BASE` |
| `:perplexity` | `PERPLEXITY_API_KEY` | `PERPLEXITY_API_BASE` |

Default provider lewat `SANAD_DEFAULT_CHAT_PROVIDER`. Endpoint yang kompatibel dengan OpenAI, misalnya OpenRouter atau Cloudflare Workers AI, bisa dipakai lewat config workflow:

```elixir
config do
  %{chat: %{provider: :openai, model: "vendor/model",
            base_url: "https://openrouter.ai/api/v1",
            key_env: "OPENROUTER_API_KEY"}}
end
```

Model Claude punya alias pendek, jadi workflow tidak perlu menuliskan ID panjang:

```elixir
chat :summary, provider: :claude, model: :opus do
  "Ringkas ini: #{cmd!(ctx, :diff).stdout}"
end
```

`:opus` → `claude-opus-5`, `:sonnet` → `claude-sonnet-5`, `:haiku` → `claude-haiku-4-5`,
`:fable` → `claude-fable-5-1`. Alias yang tidak dikenal ditolak dengan daftar yang sah.

### Streaming, JSON mode, dan tool calls

```elixir
chat :draft, stream: true do
  "Tulis draf panjang tentang #{params(ctx).topic}"
end

chat :extract, json: true do
  "Kembalikan JSON dengan field title dan tags untuk: #{cmd!(ctx, :page).stdout}"
end

chat :maybe_tool, tools: [%{
  name: "get_weather",
  description: "Cuaca terkini sebuah kota",
  parameters: %{type: "object", properties: %{city: %{type: "string"}}}
}] do
  "Bagaimana cuaca di Bandung?"
end
```

`stream: true` memancarkan tiap delta sebagai event `stdout`, jadi token terlihat mengalir di
terminal, dan `response` tetap berisi teks utuh saat step selesai. Stream **tidak di-retry**:
mengulang berarti menayangkan ulang teks yang sudah dikirim ke pemanggil.

`json: true` memakai JSON mode native provider (`response_format` untuk OpenAI dan Perplexity,
`responseMimeType` untuk Gemini). Anthropic tidak punya JSON mode, dan sanad mengatakannya
terang-terangan alih-alih diam-diam mengabaikan — pakai tool dengan schema yang diinginkan.

Definisi tool ditulis sekali dalam bentuk netral (`name`, `description`, `parameters`) lalu
diterjemahkan ke bentuk tiap provider. Panggilan tool dikembalikan apa adanya di
`chat!(ctx, :name).tool_calls` sebagai `%{id:, name:, arguments:}` — sanad **tidak menjalankan**
tool untukmu; workflow yang memutuskan, misalnya lewat `elixir_cog` lalu `chat` berikutnya.

Opsi per step: `:provider`, `:model`, `:stream`, `:json`, `:response_format`, `:tools`,
`:tool_choice`, `:system_prompt`, `:temperature`, `:max_tokens`, `:api_key`, `:key_env`, `:base_url`, `:timeout`, `:max_retries`, `:req_options`. Request POST di-retry dengan `retry: :transient`. Error HTTP atau transport melempar `Sanad.ChatError` beserta status.

### Agent providers

| provider | invocation | prompt | response |
|---|---|---|---|
| `:pi` (default) | `pi --mode json -p ... (--fork SID \| --no-session)` | stdin | JSON protocol v3, teks dan session id |
| `:claude` | `claude -p --verbose --output-format stream-json ...` | stdin | stream-json, field `result` |
| `:opencode` | `opencode run <prompt>` | argv | teks |
| `:agy` | `agy -p <prompt>` | argv | teks |

Output agent berisi `response`, `session` (id percakapan provider, `nil` untuk provider tanpa
konsep session), dan `stats`:

```elixir
out = agent!(ctx, :review)
out.session                      # "sess-42" untuk pi, session_id untuk claude
out.stats.num_turns              # jumlah giliran, nil kalau tidak dilaporkan
out.stats.usage.input_tokens     # total token, plus output/cache_read/cache_write
out.stats.usage.cost_usd         # biaya kalau provider melaporkannya
out.stats.model_usage["pi-1"]    # rincian per model (pi)
```

Angka yang tidak dilaporkan provider bernilai `nil`, bukan `0`, supaya "tidak dilaporkan" tetap
bisa dibedakan dari "nol".

Default provider lewat `SANAD_DEFAULT_AGENT_PROVIDER`. `cd` default-nya `workflow_dir`. Binary yang tidak ketemu melempar `Sanad.MissingExecutableError`. Opsi: `:model`, `:system_prompt`, `:append_system_prompt`, `:session`, `:fork_session`, `:skip_permissions`, `:command`, `:env`, `:timeout`.

### Control flow

```elixir
elixir_cog :maybe do
  skip!()   # step ditandai :skipped, workflow lanjut
end

elixir_cog :checked do
  fail!("data invalid")   # abort kalau abort_on_failure: true (default)
end
```

- `skip!` tidak menghasilkan output, statusnya `:skipped`, workflow lanjut.
- `fail!` menandai `:failed` lalu abort bila `abort_on_failure` aktif (step opts lebih dulu, lalu config, default `true`). Error lain selalu abort.
- `next!` mengakhiri scope saat ini tanpa pesan.
- `break!` mengakhiri scope dan membatalkan sibling yang masih jalan di `map`. Hasil yang sudah selesai dipertahankan, slot yang tidak jalan berisi `nil`. Di scope teratas, step selanjutnya berhenti.

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

Setiap scope nested jalan di `Context` anak yang terisolasi. Output di dalam tidak terlihat dari luar, dan sebaliknya. Aksesnya lewat `from/2`, `collect/1,2`, dan `reduce/3`. `scope_value` dan `scope_index` meneruskan item dan index. `map_cog` mendukung `parallel: false | true | 0 | n`, `:timeout`, dan `:initial_index`. `repeat_cog` meneruskan output akhir iterasi ke iterasi berikutnya, dengan guard default 1000 iterasi. Isi `nil` atau `:infinity` untuk mematikan guard.

## CLI

```bash
mix sanad.execute path/to/workflow.exs [--module M] [--param key=value ...]
mix escript.build               # menghasilkan binary ./sanad
cp sanad ~/.local/bin/sanad     # taruh di PATH, pakai dari project mana pun
sanad path/to/workflow.exs --param key=value
```

Output berisi ringkasan (status dan durasi per cog) lalu inspect output lengkap. Workflow gagal menghasilkan exit code non-zero beserta pesan errornya.

## Testing

```bash
mix test
```

Semua tes offline:

- DSL, runner, control flow, nested engine: unit dan integrasi tanpa network.
- Chat: `Req.Test` (plug test-only) untuk 4 provider, error HTTP/transport, dan override config.
- Agent: stub executable `pi`, `claude`, `opencode`, `agy`.
- E2E: subprocess `mix sanad.execute` untuk pipeline penuh, scope, params, control flow, dan jalur gagal.

## Divergensi yang didokumentasikan

- `ruby` diganti `elixir_cog` yang mengembalikan nilai mentah. Tidak ada evaluasi string Ruby.
- Agent satu prompt per step. Upstream bisa multi-prompt dan merantai sesi. Opsi `:fork_session` untuk claude tersedia, default `true` saat `:session` diisi.
- Chat menambah `system_prompt`, `max_tokens`, `temperature`, retry, timeout, `PERPLEXITY_API_BASE`, dan override `base_url`/`api_key`/`key_env`. Upstream lebih minim.
- Event dipancarkan lewat `:telemetry`, bukan satu proses monitor dengan antrean. Konsekuensinya tidak ada urutan global: event dari iterasi `map` paralel saling menyela, dan hanya event satu path yang terurut penuh. Span cog di dalam iterasi yang di-*kill* `break!` tidak tertutup; scope di atasnya ditutup dengan `control: :cancelled`.
- Config per-nama memakai `chat(:x, model: "...")`, bukan blok `chat(:x) do ... end` — Elixir tidak punya receiver implisit, dan `instance_eval` tidak diport (keputusan D2).
- Heuristik `MaxTokensExceededError` dari upstream tidak direplikasi.
- `cmd :timeout` adalah tambahan Sanad, upstream tidak punya.

## Lisensi

MIT. Port ini juga MIT. API dan ide workflow milik upstream, Shopify/roast.
