defmodule RoastEx.RunnerTest do
  use ExUnit.Case, async: true

  alias RoastEx.{Context, Helpers, Runner}

  defmodule SkipWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:a, do: skip!())
      elixir_cog(:b, do: :ran)
    end
  end

  defmodule FailContinueWorkflow do
    use RoastEx.DSL

    config do
      %{abort_on_failure: false}
    end

    execute do
      elixir_cog(:a, do: fail!("nope"))
      elixir_cog(:b, do: :ran)
    end
  end

  defmodule FailAbortWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:a, do: fail!("boom"))
      elixir_cog(:b, do: :never)
    end
  end

  defmodule BreakWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:a, do: break!())
      elixir_cog(:b, do: :never)
    end
  end

  defmodule NextWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:a, do: next!())
      elixir_cog(:b, do: :never)
    end
  end

  test "skip! marks the output skipped and continues" do
    ctx = RoastEx.run(SkipWorkflow)

    assert ctx.statuses[:a] == :skipped
    refute Map.has_key?(ctx.outputs, :a)
    assert ctx.outputs[:b] == :ran
  end

  test "fail! with abort_on_failure: false records failure and continues" do
    ctx = RoastEx.run(FailContinueWorkflow)

    assert ctx.statuses[:a] == :failed
    refute Map.has_key?(ctx.outputs, :a)
    assert ctx.outputs[:b] == :ran
  end

  test "fail! with default abort_on_failure raises" do
    assert_raise RoastEx.CogFailedError, ~r/"boom"/, fn ->
      RoastEx.run(FailAbortWorkflow)
    end
  end

  test "per-step abort_on_failure: false overrides the default" do
    steps = [
      %{
        type: :elixir,
        name: :a,
        opts: [abort_on_failure: false],
        fun: fn _ -> RoastEx.ControlFlow.fail!("x") end
      },
      %{type: :elixir, name: :b, opts: [], fun: fn _ -> :ran end}
    ]

    {ctx, :ok} = Runner.run_steps(steps, %Context{})
    assert ctx.statuses[:a] == :failed
    assert ctx.outputs[:b] == :ran
  end

  test "break! stops the remaining steps quietly" do
    ctx = RoastEx.run(BreakWorkflow)

    refute Map.has_key?(ctx.outputs, :b)
    assert ctx.statuses[:a] == nil
  end

  test "next! stops the remaining steps quietly" do
    ctx = RoastEx.run(NextWorkflow)

    refute Map.has_key?(ctx.outputs, :b)
  end

  test "unknown cog type raises a clear error" do
    steps = [%{type: :nope, name: :x, opts: [], fun: fn _ctx -> :input end}]

    assert_raise RoastEx.UnknownCogError, ~r/unknown cog type :nope/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end

  test "missing output raises a clear error naming available outputs" do
    steps = [
      %{type: :elixir, name: :a, opts: [], fun: fn _ctx -> :ok end},
      %{type: :elixir, name: :b, opts: [], fun: fn ctx -> Helpers.cmd!(ctx, :missing) end}
    ]

    assert_raise RoastEx.OutputNotFoundError, ~r/:a/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end

  test "reading a skipped output raises CogSkippedError" do
    steps = [
      %{type: :elixir, name: :a, opts: [], fun: fn _ctx -> RoastEx.ControlFlow.skip!() end},
      %{type: :elixir, name: :b, opts: [], fun: fn ctx -> Helpers.cmd!(ctx, :a) end}
    ]

    assert_raise RoastEx.CogSkippedError, ~r/:a/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end
end
