# Bab 2 - Merantai cog

## Yang akan kamu mengerti

Cara hasil satu langkah mengalir ke langkah berikutnya. Ini inti Sanad.

## Konsep

Rantai artinya: langkah 2 membaca hasil langkah 1, langkah 3 membaca hasil langkah 2.

```
cmd(:data)  →  elixir_cog(:baris)  →  elixir_cog(:perlu_restok)
   teks            daftar rapi           kesimpulan
```

Yang menyambungkan mereka cuma satu hal: **nama**. Langkah berikutnya menulis
`output!(ctx, :baris)`, dan Sanad memberi hasil langkah bernama `:baris`.

## Jalankan

```bash
mix sanad.execute tutorial/02_merantai_cog/laporan_stok.exs
```

Hasil akhirnya: `"beras, minyak"` — barang yang stoknya di bawah lima.

## Kenapa dipecah jadi tiga langkah

Bisa saja semuanya ditulis dalam satu langkah. Tapi dipecah punya tiga untung:

1. **Kelihatan**. Saat jalan, kamu melihat langkah mana yang lambat atau gagal.
2. **Bisa dipakai lagi**. Langkah `:baris` bisa dibaca banyak langkah lain.
3. **Mudah diperbaiki**. Kalau hasil aneh, kamu tahu persis langkah mana yang salah.

## Pola yang sering dipakai

**Ambil → Olah → Simpulkan.** Hampir semua workflow bentuknya begini:

| Bidang | Ambil | Olah | Simpulkan |
|---|---|---|---|
| Gudang | baca stok | hitung yang menipis | daftar restok |
| Keuangan | tarik mutasi | kelompokkan per kategori | ringkasan bulanan |
| Penulis | baca draf | pecah per paragraf | saran perbaikan |
| Developer | `git diff` | pisahkan per berkas | catatan review |

## Menambahkan AI ke rantai

Langkah terakhir paling sering diganti AI, karena di situ butuh "penilaian", bukan hitungan:

```elixir
chat :pesan_wa do
  "Tulis pesan WhatsApp singkat dan sopan ke pemasok untuk restok: #{output!(ctx, :perlu_restok)}"
end
```

Bagian mengambil dan mengolah data tetap dikerjakan `cmd` dan `elixir_cog` — lebih murah,
lebih cepat, dan hasilnya pasti. AI dipakai hanya untuk bagian yang memang perlu bahasa.

## Latihan

Tambah satu langkah yang menghitung total seluruh stok, lalu sebutkan angkanya di hasil akhir.

Berikutnya: [Bab 3 - Params](../03_params/)
