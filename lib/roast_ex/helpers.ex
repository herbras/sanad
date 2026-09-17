defmodule RoastEx.Helpers do
  @moduledoc """
  Functions available inside cog input blocks (imported by `use RoastEx.DSL`).
  """

  alias RoastEx.Context

  @doc "Returns the output of a named `chat` cog."
  def chat!(%Context{} = ctx, name), do: Context.get!(ctx, name)

  @doc "Returns the output of a named `cmd` cog."
  def cmd!(%Context{} = ctx, name), do: Context.get!(ctx, name)

  @doc "Returns the output of a named `agent` cog."
  def agent!(%Context{} = ctx, name), do: Context.get!(ctx, name)

  @doc "Returns the output of a named `elixir_cog` / `ruby` cog."
  def elixir!(%Context{} = ctx, name), do: Context.get!(ctx, name)

  @doc "Returns the output of any named cog."
  def output!(%Context{} = ctx, name), do: Context.get!(ctx, name)

  @doc "Workflow params passed to the runner."
  def params(%Context{} = ctx), do: ctx.params

  @doc "Returns the status (`:ok` / `:skipped` / `:failed`) of a named output."
  def status(%Context{} = ctx, name), do: Context.status(ctx, name)

  @doc """
  Runs `fun` with each child context behind a `call` / `map` / `repeat` output,
  giving access to the nested scope's inner outputs.
  """
  def from(%RoastEx.Output.Call{} = output, fun) when is_function(fun, 1),
    do: RoastEx.Cogs.Call.from(output, fun)

  def from(%RoastEx.Output.MapResult{} = output, fun) when is_function(fun, 1),
    do: RoastEx.Cogs.Map.from(output, fun)

  def from(%RoastEx.Output.Repeat{} = output, fun) when is_function(fun, 1),
    do: RoastEx.Cogs.Repeat.from(output, fun)

  @doc "Returns final outputs of a `map` / `repeat` output (optionally mapped)."
  def collect(%RoastEx.Output.MapResult{} = output), do: RoastEx.Cogs.Map.collect(output)
  def collect(%RoastEx.Output.Repeat{} = output), do: RoastEx.Cogs.Repeat.collect(output)

  def collect(%RoastEx.Output.MapResult{} = output, fun) when is_function(fun, 1),
    do: RoastEx.Cogs.Map.collect(output, fun)

  def collect(%RoastEx.Output.Repeat{} = output, fun) when is_function(fun, 1),
    do: RoastEx.Cogs.Repeat.collect(output, fun)

  @doc "Reduces over the non-nil final outputs of a `map` / `repeat` output."
  def reduce(%RoastEx.Output.MapResult{} = output, acc, fun) when is_function(fun, 2),
    do: RoastEx.Cogs.Map.reduce(output, acc, fun)

  def reduce(%RoastEx.Output.Repeat{} = output, acc, fun) when is_function(fun, 2),
    do: RoastEx.Cogs.Repeat.reduce(output, acc, fun)

  defdelegate skip!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate fail!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate next!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate break!(message \\ nil), to: RoastEx.ControlFlow
end
