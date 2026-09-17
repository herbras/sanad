defmodule RoastEx.CLI do
  @moduledoc """
  Escript entry point. Build with `mix escript.build` and drop the resulting
  `roast` binary anywhere on your PATH to run workflows from any project:

      roast path/to/workflow.exs --module MyWorkflow

  Same as `mix roast.execute`, but without needing the source tree or a Mix
  project around you.
  """

  def main(args) do
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, rest, _} =
      OptionParser.parse(args, strict: [module: :string, help: :boolean])

    cond do
      opts[:help] -> print_usage()
      rest == [] -> usage_error()
      true -> execute(hd(rest), opts)
    end
  end

  defp execute(path, opts) do
    unless File.exists?(path) do
      IO.puts(:stderr, "roast: file not found: #{path}")
      System.halt(1)
    end

    Code.require_file(path)
    module = Module.concat([opts[:module] || guess_module(path)])
    ctx = RoastEx.run(module, workflow_dir: Path.dirname(path))
    IO.puts(inspect(ctx.outputs, pretty: true, limit: :infinity))
  rescue
    e ->
      IO.puts(:stderr, "roast: " <> Exception.message(e))
      System.halt(1)
  end

  defp guess_module(path) do
    path
    |> Path.basename(".exs")
    |> Macro.camelize()
  end

  defp usage_error do
    print_usage()
    System.halt(1)
  end

  defp print_usage do
    IO.puts("""
    roast — run a RoastEx workflow from anywhere.

    Usage:
      roast path/to/workflow.exs [--module ModuleName]

    Options:
      --module   module defined in the file (default: inferred from filename)
      --help     show this help

    Env:
      OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY (+ *_API_BASE)
      ROAST_DEFAULT_CHAT_PROVIDER, ROAST_DEFAULT_AGENT_PROVIDER
    """)
  end
end
