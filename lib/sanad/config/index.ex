defmodule Sanad.Config.Index do
  @moduledoc """
  Workflow configuration, indexed by how specific each entry is.

  Upstream Roast lets a workflow configure a cog type generally, a single
  named cog, or every cog whose name matches a pattern. This is the same
  thing as data:

  * `global` applies to every cog, whatever its type;
  * `general` applies to one cog type;
  * `patterns` applies to cogs of one type whose name matches, **in source
    order** — which is why it is a list and not a map;
  * `names` applies to one exactly named cog.

  `Sanad.Config.resolve/4` merges them in that order and then lets the
  step's own options win.
  """

  defstruct global: %{}, general: %{}, patterns: %{}, names: %{}

  @type cog_type :: atom()

  @type t :: %__MODULE__{
          global: map(),
          general: %{optional(cog_type()) => map()},
          patterns: %{optional(cog_type()) => [{Regex.t(), map()}]},
          names: %{optional(cog_type()) => %{optional(atom()) => map()}}
        }

  @typedoc "One declaration, as the `config` macro emits it."
  @type entry :: {cog_type() | :global, atom() | Regex.t() | nil, map() | keyword()}

  @doc "Builds an index from declarations, keeping their source order."
  @spec build([entry()]) :: t()
  def build(entries) when is_list(entries) do
    Enum.reduce(entries, %__MODULE__{}, &add(&2, &1))
  end

  defp add(index, {:global, _scope, values}) do
    %{index | global: Map.merge(index.global, normalize(values))}
  end

  defp add(index, {type, nil, values}) do
    merged = index.general |> Map.get(type, %{}) |> Map.merge(normalize(values))
    %{index | general: Map.put(index.general, type, merged)}
  end

  defp add(index, {type, %Regex{} = pattern, values}) do
    entries = Map.get(index.patterns, type, []) ++ [{pattern, normalize(values)}]
    %{index | patterns: Map.put(index.patterns, type, entries)}
  end

  defp add(index, {type, name, values}) when is_atom(name) do
    for_type = Map.get(index.names, type, %{})
    merged = for_type |> Map.get(name, %{}) |> Map.merge(normalize(values))
    %{index | names: Map.put(index.names, type, Map.put(for_type, name, merged))}
  end

  defp add(_index, {_type, scope, _values}) do
    raise ArgumentError,
          "config scope must be a cog name (atom) or a regex, got: #{inspect(scope)}"
  end

  @doc """
  Lifts the legacy map form, where a key naming a registered cog type is that
  type's general config and everything else is global.
  """
  @spec from_legacy(map() | keyword()) :: t()
  def from_legacy(config) do
    config = normalize(config)
    types = Sanad.Cog.Registry.types()

    Enum.reduce(config, %__MODULE__{}, fn {key, value}, index ->
      if key in types and is_map(value) do
        add(index, {key, nil, value})
      else
        add(index, {:global, nil, %{key => value}})
      end
    end)
  end

  @doc """
  Renders the index back into the legacy flat map, which is what
  `Sanad.Context` exposes as `config` for workflows that read it directly.

  This is a lossy view on purpose: the per-name and per-pattern layers have
  no place in a flat map. Cogs never need them, because the runner resolves
  everything into a step's options before a cog runs; a workflow that wants
  the full picture should read `ctx.config_index`.
  """
  @spec legacy_map(t()) :: map()
  def legacy_map(%__MODULE__{} = index) do
    Map.merge(index.global, index.general)
  end

  defp normalize(values), do: Sanad.Config.normalize(values)
end
