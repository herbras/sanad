defmodule Sanad.Helpers do
  @moduledoc """
  Functions available inside cog input blocks (imported by `use Sanad.DSL`).
  """

  alias Sanad.Context

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
  def from(%Sanad.Output.Call{} = output, fun) when is_function(fun, 1),
    do: Sanad.Cogs.Call.from(output, fun)

  def from(%Sanad.Output.MapResult{} = output, fun) when is_function(fun, 1),
    do: Sanad.Cogs.Map.from(output, fun)

  def from(%Sanad.Output.Repeat{} = output, fun) when is_function(fun, 1),
    do: Sanad.Cogs.Repeat.from(output, fun)

  @doc "Returns final outputs of a `map` / `repeat` output (optionally mapped)."
  def collect(%Sanad.Output.MapResult{} = output), do: Sanad.Cogs.Map.collect(output)
  def collect(%Sanad.Output.Repeat{} = output), do: Sanad.Cogs.Repeat.collect(output)

  def collect(%Sanad.Output.MapResult{} = output, fun) when is_function(fun, 1),
    do: Sanad.Cogs.Map.collect(output, fun)

  def collect(%Sanad.Output.Repeat{} = output, fun) when is_function(fun, 1),
    do: Sanad.Cogs.Repeat.collect(output, fun)

  @doc "Reduces over the non-nil final outputs of a `map` / `repeat` output."
  def reduce(%Sanad.Output.MapResult{} = output, acc, fun) when is_function(fun, 2),
    do: Sanad.Cogs.Map.reduce(output, acc, fun)

  def reduce(%Sanad.Output.Repeat{} = output, acc, fun) when is_function(fun, 2),
    do: Sanad.Cogs.Repeat.reduce(output, acc, fun)

  defdelegate skip!(message \\ nil), to: Sanad.ControlFlow
  defdelegate fail!(message \\ nil), to: Sanad.ControlFlow
  defdelegate next!(message \\ nil), to: Sanad.ControlFlow
  defdelegate break!(message \\ nil), to: Sanad.ControlFlow
end
