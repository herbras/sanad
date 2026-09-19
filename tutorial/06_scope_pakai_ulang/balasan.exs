defmodule Balasan do
  use Sanad.DSL

  # Contoh bidang: customer service. Satu cara membalas, dipakai untuk beberapa tiket.

  # `execute :nama_scope` adalah blok yang tidak jalan sendiri.
  # Ia baru jalan kalau dipanggil `call_cog`.
  execute :satu_tiket do
    elixir_cog :kategori do
      teks = ctx.scope_value

      cond do
        String.contains?(teks, "refund") -> "pengembalian dana"
        String.contains?(teks, "lambat") -> "keluhan pengiriman"
        true -> "pertanyaan umum"
      end
    end

    elixir_cog :draf do
      "Halo, terima kasih sudah menghubungi kami soal #{output!(ctx, :kategori)}."
    end

    # `outputs` menentukan apa yang dikembalikan scope ini ke pemanggil.
    outputs do
      %{kategori: output!(ctx, :kategori), draf: output!(ctx, :draf)}
    end
  end

  execute do
    call_cog(:tiket_a, scope: :satu_tiket, do: "paket saya lambat sekali")
    call_cog(:tiket_b, scope: :satu_tiket, do: "saya mau refund")

    elixir_cog :ringkasan do
      a = output!(ctx, :tiket_a).value
      b = output!(ctx, :tiket_b).value

      "Tiket A: #{a.kategori}. Tiket B: #{b.kategori}."
    end
  end
end
