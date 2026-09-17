defmodule Sanad.Cogs.ElixirCog do
  @moduledoc """
  Returns the value produced by the step's input block.

  This is Sanad's counterpart of Roast's `ruby` cog; the DSL exposes it as
  both `elixir_cog` and `ruby`.
  """

  def run(value, _opts, _ctx), do: value
end
