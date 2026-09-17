defmodule RoastEx.OutputNotFoundError do
  @moduledoc "Raised when a named output is requested but was never produced."
  defexception [:name, :outputs]

  def message(%{name: name, outputs: outputs}) do
    "output #{inspect(name)} not found (available: #{inspect(Map.keys(outputs))})"
  end
end

defmodule RoastEx.CogSkippedError do
  @moduledoc "Raised when a named output was produced by a skipped cog."
  defexception [:name]

  def message(%{name: name}) do
    "output #{inspect(name)} was skipped (skip! was called)"
  end
end

defmodule RoastEx.CogFailedError do
  @moduledoc "Raised when a cog called fail! and the workflow aborts."
  defexception [:name, :reason]

  def message(%{name: name, reason: nil}) do
    "cog #{inspect(name)} failed (fail!)"
  end

  def message(%{name: name, reason: reason}) do
    "cog #{inspect(name)} failed (fail!): #{inspect(reason)}"
  end
end

defmodule RoastEx.UnknownCogError do
  @moduledoc "Raised when a step references a cog type that is not registered."
  defexception [:type]

  def message(%{type: type}) do
    known = RoastEx.Cog.Registry.types()

    "unknown cog type #{inspect(type)} (registered: #{inspect(known)})"
  end
end

defmodule RoastEx.UnknownScopeError do
  @moduledoc "Raised when call/map/repeat references a scope that is not defined."
  defexception [:scope, :module]

  def message(%{scope: scope, module: module}) do
    defined =
      case module do
        nil -> []
        mod -> mod.__roast_scopes__() |> Map.keys() |> Kernel.--([nil])
      end

    "unknown execution scope #{inspect(scope)} (defined scopes: #{inspect(defined)})"
  end
end

defmodule RoastEx.MissingEnvError do
  @moduledoc "Raised when a required environment variable is missing."
  defexception [:name, :hint]

  def message(%{name: name, hint: nil}), do: "missing environment variable #{name}"

  def message(%{name: name, hint: hint}) do
    "missing environment variable #{name} — #{hint}"
  end
end
