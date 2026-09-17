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

  defdelegate skip!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate fail!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate next!(message \\ nil), to: RoastEx.ControlFlow
  defdelegate break!(message \\ nil), to: RoastEx.ControlFlow
end
