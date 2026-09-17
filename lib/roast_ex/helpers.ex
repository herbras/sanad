defmodule RoastEx.Helpers do
  @moduledoc "Functions available inside cog input blocks."

  alias RoastEx.Context

  def chat!(ctx, name), do: Context.get!(ctx, name)
  def cmd!(ctx, name), do: Context.get!(ctx, name)
  def agent!(ctx, name), do: Context.get!(ctx, name)
  def elixir!(ctx, name), do: Context.get!(ctx, name)
  def output!(ctx, name), do: Context.get!(ctx, name)

  def params(ctx), do: ctx.params
  def config(ctx), do: ctx.config
end
