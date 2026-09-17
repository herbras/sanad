defmodule Sanad.ControlFlow do
  @moduledoc """
  Control-flow primitives, mirroring Roast's `skip!` / `fail!` / `next!` / `break!`.

  They are implemented with `throw/1` and caught by the runner at the step
  boundary:

  * `skip!`   — the cog produces no output and is marked `:skipped`; the workflow continues.
  * `fail!`   — the cog is marked `:failed`; the workflow aborts when
    `abort_on_failure` is true (the default), otherwise it continues.
  * `next!`   — ends the current scope quietly (remaining steps are not run).
  * `break!`  — ends the current scope and propagates to the enclosing loop/scope.

  Messages are accepted for API compatibility with Roast, which discards them;
  here they are attached to `fail!` aborts and ignored otherwise.
  """

  @tag :sanad_control

  @spec skip!(term()) :: no_return()
  def skip!(message \\ nil), do: throw({@tag, :skip, message})

  @spec fail!(term()) :: no_return()
  def fail!(message \\ nil), do: throw({@tag, :fail, message})

  @spec next!(term()) :: no_return()
  def next!(message \\ nil), do: throw({@tag, :next, message})

  @spec break!(term()) :: no_return()
  def break!(message \\ nil), do: throw({@tag, :break, message})

  @doc false
  def catch_tag, do: @tag
end
