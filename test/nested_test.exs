defmodule RoastEx.NestedTest do
  use ExUnit.Case, async: true

  alias RoastEx.{Context, Helpers, Runner}

  defmodule CallWorkflow do
    use RoastEx.DSL

    config do
      %{abort_on_failure: false}
    end

    execute do
      elixir_cog(:a, do: :outer)

      call_cog :inner_result, scope: :inner do
        :value_passed
      end
    end

    execute :inner do
      elixir_cog(:a, do: {:inner, ctx.scope_value})
      elixir_cog(:b, do: :last_inner)
    end
  end

  defmodule IndexWorkflow do
    use RoastEx.DSL

    execute do
      call_cog :c, scope: :index_echo, index: 7 do
        :x
      end
    end

    execute :index_echo do
      elixir_cog(:i, do: ctx.scope_index)
    end
  end

  defmodule EmptyScopeWorkflow do
    use RoastEx.DSL

    execute do
      call_cog :empty, scope: :empty_scope do
        :x
      end

      elixir_cog(:after, do: :ok)
    end

    execute :empty_scope do
    end
  end

  defmodule MapWorkflow do
    use RoastEx.DSL

    config do
      %{abort_on_failure: false}
    end

    execute do
      map_cog :parallel_map, scope: :double_one, parallel: 2 do
        [1, 2, 3]
      end

      map_cog :serial_map, scope: :double_one do
        [4, 5]
      end
    end

    execute :double_one do
      elixir_cog(:double, do: ctx.scope_value * 2)
    end
  end

  defmodule MapBreakWorkflow do
    use RoastEx.DSL

    execute do
      map_cog :taken, scope: :stop_at_three do
        [1, 2, 3, 4]
      end
    end

    execute :stop_at_three do
      elixir_cog :check do
        if ctx.scope_value >= 3, do: break!()
        ctx.scope_value
      end
    end
  end

  defmodule ParallelBreakWorkflow do
    use RoastEx.DSL

    execute do
      map_cog :cancelled, scope: :slow_then_break, parallel: 3 do
        [0, 1, 2]
      end

      map_cog :kept, scope: :delayed_break_keep, parallel: 3 do
        [0, 1, 2]
      end
    end

    execute :slow_then_break do
      elixir_cog :step do
        case ctx.scope_value do
          0 ->
            Process.sleep(300)
            :slow_done

          1 ->
            break!()

          _ ->
            Process.sleep(2000)
            :never
        end
      end
    end

    execute :delayed_break_keep do
      elixir_cog :step do
        case ctx.scope_value do
          0 ->
            :done0

          1 ->
            Process.sleep(150)
            break!()

          _ ->
            :done2
        end
      end
    end
  end

  defmodule MapFailureWorkflow do
    use RoastEx.DSL

    execute do
      map_cog :bad, scope: :boom do
        [0]
      end
    end

    execute :boom do
      elixir_cog(:x, do: raise("boom inside scope"))
    end
  end

  defmodule ParallelErrorWorkflow do
    use RoastEx.DSL

    execute do
      map_cog :bad, scope: :raiser, parallel: 4 do
        [1, 2, 3]
      end
    end

    execute :raiser do
      elixir_cog :x do
        if ctx.scope_value == 2, do: raise("parallel boom")
        ctx.scope_value
      end
    end
  end

  defmodule InitialIndexWorkflow do
    use RoastEx.DSL

    execute do
      map_cog :idx, scope: :echo_index, parallel: 0, initial_index: 10 do
        [1, 2, 3]
      end
    end

    execute :echo_index do
      elixir_cog(:i, do: ctx.scope_index)
    end
  end

  defmodule RepeatWorkflow do
    use RoastEx.DSL

    execute do
      repeat_cog :counter, scope: :count_up, max_iterations: 10 do
        0
      end
    end

    execute :count_up do
      elixir_cog :step do
        value = ctx.scope_value
        if value >= 3, do: break!(value)
        value + 1
      end
    end
  end

  defmodule NilMaxRepeatWorkflow do
    use RoastEx.DSL

    execute do
      repeat_cog :unbounded, scope: :count_two, max_iterations: nil do
        0
      end
    end

    execute :count_two do
      elixir_cog :step do
        value = ctx.scope_value
        if value >= 2, do: break!()
        value + 1
      end
    end
  end

  defmodule MaxIterationsWorkflow do
    use RoastEx.DSL

    execute do
      repeat_cog :limited, scope: :increment, max_iterations: 3 do
        0
      end

      repeat_cog :defaulted, scope: :increment do
        0
      end
    end

    execute :increment do
      elixir_cog(:step, do: ctx.scope_value + 1)
    end
  end

  defmodule CallFailWorkflow do
    use RoastEx.DSL

    config do
      %{abort_on_failure: false}
    end

    execute do
      call_cog :r, scope: :failing do
        :x
      end

      elixir_cog(:after, do: :ran)
    end

    execute :failing do
      elixir_cog(:a, do: fail!("inner boom"))
      elixir_cog(:b, do: :never)
    end
  end

  test "call runs a named scope and isolates outputs" do
    ctx = RoastEx.run(CallWorkflow)

    assert ctx.outputs[:a] == :outer
    assert ctx.outputs[:inner_result].value == :last_inner
    assert ctx.outputs[:inner_result].context.outputs[:a] == {:inner, :value_passed}
    refute Map.has_key?(ctx.outputs, :b)

    assert Helpers.from(ctx.outputs[:inner_result], & &1.outputs[:a]) == {:inner, :value_passed}
  end

  test "call passes :index as scope_index" do
    ctx = RoastEx.run(IndexWorkflow)

    assert ctx.outputs[:c].value == 7
    assert ctx.outputs[:c].index == 7
  end

  test "empty named scopes are runnable and return nil" do
    ctx = RoastEx.run(EmptyScopeWorkflow)

    assert Map.has_key?(EmptyScopeWorkflow.__roast_scopes__(), :empty_scope)
    assert ctx.outputs[:empty].value == nil
    assert ctx.outputs[:after] == :ok
  end

  test "map runs nested cogs serially and in parallel, preserving order" do
    ctx = RoastEx.run(MapWorkflow)

    assert ctx.outputs[:parallel_map].items == [2, 4, 6]
    assert ctx.outputs[:serial_map].items == [8, 10]
    assert Helpers.collect(ctx.outputs[:parallel_map]) == [2, 4, 6]
    assert Helpers.from(ctx.outputs[:parallel_map], & &1.scope_value) == [1, 2, 3]
  end

  test "map preserves order with real work per item" do
    ctx = RoastEx.run(InitialIndexWorkflow)

    assert ctx.outputs[:idx].items == [10, 11, 12]
    assert Helpers.from(ctx.outputs[:idx], & &1.scope_value) == [1, 2, 3]
  end

  test "inner outputs are namespaced and do not overwrite outer outputs" do
    ctx = RoastEx.run(MapWorkflow)

    refute Map.has_key?(ctx.outputs, :double)
    assert ctx.outputs[:parallel_map].contexts |> Enum.all?(&(&1.outputs[:double] != nil))
  end

  test "break! inside a map iteration stops remaining iterations with nil gaps" do
    ctx = RoastEx.run(MapBreakWorkflow)

    assert ctx.outputs[:taken].items == [1, 2, nil, nil]
  end

  @tag capture_log: true
  test "errors inside nested scopes propagate" do
    assert_raise RuntimeError, ~r/boom inside scope/, fn ->
      RoastEx.run(MapFailureWorkflow)
    end
  end

  @tag capture_log: true
  test "parallel errors keep the original exception type and message" do
    assert_raise RuntimeError, ~r/parallel boom/, fn ->
      RoastEx.run(ParallelErrorWorkflow)
    end
  end

  test "parallel break! cancels still-running siblings promptly" do
    started = System.monotonic_time(:millisecond)
    ctx = RoastEx.run(ParallelBreakWorkflow)
    elapsed = System.monotonic_time(:millisecond) - started

    # Without cancellation the slow sibling (2s sleep) would dominate.
    assert elapsed < 1000, "expected prompt cancellation, took #{elapsed}ms"
    assert ctx.outputs[:cancelled].items == [nil, nil, nil]
  end

  test "parallel break! keeps siblings that already completed" do
    ctx = RoastEx.run(ParallelBreakWorkflow)

    assert ctx.outputs[:kept].items == [:done0, nil, :done2]
  end

  test "collect/2 maps run iterations and keeps unrun gaps nil" do
    ctx = RoastEx.run(MapBreakWorkflow)
    collected = Helpers.collect(ctx.outputs[:taken], fn item -> {:got, item} end)

    # iteration 2 ran and broke (nil output); iteration 3 never ran.
    assert collected == [{:got, 1}, {:got, 2}, {:got, nil}, nil]
  end

  test "reduce/3 is accumulator-first and ignores a nil block return" do
    ctx = RoastEx.run(MapWorkflow)

    assert Helpers.reduce(ctx.outputs[:serial_map], [], fn acc, item -> acc ++ [item] end) == [
             8,
             10
           ]

    assert Helpers.reduce(ctx.outputs[:serial_map], 100, fn _acc, _item -> nil end) == 100
  end

  test "repeat feeds final output forward and stops on break!" do
    ctx = RoastEx.run(RepeatWorkflow)

    assert ctx.outputs[:counter].results == [1, 2, 3, nil]
    assert ctx.outputs[:counter].value == nil
    assert Helpers.collect(ctx.outputs[:counter]) == [1, 2, 3, nil]
    # run iterations include the breaking one (nil output); the callback decides
    assert Helpers.reduce(ctx.outputs[:counter], 0, fn acc, item -> acc + (item || 0) end) == 6
  end

  test "repeat accepts max_iterations: nil as no guard" do
    ctx = RoastEx.run(NilMaxRepeatWorkflow)

    assert ctx.outputs[:unbounded].results == [1, 2, nil]
  end

  test "repeat honors max_iterations and the 1000-iteration default guard" do
    ctx = RoastEx.run(MaxIterationsWorkflow)

    assert ctx.outputs[:limited].results == [1, 2, 3]
    assert length(ctx.outputs[:defaulted].results) == 1000
  end

  test "fail! inside a call scope (continue mode) does not abort the outer workflow" do
    ctx = RoastEx.run(CallFailWorkflow)

    assert ctx.outputs[:after] == :ran
    assert ctx.outputs[:r].context.statuses[:a] == :failed
    assert ctx.outputs[:r].context.outputs[:b] == :never
    assert ctx.outputs[:r].value == :never
  end

  test "unknown scope raises a clear error" do
    steps = [%{type: :call, name: :x, opts: [scope: :nope], fun: fn _ctx -> 1 end}]

    assert_raise RoastEx.UnknownScopeError, ~r/unknown execution scope :nope/, fn ->
      Runner.run_steps(steps, %Context{module: CallWorkflow})
    end
  end

  test "call/map/repeat require a :scope option" do
    steps = [%{type: :call, name: :x, opts: [], fun: fn _ctx -> 1 end}]

    assert_raise ArgumentError, ~r/:scope/, fn ->
      Runner.run_steps(steps, %Context{})
    end
  end

  test "duplicate cog names in one scope raise a compile error" do
    module = "RoastEx.DuplicateCogName#{System.unique_integer([:positive])}"

    source = """
    defmodule #{module} do
      use RoastEx.DSL

      execute do
        elixir_cog(:x, do: 1)
        elixir_cog(:x, do: 2)
      end
    end
    """

    assert_raise CompileError, ~r/duplicate cog name/, fn ->
      Code.compile_string(source)
    end
  end
end
