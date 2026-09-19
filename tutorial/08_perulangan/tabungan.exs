defmodule Tabungan do
  use Sanad.DSL

  # Contoh bidang: perencanaan keuangan. Ulangi sampai target tercapai.
  execute :satu_bulan do
    elixir_cog :saldo do
      # Hasil iterasi sebelumnya masuk lewat `ctx.scope_value`.
      sebelumnya = ctx.scope_value
      bunga = round(sebelumnya * 0.01)

      sebelumnya + 500_000 + bunga
    end

    outputs do
      saldo = output!(ctx, :saldo)

      # Sudah cukup? Hentikan perulangan.
      if saldo >= 5_000_000, do: break!()

      saldo
    end
  end

  execute do
    # Nilai di blok `do` adalah isi awal iterasi pertama.
    repeat_cog(:bulanan, scope: :satu_bulan, max_iterations: 24, do: 1_000_000)

    elixir_cog :kesimpulan do
      riwayat = collect(output!(ctx, :bulanan)) |> Enum.reject(&is_nil/1)

      "Butuh #{length(riwayat)} bulan. Saldo per bulan: #{inspect(riwayat)}"
    end
  end
end
