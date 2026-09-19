defmodule CekLayanan do
  use Sanad.DSL

  # Contoh bidang: operasional. Mengecek banyak hal sekaligus, bukan satu per satu.
  execute :satu_cek do
    cmd :jalankan, fail_on_error: false do
      ctx.scope_value.perintah
    end

    elixir_cog :hasil do
      %{
        nama: ctx.scope_value.nama,
        sehat: cmd!(ctx, :jalankan).status == 0
      }
    end

    outputs do
      output!(ctx, :hasil)
    end
  end

  execute do
    elixir_cog :daftar do
      [
        %{nama: "disk", perintah: "df -h > /dev/null"},
        %{nama: "waktu", perintah: "date > /dev/null"},
        %{nama: "sengaja gagal", perintah: "exit 3"}
      ]
    end

    # `parallel: 3` artinya tiga pengecekan berjalan bersamaan.
    map_cog :cek, scope: :satu_cek, parallel: 3 do
      output!(ctx, :daftar)
    end

    elixir_cog :ringkasan do
      hasil = collect(output!(ctx, :cek)) |> Enum.reject(&is_nil/1)
      bermasalah = Enum.reject(hasil, & &1.sehat)

      case bermasalah do
        [] -> "Semua #{length(hasil)} layanan sehat."
        list -> "Bermasalah: #{Enum.map_join(list, ", ", & &1.nama)}"
      end
    end
  end
end
