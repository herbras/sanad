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

  test "map runs a mapper over a collection (serial and parallel)" do
    steps = [
      %{
        type: :map,
        name: :doubled,
        opts: [parallel: 2],
        fun: fn _ctx -> %{collection: [1, 2, 3], mapper: fn _ctx, item -> item * 2 end} end
      }
    ]

    {ctx, :ok} = Runner.run_steps(steps, %Context{})
    assert ctx.outputs[:doubled].items == [2, 4, 6]
  end

  test "map defaults to serial and preserves input order" do
    steps = [
      %{
        type: :map,
        name: :doubled,
        opts: [],
        fun: fn _ctx -> %{collection: [3, 1, 2], mapper: fn _ctx, item -> item * 2 end} end
      }
    ]

    {ctx, :ok} = Runner.run_steps(steps, %Context{})
    assert ctx.outputs[:doubled].items == [6, 2, 4]
  end

  test "map parallel preserves input order" do
    steps = [
      %{
        type: :map,
        name: :doubled,
        opts: [parallel: 3],
        fun: fn _ctx ->
          %{
            collection: [1, 2, 3, 4],
            mapper: fn _ctx, item ->
              Process.sleep(20)
              item * 2
            end
          }
        end
      }
    ]

    {ctx, :ok} = Runner.run_steps(steps, %Context{})
    assert ctx.outputs[:doubled].items == [2, 4, 6, 8]
  end

  @tag capture_log: true
  test "map honors an explicit timeout instead of a hidden 5s default" do
    steps = [
      %{
        type: :map,
        name: :slow,
        opts: [parallel: 2, timeout: 50],
        fun: fn _ctx ->
          %{
            collection: [1],
            mapper: fn _ctx, item ->
              Process.sleep(500)
              item
            end
          }
        end
      }
    ]

    assert_raise RuntimeError, ~r/:timeout/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end

  @tag capture_log: true
  test "map surfaces mapper failures instead of hiding them" do
    steps = [
      %{
        type: :map,
        name: :boom,
        opts: [parallel: 2],
        fun: fn _ctx ->
          %{
            collection: [1, 2],
            mapper: fn _ctx, item -> if item == 2, do: raise("nope"), else: item end
          }
        end
      }
    ]

    assert_raise RuntimeError, ~r/map failed/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end
end
