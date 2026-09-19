# Bab 8 - Perulangan

## Yang akan kamu mengerti

Cara mengulang langkah sampai sesuatu tercapai — bukan sebanyak jumlah item, tapi sebanyak
yang dibutuhkan.

## Beda `map_cog` dan `repeat_cog`

| | `map_cog` | `repeat_cog` |
|---|---|---|
| Berapa kali jalan | sebanyak item di daftar | sampai `break!` atau batas |
| Tahu di awal? | ya, daftarnya sudah ada | tidak |
| Hasil sebelumnya | tidak dipakai | dipakai iterasi berikutnya |

Singkatnya: `map_cog` untuk "kerjakan semua ini", `repeat_cog` untuk "terus, sampai cukup".

## Konsep

```elixir
repeat_cog(:bulanan, scope: :satu_bulan, max_iterations: 24, do: 1_000_000)
```

- `do: 1_000_000` — nilai awal, masuk ke `ctx.scope_value` di iterasi pertama.
- Hasil tiap iterasi jadi `ctx.scope_value` iterasi berikutnya.
- `max_iterations: 24` — pagar pengaman. Tanpa itu, bawaannya 1000.

Pagar itu penting. Kalau syarat berhentinya salah tulis, workflow tidak akan berputar
selamanya — ia berhenti di batas dan kamu tahu ada yang keliru.

## Cara berhenti

Panggil `break!()` begitu targetnya tercapai:

```elixir
outputs do
  saldo = output!(ctx, :saldo)
  if saldo >= 5_000_000, do: break!()
  saldo
end
```

Iterasi yang memanggil `break!` tetap tercatat, tapi nilainya `nil`. Jadi saat membaca
riwayat, buang dulu yang kosong:

```elixir
collect(output!(ctx, :bulanan)) |> Enum.reject(&is_nil/1)
```

## Jalankan

```bash
mix sanad.execute tutorial/08_perulangan/tabungan.exs
```

## Contoh lintas bidang

| Bidang | Diulang sampai |
|---|---|
| Keuangan | saldo mencapai target |
| Penulis | draf lolos pemeriksaan |
| Developer | tes lulus semua |
| Riset | data cukup untuk disimpulkan |
| Sales | daftar prospek habis disapa |

Pola yang paling sering dengan AI: "perbaiki, periksa, ulangi kalau belum lolos". Langkah
perbaikan pakai `chat`, langkah pemeriksaan pakai `cmd` atau `elixir_cog` supaya keputusannya
pasti, bukan kira-kira.

## Latihan

Ubah setoran bulanan jadi params, lalu bandingkan berapa bulan yang dibutuhkan untuk setoran
300 ribu dan 700 ribu.

Berikutnya: [Bab 9 - Paralel](../09_paralel/README.md)
