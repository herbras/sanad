defmodule ReusableScopes do
  @moduledoc """
  Port of Roast's `tutorial/06_reusable_scopes/basic_scope.rb` (offline).

  Shows named scopes, `call_cog`, and reading inner outputs with `from/2`.
  Run with:

      mix roast.execute examples/reusable_scopes.exs
  """

  use RoastEx.DSL

  execute do
    call_cog :separator, scope: :print_separator do
      :ignored
    end

    call_cog :word1, scope: :random_word do
      "first"
    end

    call_cog :word2, scope: :random_word do
      "second"
    end

    elixir_cog :report do
      line = from(output!(ctx, :separator), fn child -> output!(child, :line) end)

      words =
        [output!(ctx, :word1), output!(ctx, :word2)]
        |> Enum.map(fn call -> from(call, fn child -> output!(child, :upper) end) end)

      Enum.join([line, Enum.join(words, ", "), line], "\n")
    end
  end

  execute :print_separator do
    elixir_cog(:line, do: String.duplicate("=", 20))
  end

  execute :random_word do
    elixir_cog(:upper, do: ctx.scope_value |> to_string() |> String.upcase())
  end
end
