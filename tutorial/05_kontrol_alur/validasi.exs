defmodule Validasi do
  use Sanad.DSL

  # Contoh bidang: keuangan. Data kosong dilewati, data rusak menghentikan pekerjaan.
  config do
    %{abort_on_failure: true}
  end

  execute do
    cmd(:baris, "printf 'jan,100\\nfeb,\\nmar,250\\n'")

    elixir_cog :bersih do
      cmd!(ctx, :baris).stdout
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, ","))
    end

    elixir_cog :kosong do
      kosong = Enum.filter(output!(ctx, :bersih), fn [_bulan, nilai] -> nilai == "" end)

      # `skip!` artinya: langkah ini tidak menghasilkan apa-apa, tapi workflow lanjut.
      if kosong == [], do: skip!()

      Enum.map_join(kosong, ", ", fn [bulan, _] -> bulan end)
    end

    elixir_cog :total do
      output!(ctx, :bersih)
      |> Enum.reject(fn [_bulan, nilai] -> nilai == "" end)
      |> Enum.map(fn [_bulan, nilai] -> String.to_integer(nilai) end)
      |> Enum.sum()
    end

    elixir_cog :laporan do
      bulan_kosong = if status(ctx, :kosong) == :skipped, do: "tidak ada", else: output!(ctx, :kosong)

      "Total #{output!(ctx, :total)}. Bulan tanpa data: #{bulan_kosong}."
    end
  end
end
