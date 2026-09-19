# Bab 4 - Konfigurasi

## Yang akan kamu mengerti

Cara mengatur model, provider, dan opsi lain — untuk semua langkah sekaligus, atau untuk satu
langkah tertentu saja.

## Konsep

Config ditulis di blok `config do ... end`, sebelum `execute`.

```elixir
config do
  global(abort_on_failure: true)
  chat(provider: :claude, model: :haiku)
  chat(:naskah, model: :opus)
  chat(~r/^cek_/, temperature: 0.0)
end
```

Empat baris itu punya jangkauan berbeda, dari paling luas ke paling sempit:

| Baris | Kena siapa |
|---|---|
| `global(...)` | semua cog, jenis apa pun |
| `chat(...)` | semua cog `chat` |
| `chat(~r/^cek_/, ...)` | cog `chat` yang namanya diawali `cek_` |
| `chat(:naskah, ...)` | cog `chat` bernama `:naskah` saja |

## Siapa menang kalau bertabrakan

Yang **lebih khusus** menang. Urutannya dari kalah ke menang:

```
global  →  semua chat  →  pola yang cocok  →  nama persis  →  opsi di langkah itu sendiri
```

Jadi kalau `chat(model: :haiku)` dan `chat(:naskah, model: :opus)` sama-sama ada, langkah
bernama `:naskah` memakai `:opus`, sisanya `:haiku`.

Dan apa pun isinya config, opsi yang ditulis langsung di langkah selalu menang:

```elixir
chat :naskah, model: :sonnet do
  "..."
end
```

Kalau dua pola sama-sama cocok, yang **ditulis belakangan** menang.

## Bentuk lama juga masih jalan

Kalau kamu sudah pernah menulis config sebagai map, itu tetap berlaku dan artinya sama:

```elixir
config do
  %{chat: %{provider: :openai, model: "gpt-4o-mini"}, abort_on_failure: true}
end
```

Yang tidak boleh: mencampur dua bentuk itu di satu blok. Sanad akan menolak dan memberi tahu
baris mana yang bikin bingung.

## Nama model yang pendek

Untuk model Claude, ada alias supaya tidak perlu menulis ID panjang:

| Alias | Artinya |
|---|---|
| `:opus` | `claude-opus-5` — paling pintar, paling mahal |
| `:sonnet` | `claude-sonnet-5` — seimbang |
| `:haiku` | `claude-haiku-4-5` — paling murah dan cepat |

`provider: :claude` sama artinya dengan `provider: :anthropic`.

## Pola yang masuk akal di dunia nyata

| Bidang | Model murah untuk | Model pintar untuk |
|---|---|---|
| Redaksi | merapikan tata bahasa | menulis naskah utama |
| Customer service | menggolongkan tiket | membalas keluhan rumit |
| Riset | menyaring judul | menyimpulkan temuan |
| Developer | membaca log | menilai desain kode |

Kalau semua langkah pakai model termahal, biayanya sia-sia. Config berskop adalah cara
membagi anggaran itu.

## Latihan

Tambahkan `chat(~r/_draf$/, temperature: 0.9)` dan jelaskan langkah mana saja yang kena.

Berikutnya: [Bab 5 - Kontrol alur](../05_kontrol_alur/)
