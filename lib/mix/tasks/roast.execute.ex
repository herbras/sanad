defmodule Mix.Tasks.Roast.Execute do
  use Mix.Task

  @shortdoc "Execute a RoastEx workflow module"

  @moduledoc """
  Runs a RoastEx workflow file:

      mix roast.execute path/to/workflow.exs [--module ModuleName] [--param key=value ...]

  Params are available inside workflows via `RoastEx.Helpers.params/1`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} = OptionParser.parse(args, strict: [module: :string, param: :keep])

    if invalid != [] do
      Mix.raise("unknown option(s): " <> Enum.map_join(invalid, ", ", fn {name, _} -> name end))
    end

    case rest do
      [path] ->
        started = System.monotonic_time(:millisecond)

        ctx =
          RoastEx.run_file(path,
            module: opts[:module],
            params: RoastEx.Summary.parse_params(Keyword.get_values(opts, :param))
          )

        Mix.shell().info(
          RoastEx.Summary.render(ctx, System.monotonic_time(:millisecond) - started)
        )

        Mix.shell().info(inspect(ctx.outputs, pretty: true, limit: :infinity))

      _ ->
        Mix.raise(
          "usage: mix roast.execute path/to/workflow.exs [--module ModuleName] [--param key=value ...]"
        )
    end
  end
end
