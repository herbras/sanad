# Tutorial Sanad

Sembilan bab, dari nol sampai bisa bikin workflow sungguhan. Bahasanya sengaja dibuat
sederhana. Kalau ada istilah baru, selalu dijelaskan dulu.

## Apa itu Sanad, dalam satu paragraf

Sanad menjalankan pekerjaan **berurutan**, satu per satu, dan menyimpan hasil tiap langkah.
Satu langkah disebut **cog**. Ada cog yang menjalankan perintah terminal (`cmd`), menghitung
sesuatu (`elixir_cog`), bertanya ke AI (`chat`), atau menyuruh agent AI bekerja (`agent`).
Hasil langkah pertama bisa dipakai langkah kedua. Itu saja idenya.

Bayangkan resep masakan: potong bawang, tumis, masukkan telur. Tiap langkah butuh hasil
langkah sebelumnya. Sanad adalah cara menulis resep seperti itu untuk komputer.

## Urutan belajar

| Bab | Isi | Butuh API key? |
|---|---|---|
| [01 - Workflow pertama](01_workflow_pertama/README.md) | Menjalankan satu langkah | Tidak |
| [02 - Merantai cog](02_merantai_cog/README.md) | Hasil langkah dipakai langkah berikutnya | Tidak |
| [03 - Params](03_params/README.md) | Memberi masukan dari luar | Tidak |
| [04 - Konfigurasi](04_konfigurasi/README.md) | Mengatur model dan opsi | Tidak |
| [05 - Kontrol alur](05_kontrol_alur/README.md) | Melewati, menggagalkan, menghentikan | Tidak |
| [06 - Scope pakai ulang](06_scope_pakai_ulang/README.md) | Menulis sekali, panggil berkali-kali | Tidak |
| [07 - Banyak item](07_banyak_item/README.md) | Mengerjakan daftar | Tidak |
| [08 - Perulangan](08_perulangan/README.md) | Mengulang sampai cukup | Tidak |
| [09 - Paralel](09_paralel/README.md) | Mengerjakan bersamaan | Tidak |

Semua contoh di tutorial ini bisa dijalankan **tanpa API key**, supaya kamu bisa belajar
dulu tanpa biaya. Di tiap bab ada catatan cara menggantinya dengan `chat` atau `agent`
sungguhan kalau sudah siap.

## Cara menjalankan

```bash
mix sanad.execute tutorial/01_workflow_pertama/salam.exs
```

Kalau mesinmu tidak punya Elixir, pakai wrapper container yang ada di repo ini:

```bash
./bin/mix sanad.execute tutorial/01_workflow_pertama/salam.exs
```

Selama workflow jalan, kamu akan melihat jejaknya di layar:

```
🔥🔥🔥 Workflow Starting
cmd(:tanggal) Starting
cmd(:tanggal) ❯ Saturday, 19 September 2026
cmd(:tanggal) Complete
🔥🔥🔥 Workflow Complete
```

Tambahkan `--quiet` kalau ingin sunyi, atau `--events jsonl` kalau ingin hasilnya dibaca
program lain.
