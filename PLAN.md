# RoastEx — execution plan

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done

## Objective / definition of done

Selesaikan rewrite Elixir dari Shopify Roast sampai **semua acceptance check di
`GAP_MAPPING.md` §4 (A–E) hijau**, dengan `mix compile` bersih, `mix test` hijau
tanpa network/API key, dan `README.md` yang jujur soal status.

Ditunda (bukan bagian "selesai" sekarang): tutorial 1–9, publish Hex, escript,
render log yang pixel-perfect.

## Keputusan yang sudah disetujui (jangan diubah tanpa konfirmasi user)

| # | Keputusan |
|---|---|
| D1 | Erlang+Elixir di-install via Homebrew; dev di Elixir terbaru, `mix.exs` tetap `~> 1.16`. |
| D2 | DSL idiomatik Elixir (macro), **bukan** transpile-compatible 1:1 Ruby. Tidak ada `instance_eval`/eval string. |
| D3 | `ruby` cog → step `:elixir` (alias `ruby` dipertahankan); return value mentah (bukan dibungkus struct), mirror Roast. |
| D4 | Chat cog: hand-rolled Req per provider (openai/anthropic/gemini/perplexity). Tanpa `req_llm`. Tes via `Req.Test`. |
| D5 | Nested `call`/`map`/`repeat` pakai `Task.Supervisor` eksplisit untuk fidelity: hasil partial urut + `nil` gap, `break!` membatalkan sibling, `parallel(n)`. |
| D6 | Semantik control flow meniru upstream: `skip!`/`next!` di-swallow, `fail!` gated `abort_on_failure` (default `true`), error lain selalu abort, pesan diabaikan. |
| D7 | Agent cog: invocation yang benar dulu (prompt via stdin, flag pi/claude upstream, `cd` = workflow_dir, error jelas). Parsing JSON protocol penuh (stats/session) = P2. |
| D8 | Tes wajib offline (`Req.Test`, stub CLI). Live smoke test opsional lewat env var. |
| D9 | Repo hygiene: git init + commit per slice, LICENSE MIT, `.gitignore`, `.formatter.exs`. README Indonesia, code docs English. |

## Slice A — foundation

- [x] A1 Fix DSL: step storage pakai generated function (hindari fun-in-attribute), `config` andal, block form `cmd`/`chat`/`agent` hidup, hilangkan arity clash & warning.
- [x] A2 `RoastEx.Cog` behaviour + `RoastEx.Cog.Registry` (builtin + override via application env). Runner pakai registry, bukan `case`.
- [x] A3 Control flow: `skip!/fail!/next!/break!` (throw), `abort_on_failure` per-step + global; status per output (`:ok/:skipped/:failed`).
- [x] A4 ExUnit: `test/test_helper.exs`, DSL compile tests, runner tests dengan fake cog + `:cmd`/`:elixir` (tanpa network).
- [x] A5 Fix B5 (map failure), B9 (unused alias), B10 (warning ctx), B18 (double wrap), B19/B20 (error jelas utk unknown type/name).

Gate: `mix compile` bersih + `mix test` hijau + acceptance §4.A. **PASSED** — 31 tests, `--warnings-as-errors` clean. Fix pasca-review: named scope attribute set saat expansion, map timeout `:infinity`, ctx-shadow detection, `Config.normalize([])`, fallback clause chat/agent, registry nil guard, `UnknownCogError` menyebut override, reason `fail!` disimpan, `validate_input/2` ditegakkan.

## Slice B — nested engine

- [x] B1 `execute :scope do` — named scopes, banyak scope per modul.
- [x] B2 `call` system cog (+ accessor `from` untuk output dalam).
- [x] B3 `map` (serial + parallel(n)) dengan nested steps; scope value/index; `collect`/`reduce`; hasil urut + `nil` gap.
- [x] B4 `repeat` (max_iterations guard, final output diteruskan, `break!`).
- [x] B5 Kebijakan namespacing output nested (child context terisolasi, akses via `from`/`collect`/`reduce`).

Gate: acceptance §4.B hijau. **PASSED** — 38 tests termasuk E2E `mix roast.execute examples/local_pipeline.exs`.

## Slice C — cog parity

- [x] C1 Cmd: `cwd`, `env`, `timeout`, stderr terpisah, `fail_on_error` (default true).
- [x] C2 Chat: status-code check, error jelas utk API key hilang, retry `:transient`, timeout, params `temperature`/`system_prompt`/`max_tokens`, provider Perplexity + config `base_url`/`api_key`/`key_env`.
- [x] C3 Agent: `cd` = workflow_dir, model/system-prompt/flags, missing-binary UX, prompt via stdin (pi/claude) + argv (opencode/agy), parser JSON protocol pi/claude.
- [x] C4 Config: resolusi terpusat (opts › workflow config › env), validasi provider (`InvalidConfigError`).

Gate: acceptance §4.C + §4.D hijau. **PASSED** — 68 tests; chat diuji via `Req.Test` (plug test-only), agent via stub CLI, cmd timeout via `RoastEx.Command`.

## Slice D — product polish

- [ ] D1 CLI: `--module` hardened, `--param key=value`, pesan error jelas.
- [ ] D2 Event log ringkas: `begin/end` tiap cog + scope, summary akhir (durasi, status), ganti `inspect` mentah.
- [ ] D3 Port 2–3 contoh upstream ke `examples/` + fixture test.
- [ ] D4 Update README status table + dokumentasi API final.

Gate: acceptance §4.E hijau + README jujur.

## Process

- Satu writer per working directory (parent agent).
- Setiap slice: implement → `mix format` → `mix compile` (warnings diperhatikan) → `mix test` → reviewer subagent (read-only) → commit.
- Live smoke test (provider/CLI asli) hanya jika env tersedia; kegagalan live tidak memblokir gate offline.
