# Sanad execution plan

> STATUS: Slice A sampai D tuntas, 77 tes hijau, `mix compile --warnings-as-errors` bersih, E2E CLI (mix task dan escript) terverifikasi. Lanjutan parity ada di Slice 0 sampai I di bawah.

Status legend: `[ ]` todo, `[~]` in progress, `[x]` done.

## Objective

Selesaikan rewrite Elixir dari Shopify Roast sampai semua acceptance check di `GAP_MAPPING.md` §4 (A sampai E) hijau, dengan `mix compile` bersih, `mix test` hijau tanpa network atau API key, dan `README.md` yang jujur soal status.

Ditunda, bukan bagian "selesai" sekarang: tutorial 1-9, publish Hex, dan render log yang persis sama dengan upstream.

## Keputusan yang sudah disetujui

| # | Keputusan |
|---|---|
| D1 | Erlang dan Elixir di-install lewat Homebrew. Dev memakai Elixir terbaru, `mix.exs` tetap `~> 1.16`. |
| D2 | DSL idiomatik Elixir, bukan transpile 1:1 dari Ruby. Tidak ada `instance_eval` atau eval string. |
| D3 | `ruby` cog menjadi step `:elixir`, alias `ruby` dipertahankan. Return value mentah, bukan struct. |
| D4 | Chat cog memakai Req per provider (openai, anthropic, gemini, perplexity). Tanpa `req_llm`. Tes lewat `Req.Test`. |
| D5 | Nested `call`/`map`/`repeat` memakai `Task.Supervisor` eksplisit untuk fidelity: hasil partial urut, `nil` gap, `break!` membatalkan sibling, `parallel(n)`. |
| D6 | Control flow meniru upstream. `skip!` dan `next!` di-swallow, `fail!` digating `abort_on_failure` (default `true`), error lain selalu abort, pesan diabaikan. |
| D7 | Agent cog: invocation benar dulu (prompt via stdin, flag pi/claude upstream, `cd` sama dengan workflow_dir, error jelas). Parsing stats penuh masuk P2. |
| D8 | Tes wajib offline (`Req.Test`, stub CLI). Live smoke test opsional lewat env var. |
| D9 | Hygiene: git init dan commit per slice, LICENSE MIT, `.gitignore`, `.formatter.exs`. README bahasa Indonesia, docs kode bahasa Inggris. |

## Slice A: foundation

- [x] A1 Fix DSL: step storage memakai generated function, `config` andal, block form `cmd`/`chat`/`agent` hidup, arity clash dan warning hilang.
- [x] A2 `Sanad.Cog` behaviour dan `Sanad.Cog.Registry` (builtin plus override lewat application env). Runner memakai registry, bukan `case`.
- [x] A3 Control flow: `skip!/fail!/next!/break!` dengan throw, `abort_on_failure` per step dan global, status per output (`:ok`, `:skipped`, `:failed`).
- [x] A4 ExUnit: `test/test_helper.exs`, DSL compile tests, runner tests dengan fake cog serta `:cmd` dan `:elixir` tanpa network.
- [x] A5 Fix B5 (map failure), B9 (unused alias), B10 (warning ctx), B18 (double wrap), B19 dan B20 (error jelas untuk unknown type/name).

Gate: `mix compile` bersih, `mix test` hijau, acceptance §4.A. PASSED, 31 tests dan `--warnings-as-errors` clean. Fix pasca-review: named scope attribute saat expansion, map timeout `:infinity`, ctx-shadow detection, `Config.normalize([])`, fallback clause chat/agent, registry nil guard, `UnknownCogError` menyebut override, reason `fail!` disimpan, `validate_input/2` ditegakkan.

## Slice B: nested engine

- [x] B1 `execute :scope do`, named scopes, banyak scope per modul.
- [x] B2 `call` system cog plus accessor `from` untuk output dalam.
- [x] B3 `map` serial dan paralel dengan nested steps, scope value/index, `collect`/`reduce`, hasil urut dan `nil` gap.
- [x] B4 `repeat` dengan max_iterations guard, final output diteruskan, `break!`.
- [x] B5 Namespacing output nested: child context terisolasi, akses via `from`/`collect`/`reduce`.

Gate: acceptance §4.B hijau. PASSED, 38 tests termasuk E2E `mix sanad.execute examples/local_pipeline.exs`.

## Slice C: cog parity

- [x] C1 Cmd: `cwd`, `env`, `timeout`, stderr terpisah, `fail_on_error` default true.
- [x] C2 Chat: status-code check, error jelas untuk API key hilang, retry `:transient`, timeout, params `temperature`/`system_prompt`/`max_tokens`, provider Perplexity, plus config `base_url`/`api_key`/`key_env`.
- [x] C3 Agent: `cd` sama dengan workflow_dir, model dan flags, missing-binary UX, prompt via stdin (pi/claude) atau argv (opencode/agy), parser JSON protocol.
- [x] C4 Config: resolusi terpusat (opts, lalu workflow config, lalu env), validasi provider lewat `InvalidConfigError`.

Gate: acceptance §4.C dan §4.D hijau. PASSED, 68 tests. Chat diuji via `Req.Test`, agent via stub CLI, cmd timeout via `Sanad.Command`.

## Slice D: product polish

- [x] D1 CLI: `--module` diharden untuk nama file non-alnum, `--param key=value`, pesan error jelas, dipakai `mix sanad.execute` dan escript `sanad`.
- [x] D2 Ringkasan run: status dan durasi per cog (`Sanad.Summary`). Inspect mentah tetap dicetak setelahnya. EventMonitor penuh belum.
- [x] D3 Port 2 contoh upstream: `examples/control_flow.exs` (tutorial 05) dan `examples/reusable_scopes.exs` (tutorial 06), plus E2E.
- [x] D4 Update README: status, API final, divergensi.

Gate: acceptance §4.E hijau (file loading dan `--param`). PASSED, 72 tests termasuk E2E CLI jalur sukses dan gagal.

## Slice 0: toolchain

- [x] 0A `bin/mix`: wrapper Docker (`elixir:1.18-alpine`), uid pemanggil, `MIX_BUILD_ROOT=_build/container` supaya tidak bentrok dengan `_build` native.
- [x] 0B CI GitHub Actions: `format --check-formatted`, `compile --warnings-as-errors`, `test`.

Gate: `bin/mix test` hijau di mesin tanpa Elixir. PASSED, 77 tests.

## Slice E: event system

Acuan upstream: `lib/roast/event.rb`, `event_monitor.rb`, `task_context.rb`, `output_router.rb`.

- [ ] E1 `Sanad.Event` plus path runtime (`chat(:x) -> {:scope}[0]`), termasuk propagasi lintas proses di `map` paralel.
- [ ] E2 Dispatch event dan handler yang bisa dipasang: renderer CLI, collector tes.
- [ ] E3 Emisi `begin`/`end` per cog di runner, `stdout`/`stderr` dari cmd, `block` untuk prompt dan response.
- [ ] E4 Hubungan dengan `Sanad.Summary`: ringkasan diturunkan dari event, bukan jalur terpisah.

Gate: tes urutan event untuk scope nested, perilaku saat `break!`, dan E2E yang mengecek format path.

## Slice F: scope outputs

Acuan upstream: `execution_manager.rb` (`bind_outputs`, `compute_final_output`).

- [ ] F1 `outputs do ... end` dan `outputs! do ... end` sebagai metadata scope, satu per scope.
- [ ] F2 Nilai akhir untuk top-level, `call`, tiap child `map`, tiap iterasi `repeat`.
- [ ] F3 Semantik swallow: `skip!`/`next!` jadi `nil`, `fail!` tetap raise, akses output skipped/not-run ditelan `outputs` tapi dilempar `outputs!`.

Gate: scope tanpa `outputs` berperilaku persis seperti sekarang; test/nested_test.exs tidak berubah hasilnya.

## Slice G: config per-nama dan regex

Acuan upstream: `config_manager.rb` (`config_for`).

- [ ] G1 Surface config bernama dan regex, tanpa merusak bentuk map yang sekarang.
- [ ] G2 Urutan merge: global, general per-cog, semua regex yang match (berurutan), nama persis, lalu opsi step.
- [ ] G3 Validasi nilai per scope config dengan `InvalidConfigError`.

Gate: semua contoh di README dan `examples/` resolve identik; tes prioritas merge lengkap.

## Slice H: chat dan agent lanjutan

- [ ] H1 Streaming chat yang mengemit event `stdout` (butuh Slice E).
- [ ] H2 JSON mode dan tool calls.
- [ ] H3 Normalisasi session lintas provider agent.

Gate: `Req.Test` untuk stream chunked dan tool call; stub CLI untuk session round-trip.

## Slice I: rilis (ditunda sampai diminta)

- [ ] I1 Tutorial 1-9.
- [ ] I2 Publish Hex. Dilakukan setelah Slice G karena config adalah perubahan API publik terakhir.

## Process

- Satu writer per working directory.
- Setiap slice: implement, `mix format`, `mix compile`, `mix test`, reviewer subagent read-only, lalu commit.
- Live smoke test provider atau CLI asli hanya jika env tersedia. Kegagalan live tidak memblokir gate offline.
