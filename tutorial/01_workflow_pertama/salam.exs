defmodule Salam do
  use Sanad.DSL

  # `execute do ... end` artinya: "jalankan langkah-langkah ini, berurutan".
  execute do
    # Cog `cmd` menjalankan perintah terminal, sama seperti kamu mengetiknya sendiri.
    cmd(:tanggal, "date '+%A, %d %B %Y'")

    # Cog `elixir_cog` tidak memanggil apa pun di luar. Ia cuma menghitung nilai.
    # `cmd!(ctx, :tanggal)` membaca hasil langkah di atas.
    elixir_cog :ucapan do
      hari_ini = String.trim(cmd!(ctx, :tanggal).stdout)
      "Selamat bekerja. Hari ini #{hari_ini}."
    end
  end
end
