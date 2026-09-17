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
    iterations that never ran.
  * `contexts` — matching child contexts (see `from/2`, `collect/2`, `reduce/3`).

  Options:

  * `:scope` — required.
  * `:parallel` — `false` (default, serial), `true` (scheduler count),
    `0` (unlimited), or a positive integer limit.
  * `:timeout` — per-iteration timeout in ms; defaults to `:infinity`.
    A timed-out iteration aborts the map with a `RuntimeError`.
  * `:initial_index` — offset added to `scope_index` (upstream semantics).

  Iterations are monitored in completion order (upstream `Async::Barrier`
  semantics):

  * `break!` in an iteration cancels still-running siblings promptly and
    leaves `nil` gaps; iterations that already completed keep their values,
    even at higher indexes.
  * An exception in any iteration cancels siblings and is re-raised in the
    caller with its original type and stacktrace.
  """

  alias RoastEx.Runner
  alias RoastEx.Cogs.Nested
  alias RoastEx.Output.MapResult

  def run(collection, opts, ctx) do
    scope = Nested.scope!(:map, opts)
    collection = to_list!(collection)
    concurrency = concurrency!(Keyword.get(opts, :parallel, false))
    timeout = Keyword.get(opts, :timeout, :infinity)
    initial_index = Keyword.get(opts, :initial_index, 0)

    results =
      collection
      |> Enum.with_index()
      |> run_all(scope, ctx, concurrency, timeout, initial_index)

    {items, contexts} = pad_results(results, length(collection))
    %MapResult{items: items, contexts: contexts}
  end

  @doc "Returns the list of final outputs (mapping `fun` over run iterations)."
  def collect(%MapResult{items: items}), do: items

  def collect(%MapResult{items: items, contexts: contexts}, fun) when is_function(fun, 1) do
    Enum.zip(contexts, items)
    |> Enum.map(fn
      {nil, _item} -> nil
      {_child_ctx, item} -> fun.(item)
    end)
  end

  @doc "Runs `fun` with each run iteration's child context (`nil` stays `nil`)."
  def from(%MapResult{contexts: contexts}, fun) when is_function(fun, 1) do
    Enum.map(contexts, fn
      nil -> nil
      child_ctx -> fun.(child_ctx)
    end)
  end

  @doc """
  Reduces over run iterations with an accumulator-first callback
  (`fun.(acc, item)`). Iterations that never ran are skipped; a `nil` return
  keeps the previous accumulator (upstream semantics).
  """
  def reduce(%MapResult{items: items, contexts: contexts}, acc, fun) when is_function(fun, 2) do
    Enum.zip(contexts, items)
    |> Enum.reduce(acc, fn
      {nil, _item}, acc -> acc
      {_child_ctx, item}, acc -> reduce_step(fun, acc, item)
    end)
  end

  # --- iteration engine -----------------------------------------------------

  defp run_all(indexed, scope, ctx, concurrency, timeout, initial_index) do
    state = %{
      pending:
        Enum.map(indexed, fn {item, position} -> {item, position + initial_index, position} end),
      running: %{},
      results: %{},
      halted: false,
      scope: scope,
      ctx: ctx,
      concurrency: concurrency,
      timeout: timeout
    }

    loop(state).results
  end

  defp loop(state) do
    state = start_pending(state)

    if map_size(state.running) == 0 do
      drain_downs()
      state
    else
      state |> await_one() |> loop()
    end
  end

  defp start_pending(%{halted: true} = state), do: state
  defp start_pending(%{pending: []} = state), do: state

  defp start_pending(%{concurrency: :infinity} = state) do
    state |> start_one() |> start_pending()
  end

  defp start_pending(state) do
    if map_size(state.running) >= state.concurrency do
      state
    else
      state |> start_one() |> start_pending()
    end
  end

  defp start_one(state) do
    [{item, scope_index, position} | rest] = state.pending

    task =
      Task.Supervisor.async_nolink(RoastEx.TaskSupervisor, fn ->
        Runner.run_scope(state.ctx, state.scope, item, scope_index)
      end)

    entry = %{task: task, position: position, started: now_ms()}

    %{state | pending: rest, running: Map.put(state.running, task.ref, entry)}
  end

  defp await_one(state) do
    wait = remaining_timeout(state.running, state.timeout)

    receive do
      {ref, result} when is_map_key(state.running, ref) ->
        {entry, running} = Map.pop(state.running, ref)
        handle_result(%{state | running: running}, entry, {:ok, result})

      {:DOWN, ref, :process, _pid, reason} when is_map_key(state.running, ref) ->
        {entry, running} = Map.pop(state.running, ref)
        handle_result(%{state | running: running}, entry, {:exit, reason})

      _stale ->
        await_one(state)
    after
      wait -> kill_expired(state)
    end
  end

  defp handle_result(state, %{position: position}, {:ok, {final_output, child_ctx, control}}) do
    state = %{state | results: Map.put(state.results, position, {final_output, child_ctx})}

    if control == :break do
      halt(state)
    else
      state
    end
  end

  defp handle_result(state, _entry, {:exit, reason}) do
    halt(state)
    raise_iteration_error(reason)
  end

  defp halt(state) do
    Enum.each(state.running, fn {_ref, entry} -> Task.shutdown(entry.task, :brutal_kill) end)
    %{state | running: %{}, halted: true}
  end

  defp kill_expired(state) do
    now = now_ms()

    expired =
      Enum.filter(state.running, fn {_ref, entry} -> now - entry.started >= state.timeout end)

    if expired == [] do
      state
    else
      {_ref, entry} = hd(expired)
      halt(state)

      raise "map iteration #{entry.position} timed out after #{state.timeout}ms"
    end
  end

  defp remaining_timeout(_running, :infinity), do: :infinity

  defp remaining_timeout(running, timeout) do
    running
    |> Enum.map(fn {_ref, entry} -> entry.started end)
    |> Enum.min(fn -> now_ms() end)
    |> Kernel.+(timeout)
    |> Kernel.-(now_ms())
    |> max(0)
  end

  defp raise_iteration_error(reason) do
    case reason do
      {exception, stacktrace} when is_list(stacktrace) ->
        if is_exception(exception) do
          reraise exception, stacktrace
        else
          raise "map iteration failed: #{inspect(exception)}"
        end

      exception when is_exception(exception) ->
        raise exception

      other ->
        raise "map iteration failed: #{inspect(other)}"
    end
  end

  defp reduce_step(fun, acc, item) do
    case fun.(acc, item) do
      nil -> acc
      new_acc -> new_acc
    end
  end

  defp drain_downs do
    receive do
      {:DOWN, _ref, :process, _pid, _reason} -> drain_downs()
    after
      5 -> :ok
    end
  end

  defp concurrency!(false), do: 1
  defp concurrency!(true), do: System.schedulers_online()
  defp concurrency!(0), do: :infinity
  defp concurrency!(limit) when is_integer(limit) and limit > 0, do: limit

  defp concurrency!(other) do
    raise ArgumentError,
          "map :parallel must be false, true, 0 (unlimited) or a positive integer, got: #{inspect(other)}"
  end

  defp pad_results(results, total) do
    pairs =
      for position <- 0..(total - 1)//1 do
        Map.get(results, position, {nil, nil})
      end

    {items, contexts} = Enum.unzip(pairs)
    {items, contexts}
  end

  defp to_list!(collection) do
    Enum.to_list(collection)
  rescue
    Protocol.UndefinedError ->
      raise ArgumentError,
            "map expects an enumerable collection from the step block, got: #{inspect(collection)}"
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
