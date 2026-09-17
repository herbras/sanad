defmodule RoastEx.Cogs.ElixirCog do
  alias RoastEx.Output.Elixir

  def run(value, _opts \\ []) do
    %Elixir{value: value}
  end
end
