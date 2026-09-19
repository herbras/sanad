# Bab 6 - Scope pakai ulang

## Yang akan kamu mengerti

Cara menulis sekumpulan langkah **sekali**, lalu memanggilnya berkali-kali dengan isi berbeda.

## Konsep

Sejauh ini kita menulis `execute do ... end` tanpa nama. Itu blok utama.

Kamu juga boleh menulis blok **bernama**:

```elixir
execute :satu_tiket do
  ...
end
```

Blok bernama tidak jalan sendiri. Ia menunggu dipanggil:

```elixir
call_cog(:tiket_a, scope: :satu_tiket, do: "paket saya lambat sekali")
```

Anggap saja seperti resep terpisah: "cara membalas satu tiket". Lalu kamu pakai resep itu
untuk tiket A dan tiket B.

## `scope_value` — isi yang dikirim

Nilai yang kamu berikan saat memanggil masuk ke `ctx.scope_value`:

```elixir
elixir_cog :kategori do
  teks = ctx.scope_value   # "paket saya lambat sekali"
  ...
end
```

## Papan tulis terpisah

Ini bagian penting. Tiap pemanggilan punya **papan tulis sendiri**. Langkah di dalam scope
tidak bisa melihat hasil di luar, dan sebaliknya.

Kenapa begitu? Supaya nama tidak bertabrakan. Tiket A dan tiket B sama-sama punya langkah
bernama `:kategori`, dan keduanya aman karena berada di papan berbeda.

Untuk mengintip ke dalam, pakai `from/2`:

```elixir
from(output!(ctx, :tiket_a), fn dalam -> output!(dalam, :kategori) end)
```

## `outputs` — menentukan nilai balik

Secara bawaan, sebuah scope mengembalikan hasil langkah **terakhir**nya. Sering kali kamu
ingin mengatur sendiri:

```elixir
outputs do
  %{kategori: output!(ctx, :kategori), draf: output!(ctx, :draf)}
end
```

Bacanya lewat `.value`:

```elixir
output!(ctx, :tiket_a).value.kategori
```

Ada versi ketatnya, `outputs!`. Bedanya: kalau di dalam blok kamu membaca langkah yang
ternyata tidak sempat jalan, `outputs` diam-diam memberi `nil`, sedangkan `outputs!`
menghentikan dan memberi tahu. Pakai `outputs` kalau memang wajar ada yang kosong (misalnya
setelah `break!`), pakai `outputs!` kalau semuanya harus ada.

## Jalankan

```bash
mix sanad.execute tutorial/06_scope_pakai_ulang/balasan.exs
```

## Contoh lintas bidang

| Bidang | Scope-nya | Dipanggil untuk |
|---|---|---|
| Customer service | "balas satu tiket" | tiap tiket masuk |
| Guru | "nilai satu jawaban" | tiap siswa |
| Rekrutmen | "ringkas satu CV" | tiap pelamar |
| Developer | "review satu berkas" | tiap berkas berubah |

## Latihan

Tambah satu tiket lagi, lalu buat `:ringkasan` menyebut ketiganya.

Berikutnya: [Bab 7 - Banyak item](../07_banyak_item/)
