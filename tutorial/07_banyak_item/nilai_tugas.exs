defmodule NilaiTugas do
  use Sanad.DSL

  # Contoh bidang: guru. Satu cara menilai, dijalankan untuk semua siswa sekaligus.
  execute :satu_siswa do
    elixir_cog :hasil do
      %{nama: nama, jawaban: jawaban} = ctx.scope_value
      benar = Enum.count(jawaban, &(&1 == :benar))

      %{nama: nama, benar: benar, nilai: round(benar / length(jawaban) * 100)}
    end
  end

  execute do
    elixir_cog :daftar do
      [
        %{nama: "Ani", jawaban: [:benar, :benar, :salah, :benar]},
        %{nama: "Budi", jawaban: [:salah, :benar, :salah, :salah]},
        %{nama: "Cici", jawaban: [:benar, :benar, :benar, :benar]}
      ]
    end

    # `map_cog` menjalankan scope sekali untuk tiap item.
    map_cog :nilai, scope: :satu_siswa, parallel: 3 do
      output!(ctx, :daftar)
    end

    elixir_cog :rapor do
      collect(output!(ctx, :nilai))
      |> Enum.map_join("\n", fn h -> "#{h.nama}: #{h.nilai}" end)
    end

    elixir_cog :rata_rata do
      hasil = collect(output!(ctx, :nilai))
      total = hasil |> Enum.map(& &1.nilai) |> Enum.sum()

      round(total / length(hasil))
    end
  end
end
