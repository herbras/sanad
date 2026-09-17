defmodule ControlFlow do
  @moduledoc """
  Port of Roast's `tutorial/05_control_flow/handling_failures.rb` (offline).

  Shows `fail!` gated by `abort_on_failure` and `fail_on_error: false` on a cmd
  step. Run with:

      mix roast.execute examples/control_flow.exs

  To see the abort path, remove `"milk"` from `:shopping_list` — the workflow
  then aborts with `RoastEx.CogFailedError`.
  """

  use RoastEx.DSL

  config do
    %{abort_on_failure: true}
  end

  execute do
    elixir_cog :shopping_list do
      ["milk", "eggs", "bread"]
    end

    elixir_cog :followup do
      items = output!(ctx, :shopping_list)

      unless "milk" in items do
        fail!("shopping list must include milk, got: #{inspect(items)}")
      end

      "recipe with milk for: " <> Enum.join(items, ", ")
    end

    cmd :grep, fail_on_error: false do
      "printf 'milk\\neggs\\n' | grep -i milk"
    end

    elixir_cog :report do
      "#{output!(ctx, :followup)} | grep: #{String.trim(cmd!(ctx, :grep).stdout)}"
    end
  end
end
