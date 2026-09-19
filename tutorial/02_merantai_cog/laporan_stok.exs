defmodule LaporanStok do
  use Sanad.DSL

  # Contoh bidang: admin gudang. Tiga langkah, tiap langkah memakai hasil sebelumnya.
  execute do
    # 1. Ambil data mentah. Di dunia nyata ini bisa `cat data.csv` atau panggil API.
    cmd(:data, "printf 'beras,4\\nminyak,0\\ngula,12\\n'")

    # 2. Ubah teks jadi daftar yang rapi.
    elixir_cog :baris do
      cmd!(ctx, :data).stdout
      |> String.split("\n", trim: true)
      |> Enum.map(fn baris ->
        [nama, jumlah] = String.split(baris, ",")
        %{nama: nama, jumlah: String.to_integer(jumlah)}
      end)
    end

    # 3. Ambil kesimpulan dari daftar itu.
    elixir_cog :perlu_restok do
      output!(ctx, :baris)
      |> Enum.filter(&(&1.jumlah < 5))
      |> Enum.map_join(", ", & &1.nama)
    end
  end
end
