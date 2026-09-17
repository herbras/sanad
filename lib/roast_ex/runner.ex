defmodule RoastEx.Runner do
  @moduledoc "Sequential (and map-parallel) execution of compiled workflow steps."

  alias RoastEx.Context
  alias RoastEx.Cogs
  alias RoastEx.Output

  def run(module, opts) when is_atom(module) do
    config = module.__roast_config__()
    steps = module.__roast_steps__()

    ctx = %Context{
      config: config,
      params: Keyword.get(opts, :params, %{}),
      workflow_dir: Keyword.get(opts, :workflow_dir, File.cwd!())
    }

    Enum.reduce(steps, ctx, &run_step/2)
  end

  def run(path, opts) when is_binary(path) do
    Code.require_file(path)
    # Expect the file to define a module ending after load; pass :module opt.
    module = Keyword.fetch!(opts, :module)
    run(module, Keyword.put(opts, :workflow_dir, Path.dirname(path)))
  end

  defp run_step(%{type: type, name: name, opts: opts, fun: fun}, ctx) do
    input = fun.(ctx)

    output =
      case type do
        :cmd -> Cogs.Cmd.run(input, opts)
        :chat -> Cogs.Chat.run(input, opts, ctx.config)
        :agent -> Cogs.Agent.run(input, opts, ctx.config)
        :elixir -> Cogs.ElixirCog.run(input, opts)
        :map -> run_map(input, opts, ctx)
      end

    Context.put(ctx, name, output)
  end

  defp run_map(%{collection: collection, mapper: mapper}, opts, ctx) do
    parallel? = Keyword.get(opts, :parallel, true)

    items =
      if parallel? do
        collection
        |> Task.async_stream(fn item -> mapper.(ctx, item) end, timeout: :infinity)
        |> Enum.map(fn {:ok, v} -> v end)
      else
        Enum.map(collection, &mapper.(ctx, &1))
      end

    %Output.MapResult{items: items}
  end

  defp run_map(other, opts, ctx) when is_list(other) do
    run_map(%{collection: other, mapper: fn _ctx, x -> x end}, opts, ctx)
  end
end
