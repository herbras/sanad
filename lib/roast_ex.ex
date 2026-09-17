defmodule Sanad do
  @moduledoc """
  Elixir rewrite of Shopify Roast: structured AI workflows as composable cogs.

  Workflow files use a macro DSL that compiles to a list of steps, then the
  runtime executes them and stores named outputs.
  """

  defdelegate run(module_or_file, opts \\ []), to: Sanad.Runner

  @doc """
  Loads a workflow file and runs its module.

  Options:

  * `:module` — module defined in the file (default: inferred from the file
    name, e.g. `my_workflow.exs` → `MyWorkflow`)
  * `:params` — workflow params map (see `Sanad.Helpers.params/1`)
  * `:workflow_dir` — defaults to the file's directory
  """
  @spec run_file(Path.t(), keyword()) :: Sanad.Context.t()
  def run_file(path, opts \\ []) do
    Code.require_file(path)
    module = opts[:module] || guess_module(path)

    opts =
      opts
      |> Keyword.delete(:module)
      |> Keyword.put_new(:workflow_dir, Path.dirname(path))

    Sanad.Runner.run(Module.concat([module]), opts)
  end

  @doc """
  Infers a module name from a workflow file path.
  """
  @spec guess_module(Path.t()) :: String.t()
  def guess_module(path) do
    path
    |> Path.basename(".exs")
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> Macro.camelize()
  end
end
