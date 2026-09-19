# Bab 3 - Params

## Yang akan kamu mengerti

Cara memberi masukan ke workflow dari luar, supaya satu workflow bisa dipakai berkali-kali
dengan isi berbeda.

## Konsep

**Params** adalah kotak isian. Kamu isi saat menjalankan, bukan saat menulis.

Di dalam workflow, bacanya dengan `params(ctx)`. Hasilnya berupa map dengan kunci teks:

```elixir
nama = Map.get(params(ctx), "nama", "Bapak/Ibu")
```

Bagian `"Bapak/Ibu"` adalah nilai cadangan: dipakai kalau params tidak diisi. Selalu siapkan
nilai cadangan, supaya workflow tidak rusak kalau ada yang lupa mengisi.

## Jalankan

```bash
mix sanad.execute tutorial/03_params/undangan.exs \
  --param nama="Ibu Sinta" --param acara="rapat anggaran" --param jam="13.30"
```

Tanpa params pun tetap jalan, isinya memakai nilai cadangan:

```bash
mix sanad.execute tutorial/03_params/undangan.exs
```

`--param` boleh diulang sebanyak yang kamu mau. Bentuknya selalu `kunci=nilai`.

## Kapan params berguna

| Bidang | Satu workflow | Params-nya |
|---|---|---|
| HR | surat undangan | nama, acara, jam |
| Guru | soal latihan | mata pelajaran, tingkat kesulitan |
| Marketing | caption promo | produk, target audiens |
| Developer | review kode | nama berkas, cabang git |
| Peneliti | ringkasan jurnal | topik, tahun |

Ini bedanya workflow dengan catatan biasa: sekali tulis, dipakai terus dengan isi berganti.

## Hati-hati satu hal

Kunci params selalu **teks**, bukan simbol. Jadi `Map.get(p, "nama")`, bukan
`Map.get(p, :nama)`. Ini sering bikin bingung di awal.

## Latihan

Tambahkan params `tempat`, dan pastikan tetap jalan meski `tempat` tidak diisi.

Berikutnya: [Bab 4 - Konfigurasi](../04_konfigurasi/)
