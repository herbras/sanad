defmodule Sanad.Summary do
  @moduledoc """
  Compact end-of-run summary and CLI param parsing.
  """

  alias Sanad.Context

  @doc """
  Renders a one-line result summary plus per-cog status/timing lines.
  """
  @spec render(Context.t(), non_neg_integer()) :: String.t()
  def render(%Context{} = ctx, elapsed_ms) do
    {ok, skipped, failed} =
      Enum.reduce(ctx.statuses, {0, 0, 0}, fn
        {_name, :ok}, {ok, skipped, failed} -> {ok + 1, skipped, failed}
        {_name, :skipped}, {ok, skipped, failed} -> {ok, skipped + 1, failed}
        {_name, :failed}, {ok, skipped, failed} -> {ok, skipped, failed + 1}
      end)

    header =
      "Sanad workflow finished in #{elapsed_ms}ms — #{ok} ok, #{skipped} skipped, #{failed} failed"

    lines =
      ctx.statuses
      |> Enum.sort_by(fn {name, _status} -> to_string(name) end)
      |> Enum.map_join("\n", fn {name, status} ->
        "  [#{status}] #{name} (#{Map.get(ctx.timings, name, 0)}ms)"
      end)

    if lines == "", do: header, else: header <> "\n" <> lines
  end

  @doc """
  Parses repeated `--param key=value` strings into a map. `--param key`
  (without `=`) becomes `true`.
  """
  @spec parse_params([String.t()] | nil) :: map()
  def parse_params(nil), do: %{}
  def parse_params([]), do: %{}
  def parse_params(value) when is_binary(value), do: parse_params([value])

  def parse_params(values) when is_list(values) do
    Enum.reduce(values, %{}, fn value, acc ->
      case String.split(value, "=", parts: 2) do
        [key, val] -> Map.put(acc, key, val)
        [key] -> Map.put(acc, key, true)
      end
    end)
  end
end
