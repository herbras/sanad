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
| D10 | Toolchain lewat container (`bin/mix`), karena mesin kerja sekarang tidak punya Elixir di PATH. |
| D11 | Event dipancarkan lewat `:telemetry` tanpa proses monitor. Tidak ada urutan global; path event hidup di `Sanad.Context` supaya selamat menyeberang `Task.Supervisor`. |

## Keputusan yang masih perlu persetujuan

| # | Pertanyaan | Rekomendasi |
|---|---|---|
| Q1 | Pasang skill "TypeSafe" (`typesafe-ai/skills`) ke setup Claude Code? | Belum. Instruksinya datang dari teks tempelan, bukan dari repo ini, dan skill itu berorientasi TypeScript sementara repo ini Elixir. Perlu konfirmasi eksplisit sebelum menyentuh `~/.claude`. |
| Q2 | Urutan UI: setelah Slice G, mulai dari `--events jsonl`, lalu bridge OpenTelemetry, lalu laporan HTML satu berkas. | Setuju dulu sebelum skema event dianggap permukaan publik. |

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

- [x] E1 `Sanad.Event` plus path runtime (`chat(:x) -> {:scope}[0]`). Path hidup di `Sanad.Context`, jadi ikut tersalin ke proses anak `map`.
- [x] E2 Dispatch lewat `:telemetry` (sudah ada di `mix.lock` via finch/plug), renderer CLI, collector tes.
- [x] E3 Span start/stop/exception per workflow, scope, dan cog; `stdout` streaming dari cmd, `stderr`, `block` untuk prompt dan response.
- [ ] E4 `Sanad.Summary` diturunkan dari event. Ditunda: ringkasan sekarang masih dari `ctx.statuses`, jadi hanya mencakup scope teratas.

Gate: PASSED, 95 tests. Tes urutan event untuk scope nested, penutupan span saat `break!`, dan E2E yang mengecek format path plus `--quiet`.

Keputusan yang diambil di slice ini: tidak ada proses monitor dengan antrean. Konsekuensinya tidak ada urutan global; tes hanya boleh menegaskan urutan dalam satu path. Span cog di dalam iterasi yang di-kill tetap terbuka, dan itu didokumentasikan sebagai invarian.

## Slice F: scope outputs

Acuan upstream: `execution_manager.rb` (`bind_outputs`, `compute_final_output`).

- [x] F1 `outputs do ... end` dan `outputs! do ... end` sebagai metadata scope, satu per scope (dobel = CompileError).
- [x] F2 Nilai akhir untuk top-level (`ctx.final_output`), `call`, tiap child `map`, tiap iterasi `repeat`.
- [x] F3 Semantik swallow: `skip!`/`next!` jadi `nil`, `break!` juga sambil mengakhiri loop, `fail!` melempar `OutputsFailedError`; akses output skipped/not-run ditelan `outputs` tapi dilempar `outputs!`. Nama yang tidak dideklarasikan selalu dilempar.

Gate: PASSED, 108 tests. test/nested_test.exs tidak diubah dan tetap hijau.

## Slice G: config per-nama dan regex

Acuan upstream: `config_manager.rb` (`config_for`).

- [x] G1 `config do global(...); chat(:x, ...); chat(~r/.../, ...) end`, dipilih lewat bentuk AST; bentuk map lama tetap jalan, blok campuran ditolak.
- [x] G2 Urutan merge: global, general per-cog, semua regex yang match (urutan penulisan), nama persis, lalu opsi step.
- [ ] G3 Preflight validasi sebelum step pertama jalan. Ditunda: validasi masih terjadi saat cog jalan, sama seperti upstream.

Gate: PASSED, 123 tests. Semua contoh dan snippet README resolve identik; `normalize/1` tidak lagi merusak opsi bernilai keyword list.

## Slice H: chat dan agent lanjutan

- [ ] H1 Streaming chat yang mengemit event `stdout` (butuh Slice E).
- [ ] H2 JSON mode dan tool calls.
- [ ] H3 Normalisasi session lintas provider agent.

Gate: `Req.Test` untuk stream chunked dan tool call; stub CLI untuk session round-trip.

## Slice J: dukungan kelas satu untuk pi dan model Claude

Keadaan sekarang: `pi` sudah provider agent default (`pi --mode json -p`, `--fork`, parser
protokol JSON), dan Anthropic sudah provider chat. Yang kurang adalah kelas satunya.

- [ ] J1 Alias `provider: :claude` untuk chat Anthropic, plus default model yang masuk akal
      (`claude-opus-5` untuk kerja berat, `claude-haiku-4-5` untuk yang murah) dan alias model
      pendek supaya workflow tidak menuliskan ID panjang.
- [ ] J2 Parity pi: normalisasi session lintas provider (lihat H3), plus stats dan usage
      (token, biaya) dari protokol pi masuk ke `%Sanad.Output.Agent{}`. Acuan upstream:
      `lib/roast/cogs/agent/stats.rb` dan `usage.rb`.
- [ ] J3 Smoke test live opsional di balik env (`SANAD_LIVE=1`): satu panggilan pi asli dan satu
      panggilan Anthropic asli. Tidak jalan di CI, tidak memblokir gate offline (keputusan D8).

Gate: workflow contoh yang memakai `agent(:x)` dengan pi dan `chat(:y)` dengan Claude jalan tanpa
konfigurasi tambahan selain API key; tes offline tetap hijau.

## Slice I: rilis (ditunda sampai diminta)

- [ ] I1 Tutorial 1-9.
- [ ] I2 Publish Hex. Dilakukan setelah Slice G karena config adalah perubahan API publik terakhir.

## Process

- Satu writer per working directory.
- Setiap slice: implement, `mix format`, `mix compile`, `mix test`, reviewer subagent read-only, lalu commit.
- Live smoke test provider atau CLI asli hanya jika env tersedia. Kegagalan live tidak memblokir gate offline.
