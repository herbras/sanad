# Bab 1 - Workflow pertama

## Yang akan kamu mengerti

Apa itu workflow, apa itu cog, dan bagaimana menjalankannya.

## Konsep

**Workflow** adalah daftar pekerjaan. **Cog** adalah satu pekerjaan di daftar itu.

Setiap cog punya **nama**, ditulis dengan titik dua di depan: `:tanggal`, `:ucapan`.
Nama itu penting, karena langkah berikutnya memanggil hasil lewat nama tersebut.

Workflow ditulis di berkas `.exs`. Isinya satu modul Elixir yang memakai DSL Sanad:

```elixir
defmodule Salam do
  use Sanad.DSL

  execute do
    cmd(:tanggal, "date '+%A, %d %B %Y'")
  end
end
```

Baris demi baris:

- `defmodule Salam do` — nama workflow. Harus cocok dengan nama berkas: `salam.exs` → `Salam`.
- `use Sanad.DSL` — memberi tahu Elixir bahwa ini workflow Sanad.
- `execute do ... end` — isinya daftar langkah.
- `cmd(:tanggal, "date ...")` — langkah bernama `:tanggal`, yang menjalankan perintah terminal.

## Jalankan

```bash
mix sanad.execute tutorial/01_workflow_pertama/salam.exs
```

Di akhir kamu akan melihat ringkasan dan isi semua hasil:

```
Sanad workflow finished in 12ms: 2 ok, 0 skipped, 0 failed
  [ok] tanggal (9ms)
  [ok] ucapan (0ms)
```

Nama hari keluar dalam bahasa Inggris, karena `date` mengikuti locale sistem. Kalau mesinmu
punya locale Indonesia, `LC_TIME=id_ID.UTF-8 date '+%A'` akan berbahasa Indonesia.

## Membaca hasil langkah sebelumnya

Di dalam blok, variabel `ctx` selalu tersedia. Itu "papan tulis" tempat semua hasil disimpan.

| Cara baca | Untuk cog jenis apa |
|---|---|
| `cmd!(ctx, :nama)` | `cmd` — hasilnya punya `.stdout`, `.stderr`, `.status` |
| `chat!(ctx, :nama)` | `chat` — hasilnya punya `.response` |
| `agent!(ctx, :nama)` | `agent` — hasilnya punya `.response`, `.session`, `.stats` |
| `output!(ctx, :nama)` | jenis apa pun |

Tanda seru artinya: "kalau hasilnya belum ada, berhenti dan katakan kenapa". Itu lebih baik
daripada diam-diam bernilai kosong lalu bikin bingung di langkah kemudian.

## Kalau kamu ingin memakai AI

Ganti `elixir_cog` dengan `chat`. Isinya jadi kalimat perintah untuk AI:

```elixir
chat :ucapan do
  "Buat satu kalimat sapaan hangat untuk hari #{String.trim(cmd!(ctx, :tanggal).stdout)}"
end
```

Itu butuh API key, misalnya `OPENAI_API_KEY` atau `ANTHROPIC_API_KEY`.

## Latihan

Ubah `salam.exs` agar juga menjalankan `whoami` dan menyebut namamu di ucapan.

Berikutnya: [Bab 2 - Merantai cog](../02_merantai_cog/README.md)
