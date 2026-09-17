defmodule Sanad.OutputNotFoundError do
  @moduledoc "Raised when a named output is requested but was never produced."
  defexception [:name, :outputs]

  def message(%{name: name, outputs: outputs}) do
    "output #{inspect(name)} not found (available: #{inspect(Map.keys(outputs))})"
  end
end

defmodule Sanad.CogSkippedError do
  @moduledoc "Raised when a named output was produced by a skipped cog."
  defexception [:name]

  def message(%{name: name}) do
    "output #{inspect(name)} was skipped (skip! was called)"
  end
end

defmodule Sanad.CogFailedError do
  @moduledoc "Raised when a cog called fail! and the workflow aborts."
  defexception [:name, :reason]

  def message(%{name: name, reason: nil}) do
    "cog #{inspect(name)} failed (fail!)"
  end

  def message(%{name: name, reason: reason}) do
    "cog #{inspect(name)} failed (fail!): #{inspect(reason)}"
  end
end

defmodule Sanad.UnknownCogError do
  @moduledoc "Raised when a step references a cog type that is not registered."
  defexception [:type]

  def message(%{type: type}) do
    known = Sanad.Cog.Registry.types()

    "unknown cog type #{inspect(type)} (registered: #{inspect(known)})"
  end
end

defmodule Sanad.UnknownScopeError do
  @moduledoc "Raised when call/map/repeat references a scope that is not defined."
  defexception [:scope, :module]

  def message(%{scope: scope, module: module}) do
    defined =
      case module do
        nil -> []
        mod -> mod.__sanad_scopes__() |> Map.keys() |> Kernel.--([nil])
      end

    "unknown execution scope #{inspect(scope)} (defined scopes: #{inspect(defined)})"
  end
end

defmodule Sanad.MissingEnvError do
  @moduledoc "Raised when a required environment variable is missing."
  defexception [:name, :hint]

  def message(%{name: name, hint: nil}), do: "missing environment variable #{name}"

  def message(%{name: name, hint: hint}) do
    "missing environment variable #{name} — #{hint}"
  end
end

defmodule Sanad.InvalidConfigError do
  @moduledoc "Raised when workflow/cog configuration is invalid."
  defexception [:message]
end

defmodule Sanad.ChatError do
  @moduledoc "Raised when a chat provider request fails."
  defexception [:provider, :status, :body, :reason]

  def message(%{provider: provider, status: status, body: body}) when is_integer(status) do
    "chat provider #{inspect(provider)} returned HTTP #{status}: #{inspect(body)}"
  end

  def message(%{provider: provider, reason: reason}) do
    "chat provider #{inspect(provider)} request failed: #{inspect(reason)}"
  end
end

defmodule Sanad.AgentError do
  @moduledoc "Raised when an agent CLI invocation fails."
  defexception [:provider, :reason]

  def message(%{provider: provider, reason: reason}) do
    "agent provider #{inspect(provider)} #{reason}"
  end
end

defmodule Sanad.MissingExecutableError do
  @moduledoc "Raised when a required external binary is not on PATH."
  defexception [:name, :hint]

  def message(%{name: name, hint: nil}), do: "executable #{inspect(name)} not found on PATH"

  def message(%{name: name, hint: hint}) do
    "executable #{inspect(name)} not found on PATH — #{hint}"
  end
end

defmodule Sanad.CommandTimeoutError do
  @moduledoc "Raised when an external command exceeds its timeout."
  defexception [:command, :timeout, :stdout, :stderr]

  def message(%{command: command, timeout: timeout}) do
    "command timed out after #{inspect(timeout)}ms: #{command}"
  end
end
