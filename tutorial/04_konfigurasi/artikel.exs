defmodule Artikel do
  use Sanad.DSL

  # Contoh bidang: redaksi media. Riset pakai model murah, tulis pakai model pintar.
  config do
    # `global` berlaku untuk semua cog, jenis apa pun.
    global(abort_on_failure: true)

    # Berlaku untuk semua cog `chat` di workflow ini.
    chat(provider: :claude, model: :haiku)

    # Berlaku hanya untuk cog `chat` bernama `:naskah`.
    chat(:naskah, model: :opus)

    # Berlaku untuk semua cog `chat` yang namanya diawali "cek_".
    chat(~r/^cek_/, temperature: 0.0)
  end

  execute do
    # Contoh ini tidak memanggil AI supaya bisa dijalankan tanpa API key.
    # Yang penting di bab ini: lihat bagaimana config tersusun di atas.
    elixir_cog :catatan do
      "Buka README bab ini untuk melihat urutan menang antar lapisan config."
    end
  end
end
