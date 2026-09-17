defmodule RoastEx.Context do
  @moduledoc """
  Runtime context: named cog outputs plus their statuses, config, params and
  scope bookkeeping.

  Nested execution (see `RoastEx.Cogs.Call`, `Map`, `Repeat`) uses child
  contexts with their own outputs; `scope_value` / `scope_index` carry the
  value and index of the current nested invocation.
  """

  defstruct outputs: %{},
            statuses: %{},
            failures: %{},
            config: %{},
            params: %{},
            workflow_dir: ".",
            module: nil,
            scope_value: nil,
            scope_index: nil

  @type status :: :ok | :skipped | :failed

  @type t :: %__MODULE__{
          outputs: map(),
          statuses: map(),
          failures: map(),
          config: map(),
          params: map(),
          workflow_dir: String.t(),
          module: module() | nil,
          scope_value: term(),
          scope_index: non_neg_integer() | nil
        }

  @doc "Stores a named output and marks it `:ok`."
  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{} = ctx, name, output) do
    %{
      ctx
      | outputs: Map.put(ctx.outputs, name, output),
        statuses: Map.put(ctx.statuses, name, :ok)
    }
  end

  @doc "Records a status (`:skipped` / `:failed`) without storing an output."
  @spec put_status(t(), atom(), status()) :: t()
  def put_status(%__MODULE__{} = ctx, name, status) when status in [:ok, :skipped, :failed] do
    %{ctx | statuses: Map.put(ctx.statuses, name, status)}
  end

  @doc "Records the message passed to `fail!` for better error reporting."
  @spec put_failure(t(), atom(), term()) :: t()
  def put_failure(%__MODULE__{} = ctx, name, reason) do
    %{ctx | failures: Map.put(ctx.failures, name, reason)}
  end

  @doc "Returns the `fail!` reason for a name, if any."
  @spec failure_reason(t(), atom()) :: term()
  def failure_reason(%__MODULE__{} = ctx, name), do: Map.get(ctx.failures, name)

  @doc "Returns the status of a named output, or nil when it was never touched."
  @spec status(t(), atom()) :: status() | nil
  def status(%__MODULE__{} = ctx, name), do: Map.get(ctx.statuses, name)

  @doc "Fetches a named output."
  @spec get(t(), atom()) :: {:ok, term()} | :error
  def get(%__MODULE__{} = ctx, name), do: Map.fetch(ctx.outputs, name)

  @doc """
  Fetches a named output, raising a clear error when it is missing, skipped or
  failed.
  """
  @spec get!(t(), atom()) :: term()
  def get!(%__MODULE__{} = ctx, name) do
    case Map.fetch(ctx.outputs, name) do
      {:ok, value} ->
        value

      :error ->
        case Map.get(ctx.statuses, name) do
          :skipped ->
            raise RoastEx.CogSkippedError, name: name

          :failed ->
            raise RoastEx.CogFailedError, name: name, reason: Map.get(ctx.failures, name)

          _ ->
            raise RoastEx.OutputNotFoundError, name: name, outputs: ctx.outputs
        end
    end
  end
end
