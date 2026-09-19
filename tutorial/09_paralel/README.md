# Bab 9 - Paralel

## Yang akan kamu mengerti

Cara mengerjakan beberapa hal bersamaan, dan apa yang berubah saat kamu melakukannya.

## Konsep

Tambahkan `parallel:` pada `map_cog`:

```elixir
map_cog :cek, scope: :satu_cek, parallel: 3 do
  output!(ctx, :daftar)
end
```

| Nilai | Artinya |
|---|---|
| `false` (bawaan) | satu per satu |
| `3` | paling banyak tiga bersamaan |
| `true` | sebanyak inti prosesor |
| `0` | semuanya sekaligus, tanpa batas |

Kalau tiap pengecekan butuh 2 detik dan ada 3 pengecekan: berurutan 6 detik, paralel 2 detik.
Untuk pekerjaan yang isinya **menunggu** — menunggu jaringan, menunggu AI menjawab, menunggu
perintah selesai — ini beda yang besar.

## Yang tidak berubah

**Urutan hasil.** `collect` tetap mengembalikan hasil sesuai urutan daftar masukan, bukan
urutan siapa selesai duluan. Laporanmu tetap rapi.

## Yang berubah

**Urutan tampilan di layar.** Baris-baris dari beberapa item akan saling menyela:

```
map(:cek) -> {:satu_cek}[0] Starting
map(:cek) -> {:satu_cek}[2] Starting
map(:cek) -> {:satu_cek}[0] Complete
map(:cek) -> {:satu_cek}[1] Starting
```

Itu wajar, bukan tanda rusak. Angka dalam kurung siku menunjukkan item ke berapa, jadi kamu
tetap bisa mengikuti jalannya masing-masing.

Kalau kamu butuh urutan yang bisa dibaca program, pakai `--events jsonl` lalu saring per
jalur.

## Kalau satu item gagal

Satu item yang melempar error akan **menghentikan saudaranya** yang masih jalan, lalu
errornya diteruskan ke pemanggil. Kalau kamu tidak mau begitu — misalnya satu server mati
tidak boleh membatalkan pengecekan server lain — tangani di dalam item itu sendiri:

```elixir
cmd :jalankan, fail_on_error: false do
  ctx.scope_value.perintah
end
```

Dengan `fail_on_error: false`, perintah yang keluar dengan status bukan nol tidak dianggap
bencana. Kamu yang memutuskan artinya.

## Jalankan

```bash
mix sanad.execute tutorial/09_paralel/cek_layanan.exs
```

Satu pengecekan memang sengaja dibuat gagal, supaya kamu melihat bagaimana hasilnya dilaporkan
tanpa membatalkan yang lain.

## Contoh lintas bidang

| Bidang | Dikerjakan paralel |
|---|---|
| Ops | cek banyak server |
| Peneliti | ringkas banyak dokumen |
| Toko online | tulis deskripsi banyak produk |
| Media | terjemahkan banyak artikel |

## Seberapa besar `parallel` sebaiknya

Untuk panggilan AI berbayar, mulai dari kecil — 2 sampai 4. Penyedia API punya batas
kecepatan, dan biaya naik seiring jumlah panggilan. Untuk perintah lokal yang ringan, angka
lebih besar aman.

## Selesai

Kamu sudah melewati sembilan bab. Langkah berikutnya: buka `examples/` di repo ini untuk
melihat workflow yang lebih panjang, termasuk `examples/pi_and_claude.exs` yang memakai agent
`pi` dan model Claude bersamaan.
