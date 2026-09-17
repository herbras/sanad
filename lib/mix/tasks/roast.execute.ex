defmodule Mix.Tasks.Roast.Execute do
  use Mix.Task

  @shortdoc "Execute a RoastEx workflow module"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, _} =
      OptionParser.parse(args, strict: [module: :string])

    case rest do
      [path] ->
        Code.require_file(path)
        module = Module.concat([opts[:module] || guess_module(path)])
        ctx = RoastEx.run(module, workflow_dir: Path.dirname(path))
        Mix.shell().info(inspect(ctx.outputs, pretty: true, limit: :infinity))

      _ ->
        Mix.raise("usage: mix roast.execute path/to/workflow.exs --module ModuleName")
    end
  end

  defp guess_module(path) do
    path
    |> Path.basename(".exs")
    |> Macro.camelize()
  end
end
