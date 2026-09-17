defmodule RoastEx.Config do
  @moduledoc """
  Configuration helpers for workflows.

  Workflow config is a plain map (or keyword list) of per-cog settings plus
  process-wide flags such as `:abort_on_failure`.

      config do
        %{
          chat: %{provider: :openai, model: "gpt-4o-mini"},
          agent: %{provider: :pi},
          abort_on_failure: true
        }
      end

  Keyword lists are normalized to maps recursively, so both shapes work.
  """

  alias RoastEx.Context

  @doc """
  Normalizes nested keyword lists into maps so cogs can use `Map.get/3`
  uniformly.
  """
  @spec normalize(term()) :: term()
  def normalize(%_{} = struct), do: struct

  def normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize(value)} end)
  end

  def normalize(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Map.new(list, fn {key, value} -> {key, normalize(value)} end)
    else
      Enum.map(list, &normalize/1)
    end
  end

  def normalize(other), do: other

  @doc """
  Whether a failed cog should abort the workflow.

  Step options win over global workflow config; the default is `true`,
  matching upstream Roast.
  """
  @spec abort_on_failure?(Context.t(), keyword()) :: boolean()
  def abort_on_failure?(%Context{} = ctx, opts) do
    Keyword.get(opts, :abort_on_failure, Map.get(ctx.config, :abort_on_failure, true))
  end

  @doc "Fetches a required env var, raising an actionable error when missing."
  @spec fetch_env!(String.t(), String.t() | nil) :: String.t()
  def fetch_env!(name, hint \\ nil) when is_binary(name) do
    case System.get_env(name) do
      nil -> raise RoastEx.MissingEnvError, name: name, hint: hint
      "" -> raise RoastEx.MissingEnvError, name: name, hint: hint
      value -> value
    end
  end
end
