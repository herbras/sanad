# Changelog

## 0.2.0

Rilis Hex pertama. Isinya parity dengan Shopify Roast untuk bagian yang sebelumnya kosong.

### Ditambahkan

- **Event run.** Span `start`/`stop`/`exception` untuk workflow, tiap scope bersarang, dan tiap
  cog, plus `stdout`, `stderr`, `block`, dan `log`. Tiap event membawa path tempat kejadiannya
  (`map(:reviewed) -> {:review_one}[2] -> cmd(:files)`). Dipancarkan lewat `:telemetry`, tanpa
  proses monitor: tidak ada urutan global, dan itu didokumentasikan.
- **Renderer** bergaya Roast di stderr, plus `--events jsonl` untuk dibaca program lain dan
  `--quiet` untuk mematikannya.
- **`outputs` dan `outputs!`** sebagai nilai balik scope, dengan semantik telan-atau-lempar
  mengikuti upstream.
- **Config per nama dan per pola**: `global(...)`, `chat(:nama, ...)`, `chat(~r/pola/, ...)`.
  Bentuk map lama tetap berlaku dan tidak berubah artinya.
- **Chat**: streaming (`stream: true`), JSON mode (`json: true`), dan tool calls yang
  dinormalisasi jadi `%{id, name, arguments}`. Sanad tidak menjalankan tool; workflow yang
  memutuskan.
- **Agent**: `session` dan `stats` (turn, token, cache, biaya, rincian per model) di
  `%Sanad.Output.Agent{}`.
- **Alias** `provider: :claude` dan alias model `:opus`, `:sonnet`, `:haiku`, `:fable`.
- **Tutorial** sembilan bab bahasa Indonesia di `tutorial/`, semua contohnya jalan tanpa API key.

### Diperbaiki

- Loop `receive` di cog `map` membuang setiap pesan tak dikenal di mailbox **proses pemanggil**,
  termasuk pesan milik pengguna. Klausa catch-all itu dihapus.
- `Sanad.Config.normalize/1` mengubah nilai keyword list jadi map. Kunci `:req_options`, `:env`,
  `:headers`, dan `:command` kini dilewatkan apa adanya — tanpa itu, config berskop akan merusak
  jalur yang dipakai semua tes chat.
- Respons streaming yang gagal melaporkan badan kosong, karena `Req` menyerahkan byte error ke
  collector dan membiarkan `resp.body` kosong.

### Catatan

- 77 tes menjadi 169.
- Tes baru menjalankan tiap berkas di `examples/` lewat escript, dan ada smoke test opsional
  terhadap CLI agent sungguhan (`mix test --include live_providers`).

## 0.1.0

MVP: DSL, runner rekursif, cog `chat`/`agent`/`cmd`/`elixir_cog`, engine nested
(`call`/`map`/`repeat`), kontrol alur, CLI, dan ringkasan run. Tidak dirilis ke Hex.
