defmodule Sanad.Cogs.Repeat do
  @moduledoc """
  Runs a named `execute :scope` block repeatedly.

      execute do
        repeat_cog :counter, scope: :count_up, max_iterations: 10 do
          0
        end
      end

      execute :count_up do
        elixir_cog :step do
          value = ctx.scope_value
          if value >= 3, do: break!(value)
          value + 1
        end
      end

  The step block supplies the first iteration's `scope_value`; each iteration's
  final output becomes the next iteration's `scope_value` (upstream Roast
  semantics). The output is `%Sanad.Output.Repeat{}` with `results` (one final
  output per iteration, `nil` for the iteration that called `break!`) and the
  matching child `contexts`.

  Options:

  * `:scope` — required.
  * `:max_iterations` — loop guard; defaults to `1000`. `nil` or `:infinity`
    disables the guard (upstream Roast has no guard at all).
  """

  alias Sanad.Runner
  alias Sanad.Cogs.Nested
  alias Sanad.Output.Repeat

  @default_max_iterations 1000

  def run(value, opts, ctx) do
    scope = Nested.scope!(:repeat, opts)

    max_iterations =
      case Keyword.get(opts, :max_iterations, @default_max_iterations) do
        nil ->
          :infinity

        :infinity ->
          :infinity

        max when is_integer(max) and max > 0 ->
          max

        other ->
          raise ArgumentError,
                "repeat :max_iterations must be a positive integer, nil, or :infinity, got: #{inspect(other)}"
      end

    results =
      Enum.reverse(loop(ctx, scope, value, 0, max_iterations, []))

    {iteration_outputs, contexts} = unzip_pairs(results)

    %Repeat{
      scope: scope,
      results: iteration_outputs,
      contexts: contexts,
      value: List.last(iteration_outputs)
    }
  end

  @doc "Returns all iteration outputs (mapping `fun` over each run iteration)."
  def collect(%Repeat{results: results}), do: results

  def collect(%Repeat{results: results, contexts: contexts}, fun) when is_function(fun, 1) do
    Enum.zip(contexts, results)
    |> Enum.map(fn
      {nil, _result} -> nil
      {_child_ctx, result} -> fun.(result)
    end)
  end

  @doc "Runs `fun` with each iteration's child context (`nil` stays `nil`)."
  def from(%Repeat{contexts: contexts}, fun) when is_function(fun, 1) do
    Enum.map(contexts, fn
      nil -> nil
      child_ctx -> fun.(child_ctx)
    end)
  end

  @doc """
  Reduces over iterations with an accumulator-first callback (`fun.(acc, item)`).
  A `nil` return keeps the previous accumulator (upstream semantics).
  """
  def reduce(%Repeat{results: results, contexts: contexts}, acc, fun) when is_function(fun, 2) do
    Enum.zip(contexts, results)
    |> Enum.reduce(acc, fn
      {nil, _result}, acc -> acc
      {_child_ctx, result}, acc -> reduce_step(fun, acc, result)
    end)
  end

  @doc "Returns the output of a specific iteration."
  def iteration(%Repeat{results: results}, index), do: Enum.at(results, index)

  defp loop(_ctx, _scope, _value, index, max, acc)
       when is_integer(max) and index >= max do
    acc
  end

  defp loop(ctx, scope, value, index, max, acc) do
    {final_output, child_ctx, control} = Runner.run_scope(ctx, scope, value, index)
    acc = [{final_output, child_ctx} | acc]

    case control do
      :break -> acc
      _ -> loop(ctx, scope, final_output, index + 1, max, acc)
    end
  end

  defp reduce_step(fun, acc, item) do
    case fun.(acc, item) do
      nil -> acc
      new_acc -> new_acc
    end
  end

  defp unzip_pairs([]), do: {[], []}
  defp unzip_pairs(pairs), do: Enum.unzip(pairs)
end
