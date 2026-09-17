defmodule RoastEx do
  @moduledoc """
  Elixir rewrite of Shopify Roast: structured AI workflows as composable cogs.

  Workflow files use a macro DSL that compiles to a list of steps, then the
  runtime executes them and stores named outputs.
  """

  defdelegate run(module_or_file, opts \\ []), to: RoastEx.Runner
end
