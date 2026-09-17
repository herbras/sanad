defmodule RoastEx.Cogs.Call do
  @moduledoc """
  Runs a named `execute :scope` block once with the value produced by the step
  block.

      execute do
        call_cog :result, scope: :review_one do
          cmd!(ctx, :files).stdout
        end
      end

      execute :review_one do
        chat(:summary) do
          "Review: \#{ctx.scope_value}"
        end
      end

  The output is `%RoastEx.Output.Call{}` with the scope's final output in
  `value` and the child context in `context` (see `from/2`).

  Options: `:scope` (required), `:index` (default 0, passed as `scope_index`).
  `next!` / `break!` inside the scope end it quietly, matching upstream Roast.
  """

  alias RoastEx.{Output, Runner}
  alias RoastEx.Cogs.Nested

  def run(value, opts, ctx) do
    scope = Nested.scope!(:call, opts)
    index = Keyword.get(opts, :index, 0)

    {final_output, child_ctx, _control} = Runner.run_scope(ctx, scope, value, index)

    %Output.Call{scope: scope, index: index, value: final_output, context: child_ctx}
  end

  @doc """
  Runs `fun` with the child context of a call output, giving access to the
  scope's inner outputs.
  """
  def from(%Output.Call{context: child_ctx}, fun) when is_function(fun, 1) do
    fun.(child_ctx)
  end
end
