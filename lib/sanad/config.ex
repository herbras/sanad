defmodule Sanad.Config do
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

  Config can also be declared per cog name or per pattern, which is the form
  upstream Roast teaches:

      config do
        global(abort_on_failure: true)
        chat(provider: :openai, model: "gpt-4o-mini")
        chat(~r/^review_/, temperature: 0.0)
        chat(:summary, model: "gpt-4o")
      end

  Both forms build a `Sanad.Config.Index`; see `resolve/4` for the order the
  layers are merged in.
  """

  alias Sanad.Config.Index
  alias Sanad.Context

  # Values that are meant to stay keyword lists all the way into a cog, and
  # so must not be normalized into maps on the way through config.
  @passthrough_keys [:req_options, :env, :headers, :command]

  @doc """
  Normalizes nested keyword lists into maps so cogs can use `Map.get/3`
  uniformly.
  """
  @spec normalize(term()) :: term()
  def normalize(%_{} = struct), do: struct

  def normalize(map) when is_map(map) do
    Map.new(map, &normalize_pair/1)
  end

  def normalize(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Map.new(list, &normalize_pair/1)
    else
      Enum.map(list, &normalize/1)
    end
  end

  def normalize(other), do: other

  defp normalize_pair({key, value}) when key in @passthrough_keys, do: {key, value}
  defp normalize_pair({key, value}), do: {key, normalize(value)}

  @doc """
  Resolves the options a cog runs with.

  Merged lowest to highest: global config, the cog type's general config,
  every pattern whose regex matches the cog's name (in source order), the
  exactly named config, and finally the step's own options.
  """
  @spec resolve(Index.t(), atom(), atom() | nil, keyword()) :: keyword()
  def resolve(%Index{} = index, type, name, step_opts \\ []) when is_list(step_opts) do
    index.global
    |> Map.merge(Map.get(index.general, type, %{}))
    |> merge_patterns(Map.get(index.patterns, type, []), name)
    |> merge_name(index, type, name)
    |> Map.to_list()
    |> Keyword.merge(step_opts)
  end

  defp merge_patterns(acc, _patterns, nil), do: acc

  defp merge_patterns(acc, patterns, name) do
    subject = Atom.to_string(name)

    Enum.reduce(patterns, acc, fn {pattern, values}, acc ->
      if Regex.match?(pattern, subject), do: Map.merge(acc, values), else: acc
    end)
  end

  defp merge_name(acc, _index, _type, nil), do: acc

  defp merge_name(acc, index, type, name) do
    Map.merge(acc, index.names |> Map.get(type, %{}) |> Map.get(name, %{}))
  end

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
      nil -> raise Sanad.MissingEnvError, name: name, hint: hint
      "" -> raise Sanad.MissingEnvError, name: name, hint: hint
      value -> value
    end
  end
end
