# Bab 5 - Kontrol alur

## Yang akan kamu mengerti

Cara melewati langkah, menggagalkan pekerjaan, atau berhenti di tengah jalan — dengan sengaja.

## Empat perintah

| Perintah | Artinya | Workflow lanjut? |
|---|---|---|
| `skip!()` | "langkah ini tidak perlu" | Ya |
| `fail!("alasan")` | "ada yang salah" | Tergantung `abort_on_failure` |
| `next!()` | "cukup sampai di sini untuk bagian ini" | Ya, bagian berikutnya |
| `break!()` | "hentikan pengulangan" | Ya, keluar dari loop |

## `skip!` — lewati saja

Dipakai kalau langkah itu memang tidak ada gunanya sekarang.

```elixir
elixir_cog :kosong do
  if tidak_ada_masalah, do: skip!()
  "..."
end
```

Langkah yang di-`skip!` **tidak punya hasil**. Jadi jangan langsung dibaca. Cek dulu:

```elixir
if status(ctx, :kosong) == :skipped, do: "tidak ada", else: output!(ctx, :kosong)
```

## `fail!` — nyatakan gagal

```elixir
elixir_cog :periksa do
  if saldo < 0, do: fail!("saldo tidak boleh minus")
  :ok
end
```

Apa yang terjadi sesudahnya diatur `abort_on_failure`:

- `true` (bawaan): workflow berhenti. Cocok untuk data yang harus benar, misalnya keuangan.
- `false`: langkah ditandai gagal, sisanya tetap jalan. Cocok untuk memeriksa banyak berkas,
  di mana satu berkas rusak tidak boleh membatalkan semuanya.

Atur per langkah kalau perlu:

```elixir
elixir_cog :periksa, abort_on_failure: false do
  fail!("boleh gagal, tidak apa-apa")
end
```

## `break!` — hentikan pengulangan

Ini baru terasa gunanya di Bab 7 dan 8, saat kita mengerjakan banyak item. Intinya: begitu
ketemu yang dicari, tidak perlu meneruskan sisanya.

## Jalankan

```bash
mix sanad.execute tutorial/05_kontrol_alur/validasi.exs
```

Lihat ringkasannya: satu langkah berstatus `ok`, dan kalau tidak ada data kosong, langkah
`:kosong` akan berstatus `skipped`.

## Contoh lintas bidang

| Bidang | Kapan `skip!` | Kapan `fail!` |
|---|---|---|
| Keuangan | tidak ada transaksi hari ini | angka tidak balance |
| Guru | siswa belum mengumpulkan | format jawaban rusak |
| Ops | server memang dimatikan | sertifikat kedaluwarsa |
| Developer | tidak ada berkas berubah | tes gagal |

Perbedaan intinya: `skip!` artinya "wajar", `fail!` artinya "tidak wajar".

## Latihan

Ubah contohnya agar `fail!` dipanggil kalau ada nilai negatif, lalu jalankan dua kali:
sekali dengan `abort_on_failure: true`, sekali `false`. Perhatikan bedanya di ringkasan.

Berikutnya: [Bab 6 - Scope pakai ulang](../06_scope_pakai_ulang/)
