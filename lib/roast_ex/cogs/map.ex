defmodule RoastEx.Cogs.Map do
  @moduledoc """
  Maps a function over a collection.

  The step block must return `%{collection: enumerable, mapper: fun/2}` where
  the mapper receives `(ctx, item)`.

  Options:

  * `:parallel` — `false` (default, serial), `true` (default concurrency),
    or a positive integer limit.
  * `:timeout` — per-item timeout in ms; defaults to `:infinity` (no cap),
    matching upstream Roast.

  This is a transitional implementation: nested cogs inside `map` (Roast
  semantics) arrive with the nested execution engine.
  """

  alias RoastEx.Output.MapResult

  def run(%{collection: collection, mapper: mapper}, opts, ctx) when is_function(mapper, 2) do
    collection = Enum.to_list(collection)
    parallel = Keyword.get(opts, :parallel, false)
    timeout = Keyword.get(opts, :timeout, :infinity)

    items =
      case parallel do
        false ->
          Enum.map(collection, &mapper.(ctx, &1))

        true ->
          parallel_map(collection, mapper, ctx, System.schedulers_online(), timeout)

        limit when is_integer(limit) and limit > 0 ->
          parallel_map(collection, mapper, ctx, limit, timeout)

        other ->
          raise ArgumentError,
                "map :parallel must be false, true, or a positive integer, got: #{inspect(other)}"
      end

    %MapResult{items: items}
  end

  def run(%{collection: collection, mapper: mapper}, _opts, _ctx) do
    raise ArgumentError,
          "map expects a mapper with arity 2, got #{inspect(mapper)} for collection #{inspect(collection)}"
  end

  def run(list, _opts, _ctx) when is_list(list), do: %MapResult{items: list}

  def run(other, _opts, _ctx) do
    raise ArgumentError,
          "map expects %{collection: ..., mapper: ...}, got: #{inspect(other)}"
  end

  defp parallel_map(collection, mapper, ctx, max_concurrency, timeout) do
    Task.Supervisor.async_stream_nolink(
      RoastEx.TaskSupervisor,
      collection,
      fn item -> mapper.(ctx, item) end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      zip_input_on_exit: true
    )
    |> Enum.map(fn
      {:ok, value} -> value
      {:exit, {item, reason}} -> raise "map failed for #{inspect(item)}: #{inspect(reason)}"
      {:exit, reason} -> raise "map failed: #{inspect(reason)}"
    end)
  end
end
