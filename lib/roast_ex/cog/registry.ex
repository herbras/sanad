defmodule RoastEx.Cog.Registry do
  @moduledoc """
  Maps step `type` atoms to cog modules.

  Built-ins are fixed; custom cogs are registered through the application
  environment (`Application.put_env(:roast_ex, :cogs, %{...})` via
  `register/2`), which lets tests and user code extend the workflow DSL.
  """

  @builtin %{
    cmd: RoastEx.Cogs.Cmd,
    chat: RoastEx.Cogs.Chat,
    agent: RoastEx.Cogs.Agent,
    elixir: RoastEx.Cogs.ElixirCog,
    map: RoastEx.Cogs.Map,
    call: RoastEx.Cogs.Call,
    repeat: RoastEx.Cogs.Repeat
  }

  @type cog_type :: atom()
  @type cog_module :: module()

  @doc "Looks up the cog module for a step type."
  @spec lookup(cog_type()) :: {:ok, cog_module()} | :error
  def lookup(type) when is_atom(type) do
    overrides = Application.get_env(:roast_ex, :cogs, %{})

    cond do
      Map.has_key?(overrides, type) -> {:ok, Map.fetch!(overrides, type)}
      Map.has_key?(@builtin, type) -> {:ok, Map.fetch!(@builtin, type)}
      true -> :error
    end
  end

  @doc """
  Registers (or overrides) a cog type.

  Overrides live in the global application environment, so registration is
  process-global and intended for setup/config time, not concurrent mutation.
  """
  @spec register(cog_type(), cog_module()) :: :ok
  def register(type, module) when is_atom(type) and is_atom(module) and not is_nil(module) do
    overrides = Application.get_env(:roast_ex, :cogs, %{})
    Application.put_env(:roast_ex, :cogs, Map.put(overrides, type, module))
    :ok
  end

  def register(_type, nil) do
    raise ArgumentError, "cog module cannot be nil"
  end

  @doc "Removes a previously registered override."
  @spec unregister(cog_type()) :: :ok
  def unregister(type) when is_atom(type) do
    overrides = Application.get_env(:roast_ex, :cogs, %{})
    Application.put_env(:roast_ex, :cogs, Map.delete(overrides, type))
    :ok
  end

  @doc "Built-in step types, used for error messages."
  @spec builtin_types() :: [cog_type()]
  def builtin_types, do: Map.keys(@builtin)

  @doc "All currently resolvable step types (built-ins plus overrides)."
  @spec types() :: [cog_type()]
  def types do
    overrides = Application.get_env(:roast_ex, :cogs, %{})
    Enum.uniq(Map.keys(@builtin) ++ Map.keys(overrides))
  end
end
