defmodule LocalPipeline do
  @moduledoc """
  End-to-end demo workflow that needs no network or API keys.

  Run with:

      mix roast.execute examples/local_pipeline.exs --module LocalPipeline
  """

  use RoastEx.DSL

  config do
    %{abort_on_failure: true}
  end

  execute do
    cmd(:echo, "printf 'hello'")

    elixir_cog :greeting do
      String.trim(cmd!(ctx, :echo).stdout) <> " world"
    end

    call_cog :loud, scope: :upcase do
      output!(ctx, :greeting)
    end

    map_cog :lengths, scope: :string_length, parallel: 2 do
      ["a", "bb", "ccc"]
    end

    repeat_cog :counter, scope: :count, max_iterations: 5 do
      0
    end
  end

  execute :upcase do
    elixir_cog(:value, do: String.upcase(ctx.scope_value))
  end

  execute :string_length do
    elixir_cog(:length, do: String.length(ctx.scope_value))
  end

  execute :count do
    elixir_cog :step do
      value = ctx.scope_value
      if value >= 3, do: break!()
      value + 1
    end
  end
end
