defmodule Mix.Tasks.Sanad.Execute do
  use Mix.Task

  @shortdoc "Execute a Sanad workflow module"

  @moduledoc """
  Runs a Sanad workflow file:

      mix sanad.execute path/to/workflow.exs [--module ModuleName] [--param key=value ...]

  Params are available inside workflows via `Sanad.Helpers.params/1`.

  Run events are rendered to stderr as the workflow runs. `--events jsonl`
  writes them as JSON Lines instead, and `--quiet` turns them off entirely,
  leaving only the summary and the outputs dump.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [module: :string, param: :keep, quiet: :boolean, events: :string]
      )

    if invalid != [] do
      Mix.raise("unknown option(s): " <> Enum.map_join(invalid, ", ", fn {name, _} -> name end))
    end

    case rest do
      [path] ->
        unless opts[:quiet] do
          case opts[:events] || System.get_env("SANAD_EVENT_FORMAT") || "pretty" do
            "jsonl" -> Sanad.Events.Jsonl.attach()
            "pretty" -> Sanad.Events.Renderer.attach()
            other -> Mix.raise("unknown --events format: #{other} (expected pretty | jsonl)")
          end
        end

        started = System.monotonic_time(:millisecond)

        ctx =
          Sanad.run_file(path,
            module: opts[:module],
            params: Sanad.Summary.parse_params(Keyword.get_values(opts, :param))
          )

        Mix.shell().info(Sanad.Summary.render(ctx, System.monotonic_time(:millisecond) - started))

        Mix.shell().info(inspect(ctx.outputs, pretty: true, limit: :infinity))

      _ ->
        Mix.raise(
          "usage: mix sanad.execute path/to/workflow.exs [--module ModuleName] [--param key=value ...]"
        )
    end
  end
end
