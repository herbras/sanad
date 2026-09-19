defmodule Sanad.Event.Cog do
  @moduledoc "One `cmd(:name)` element of an event path."

  defstruct [:type, :name]

  @type t :: %__MODULE__{type: atom(), name: atom()}
end

defmodule Sanad.Event.Scope do
  @moduledoc "One `{:scope}[index]` element of an event path."

  defstruct [:scope, :index]

  @type t :: %__MODULE__{scope: atom() | nil, index: non_neg_integer()}
end

defmodule Sanad.Event do
  @moduledoc """
  A run event, normalized from the raw `:telemetry` callback arguments.

  Workflows emit events as they run: a `start`/`stop` pair per workflow, per
  nested scope and per cog, plus `stdout`, `stderr`, `block` and `log` events
  in between. Handlers receive the raw telemetry arguments; `new/3` turns them
  into this struct so renderers and collectors work on one shape.

  Every event carries the `path` where it happened, which renders the way
  Roast renders it:

      map_cog(:reviewed) -> {:review_one}[2] -> cmd(:files)

  Events fire in the process that did the work. Concurrent `map` children
  therefore interleave, and only the events of a single path are totally
  ordered. See `Sanad.Events` for the emission side.
  """

  alias Sanad.Event.{Cog, Scope}

  defstruct [:name, :path, :measurements, :metadata, :at]

  @type element :: Cog.t() | Scope.t()
  @type path :: [element()]

  @type t :: %__MODULE__{
          name: [atom()],
          path: path(),
          measurements: map(),
          metadata: map(),
          at: DateTime.t()
        }

  @doc "All event names a handler can attach to."
  @spec names() :: [[atom()]]
  def names do
    [
      [:sanad, :workflow, :start],
      [:sanad, :workflow, :stop],
      [:sanad, :workflow, :exception],
      [:sanad, :scope, :start],
      [:sanad, :scope, :stop],
      [:sanad, :cog, :start],
      [:sanad, :cog, :stop],
      [:sanad, :cog, :exception],
      [:sanad, :cog, :stdout],
      [:sanad, :cog, :stderr],
      [:sanad, :cog, :block],
      [:sanad, :cog, :log]
    ]
  end

  @doc "Builds an event from the raw `:telemetry` handler arguments."
  @spec new([atom()], map(), map()) :: t()
  def new(name, measurements, metadata) do
    %__MODULE__{
      name: name,
      path: Map.get(metadata, :path, []),
      measurements: measurements,
      metadata: metadata,
      at: DateTime.utc_now()
    }
  end

  @doc "Duration of a `stop` or `exception` event in milliseconds."
  @spec duration_ms(t()) :: non_neg_integer() | nil
  def duration_ms(%__MODULE__{measurements: %{duration: duration}}) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  def duration_ms(%__MODULE__{}), do: nil

  @doc """
  Renders a path the way Roast's event monitor renders it.

      iex> Sanad.Event.format_path([%Sanad.Event.Cog{type: :map, name: :reviewed}])
      "map(:reviewed)"
  """
  @spec format_path(t() | path()) :: String.t()
  def format_path(%__MODULE__{path: path}), do: format_path(path)
  def format_path(path) when is_list(path), do: Enum.map_join(path, " -> ", &format_element/1)

  @doc "Renders one path element."
  @spec format_element(element()) :: String.t()
  def format_element(%Cog{type: type, name: name}), do: "#{type}(#{inspect(name)})"
  def format_element(%Scope{scope: scope, index: index}), do: "{#{inspect(scope)}}[#{index}]"

  @doc """
  True when `descendant` happened inside `ancestor` — that is, when the
  ancestor path is a prefix of the descendant path.
  """
  @spec inside?(path(), path()) :: boolean()
  def inside?(descendant, ancestor) when is_list(descendant) and is_list(ancestor) do
    length(descendant) >= length(ancestor) and
      Enum.take(descendant, length(ancestor)) == ancestor
  end
end
