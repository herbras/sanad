defmodule RoastEx.Context do
  @moduledoc "Runtime context: named cog outputs + config + params."

  defstruct outputs: %{}, config: %{}, params: %{}, workflow_dir: "."

  @type t :: %__MODULE__{
          outputs: map(),
          config: map(),
          params: map(),
          workflow_dir: String.t()
        }

  def put(%__MODULE__{} = ctx, name, output) do
    %{ctx | outputs: Map.put(ctx.outputs, name, output)}
  end

  def get(%__MODULE__{} = ctx, name) do
    Map.fetch(ctx.outputs, name)
  end

  def get!(%__MODULE__{} = ctx, name) do
    case Map.fetch(ctx.outputs, name) do
      {:ok, value} -> value
      :error -> raise KeyError, key: name, term: ctx.outputs
    end
  end
end
