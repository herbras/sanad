# Bab 7 - Banyak item

## Yang akan kamu mengerti

Cara mengerjakan satu daftar: tiap item diproses dengan langkah yang sama.

## Konsep

`map_cog` adalah "lakukan ini untuk setiap item".

```elixir
map_cog :nilai, scope: :satu_siswa, parallel: 3 do
  output!(ctx, :daftar)
end
```

Tiga bagiannya:

- `scope: :satu_siswa` — resep yang dipakai untuk tiap item (blok `execute :satu_siswa`).
- blok `do` — daftarnya. Harus menghasilkan list.
- `parallel: 3` — berapa item boleh dikerjakan bersamaan. Lihat Bab 9.

Tiap item masuk ke `ctx.scope_value`, dan urutannya ada di `ctx.scope_index` (mulai dari 0).

## Mengambil hasilnya

| Cara | Untuk apa |
|---|---|
| `collect(output!(ctx, :nilai))` | daftar semua hasil, urutannya sama dengan daftar masukan |
| `collect(hasil, fn h -> ... end)` | sama, tapi tiap hasil diolah dulu |
| `reduce(hasil, awal, fn acc, h -> ... end)` | meringkas jadi satu nilai |
| `from(hasil, fn dalam -> ... end)` | mengintip langkah **di dalam** tiap item |

Hasil selalu **urut sesuai daftar masukan**, bukan sesuai siapa yang selesai duluan. Ini
penting: meski dikerjakan bersamaan, laporanmu tetap rapi.

## Jalankan

```bash
mix sanad.execute tutorial/07_banyak_item/nilai_tugas.exs
```

## Kalau ada yang berhenti di tengah

Kalau satu item memanggil `break!`, item yang belum selesai dihentikan, dan tempatnya di
daftar hasil diisi `nil`. Item yang sudah selesai tetap disimpan hasilnya.

Jadi saat membaca hasil, siapkan diri untuk `nil`:

```elixir
collect(output!(ctx, :nilai)) |> Enum.reject(&is_nil/1)
```

## Contoh lintas bidang

| Bidang | Daftarnya | Tiap item diapakan |
|---|---|---|
| Guru | daftar siswa | dinilai |
| Toko online | daftar produk | dibuatkan deskripsi |
| Peneliti | daftar jurnal | diringkas |
| Ops | daftar server | dicek sehat atau tidak |
| Penerbit | daftar bab | diperiksa ejaannya |

## Latihan

Tambahkan satu siswa yang jawabannya kosong, dan pakai `skip!` supaya siswa itu tidak ikut
dihitung di rata-rata.

Berikutnya: [Bab 8 - Perulangan](../08_perulangan/README.md)
