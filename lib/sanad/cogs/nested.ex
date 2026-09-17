defmodule Sanad.Cogs.Nested do
  @moduledoc false

  @doc """
  Reads the `:scope` option required by `call`, `map` and `repeat`.
  """
  @spec scope!(atom(), keyword()) :: atom()
  def scope!(type, opts) do
    case Keyword.get(opts, :scope) do
      nil ->
        raise ArgumentError,
              "#{type} requires a :scope option naming an execute scope, e.g. " <>
                "#{type}_cog :result, scope: :inner do ... end"

      scope when is_atom(scope) ->
        scope

      other ->
        raise ArgumentError, "#{type} :scope must be an atom, got: #{inspect(other)}"
    end
  end
end
