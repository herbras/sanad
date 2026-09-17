defmodule Sanad.CLI do
  @moduledoc """
  Escript entry point. Build with `mix escript.build` and drop the resulting
  `sanad` binary anywhere on your PATH to run workflows from any project:

      sanad path/to/workflow.exs --module MyWorkflow --param name=world

  Same as `mix sanad.execute`, but without needing the source tree or a Mix
  project around you.
  """

  def main(args) do
    load_env_file()
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [module: :string, param: :keep, help: :boolean])

    cond do
      opts[:help] ->
        print_usage()

      invalid != [] ->
        usage_error("unknown option(s): " <> option_names(invalid))

      rest == [] ->
        usage_error(nil)

      match?([_, _ | _], rest) ->
        usage_error("expected exactly one workflow file, got: #{inspect(rest)}")

      true ->
        execute(hd(rest), opts)
    end
  end

  # BYOK convenience: auto-load ~/.config/sanad/.env (KEY=VALUE lines)
  # unless SANAD_ENV_FILE points elsewhere. Existing env wins.
  defp load_env_file do
    path = System.get_env("SANAD_ENV_FILE") || Path.expand("~/.config/sanad/.env")

    with true <- File.exists?(path),
         {:ok, content} <- File.read(path) do
      for line <- String.split(content, "\n", trim: true),
          [k, v] <- String.split(line, "=", parts: 2),
          k != "" and System.get_env(k) == nil do
        System.put_env(k, String.trim(v) |> String.trim("\"") |> String.trim("'"))
      end
    end

    :ok
  end

  defp execute(path, opts) do
    unless File.exists?(path) do
      IO.puts(:stderr, "sanad: file not found: #{path}")
      System.halt(1)
    end

    started = System.monotonic_time(:millisecond)

    ctx =
      Sanad.run_file(path,
        module: opts[:module],
        params: Sanad.Summary.parse_params(Keyword.get_values(opts, :param))
      )

    IO.puts(Sanad.Summary.render(ctx, System.monotonic_time(:millisecond) - started))
    IO.puts(inspect(ctx.outputs, pretty: true, limit: :infinity))
  rescue
    e ->
      IO.puts(:stderr, "sanad: " <> Exception.message(e))
      System.halt(1)
  end

  defp usage_error(nil) do
    print_usage()
    System.halt(1)
  end

  defp usage_error(message) do
    IO.puts(:stderr, "sanad: " <> message)
    print_usage()
    System.halt(1)
  end

  defp option_names(invalid) do
    Enum.map_join(invalid, ", ", fn {name, _value} -> name end)
  end

  defp print_usage do
    IO.puts("""
    Run a Sanad workflow from anywhere.

    Usage:
      sanad path/to/workflow.exs [--module ModuleName] [--param key=value ...]

    Options:
      --module   module defined in the file (default: inferred from filename)
      --param    workflow param, repeatable (available via params(ctx))
      --help     show this help

    Env:
      OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY / PERPLEXITY_API_KEY
      (+ *_API_BASE), SANAD_DEFAULT_CHAT_PROVIDER, SANAD_DEFAULT_AGENT_PROVIDER
    """)
  end
end
