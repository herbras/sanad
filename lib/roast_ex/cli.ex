defmodule RoastEx.CLI do
  @moduledoc """
  Escript entry point. Build with `mix escript.build` and drop the resulting
  `roast` binary anywhere on your PATH to run workflows from any project:

      roast path/to/workflow.exs --module MyWorkflow --param name=world

  Same as `mix roast.execute`, but without needing the source tree or a Mix
  project around you.
  """

  def main(args) do
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [module: :string, param: :keep, help: :boolean])

    cond do
      opts[:help] -> print_usage()
      invalid != [] -> usage_error("unknown option(s): " <> option_names(invalid))
      rest == [] -> usage_error(nil)
      true -> execute(hd(rest), opts)
    end
  end

  defp execute(path, opts) do
    unless File.exists?(path) do
      IO.puts(:stderr, "roast: file not found: #{path}")
      System.halt(1)
    end

    started = System.monotonic_time(:millisecond)

    ctx =
      RoastEx.run_file(path,
        module: opts[:module],
        params: RoastEx.Summary.parse_params(Keyword.get_values(opts, :param))
      )

    IO.puts(RoastEx.Summary.render(ctx, System.monotonic_time(:millisecond) - started))
    IO.puts(inspect(ctx.outputs, pretty: true, limit: :infinity))
  rescue
    e ->
      IO.puts(:stderr, "roast: " <> Exception.message(e))
      System.halt(1)
  end

  defp usage_error(nil) do
    print_usage()
    System.halt(1)
  end

  defp usage_error(message) do
    IO.puts(:stderr, "roast: " <> message)
    print_usage()
    System.halt(1)
  end

  defp option_names(invalid) do
    Enum.map_join(invalid, ", ", fn {name, _value} -> name end)
  end

  defp print_usage do
    IO.puts("""
    roast — run a RoastEx workflow from anywhere.

    Usage:
      roast path/to/workflow.exs [--module ModuleName] [--param key=value ...]

    Options:
      --module   module defined in the file (default: inferred from filename)
      --param    workflow param, repeatable (available via params(ctx))
      --help     show this help

    Env:
      OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY / PERPLEXITY_API_KEY
      (+ *_API_BASE), ROAST_DEFAULT_CHAT_PROVIDER, ROAST_DEFAULT_AGENT_PROVIDER
    """)
  end
end
