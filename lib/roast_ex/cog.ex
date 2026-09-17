defmodule RoastEx.Cog do
  @moduledoc """
  Behaviour for RoastEx cogs.

  A cog receives the value produced by its step's input block, the step options,
  and the runtime context, and returns an output value that is stored under the
  step name.

  Built-in cogs live under `RoastEx.Cogs`; custom cogs can be registered with
  `RoastEx.Cog.Registry.register/2`.
  """

  alias RoastEx.Context

  @typedoc "Value produced by a step's input block (before the cog runs)."
  @type input :: term()

  @typedoc "Value stored as a named output."
  @type output :: term()

  @callback run(input :: input(), opts :: keyword(), ctx :: Context.t()) :: output()

  @callback validate_input(input :: input(), opts :: keyword()) :: :ok | {:error, term()}

  @optional_callbacks validate_input: 2

  @doc "Runs a cog module with the standard `run/3` contract."
  @spec run(module(), input(), keyword(), Context.t()) :: output()
  def run(cog, input, opts, ctx) when is_atom(cog) do
    if function_exported?(cog, :validate_input, 2) do
      case cog.validate_input(input, opts) do
        :ok ->
          :ok

        {:error, reason} ->
          raise ArgumentError, "invalid input for #{inspect(cog)}: #{inspect(reason)}"
      end
    end

    cog.run(input, opts, ctx)
  end
end
