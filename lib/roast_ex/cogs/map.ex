defmodule RoastEx.Cogs.Map do
  @moduledoc """
  Runs a named `execute :scope` block once per item of a collection.

      execute do
        map_cog :reviewed, scope: :review_one, parallel: 2 do
          cmd!(ctx, :files).stdout |> String.split("\\n", trim: true)
        end
      end

      execute :review_one do
        chat(:summary) do
          "Review: \#{ctx.scope_value}"
        end
      end

  Each iteration runs in an isolated child context whose `scope_value` is the
  item and whose `scope_index` is its position. The output is a
  `%RoastEx.Output.MapResult{}`:

  * `items` — each iteration's final output, in input order; `nil` for
    iterations that never ran (after `break!` or a halt).
  * `contexts` — matching child contexts (see `from/2`, `collect/2`).

  Options:

  * `:scope` — required.
  * `:parallel` — `false` (default, serial), `true` (scheduler count), or a
    positive integer limit.
  * `:timeout` — per-iteration timeout in ms; defaults to `:infinity`.

  `break!` in an iteration stops scheduling/consuming further iterations and
  leaves `nil` gaps; already completed iterations are preserved in order
  (upstream Roast semantics).
  """

  alias RoastEx.Runner
  alias RoastEx.Cogs.Nested
  alias RoastEx.Output.MapResult

  def run(collection, opts, ctx) do
    scope = Nested.scope!(:map, opts)
    collection = to_list!(collection)
    parallel = Keyword.get(opts, :parallel, false)
    timeout = Keyword.get(opts, :timeout, :infinity)

    results =
      case parallel do
        false ->
          serial(collection, scope, ctx)

        true ->
          parallel_run(collection, scope, ctx, System.schedulers_online(), timeout)

        limit when is_integer(limit) and limit > 0 ->
          parallel_run(collection, scope, ctx, limit, timeout)

        other ->
          raise ArgumentError,
                "map :parallel must be false, true, or a positive integer, got: #{inspect(other)}"
      end

    {items, contexts} = pad(results, length(collection))
    %MapResult{items: items, contexts: contexts}
  end

  defp to_list!(collection) do
    Enum.to_list(collection)
  rescue
    Protocol.UndefinedError ->
      raise ArgumentError,
            "map expects an enumerable collection from the step block, got: #{inspect(collection)}"
  end

  @doc "Returns the list of final outputs (or maps `fun` over them)."
  def collect(%MapResult{items: items}, fun) when is_function(fun, 1), do: Enum.map(items, fun)
  def collect(%MapResult{items: items}), do: items

  @doc "Runs `fun` with each iteration's child context (`nil` stays `nil`)."
  def from(%MapResult{contexts: contexts}, fun) when is_function(fun, 1) do
    Enum.map(contexts, fn
      nil -> nil
      child_ctx -> fun.(child_ctx)
    end)
  end

  @doc "Reduces over non-nil iteration outputs."
  def reduce(%MapResult{items: items}, acc, fun) when is_function(fun, 2) do
    items
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(acc, fun)
  end

  defp serial(collection, scope, ctx) do
    acc =
      Enum.reduce_while(Enum.with_index(collection), [], fn {item, index}, acc ->
        {final_output, child_ctx, control} = Runner.run_scope(ctx, scope, item, index)
        acc = [{final_output, child_ctx} | acc]

        if control == :break do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end)

    Enum.reverse(acc)
  end

  defp parallel_run(collection, scope, ctx, concurrency, timeout) do
    acc =
      Task.Supervisor.async_stream_nolink(
        RoastEx.TaskSupervisor,
        Enum.with_index(collection),
        fn {item, index} -> Runner.run_scope(ctx, scope, item, index) end,
        max_concurrency: concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: true,
        zip_input_on_exit: true
      )
      |> Enum.reduce_while([], fn
        {:ok, {final_output, child_ctx, control}}, acc ->
          acc = [{final_output, child_ctx} | acc]

          if control == :break do
            {:halt, acc}
          else
            {:cont, acc}
          end

        {:exit, {_item, reason}}, _acc ->
          raise "map iteration failed: #{inspect(reason)}"

        {:exit, reason}, _acc ->
          raise "map iteration failed: #{inspect(reason)}"
      end)

    Enum.reverse(acc)
  end

  defp pad(results, total) do
    {items, contexts} = Enum.unzip(results)
    missing = max(total - length(items), 0)
    padding = List.duplicate(nil, missing)
    {items ++ padding, contexts ++ padding}
  end
end
