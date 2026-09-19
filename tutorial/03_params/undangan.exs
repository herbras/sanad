defmodule Undangan do
  use Sanad.DSL

  # Contoh bidang: administrasi. Workflow yang sama dipakai untuk banyak orang,
  # cukup ganti params saat dijalankan.
  execute do
    elixir_cog :data do
      p = params(ctx)

      %{
        nama: Map.get(p, "nama", "Bapak/Ibu"),
        acara: Map.get(p, "acara", "rapat"),
        jam: Map.get(p, "jam", "09.00")
      }
    end

    elixir_cog :surat do
      d = output!(ctx, :data)

      """
      Yth. #{d.nama},

      Dengan hormat kami mengundang Anda pada #{d.acara} pukul #{d.jam} WIB.
      Mohon kehadirannya tepat waktu.

      Terima kasih.
      """
    end
  end
end
