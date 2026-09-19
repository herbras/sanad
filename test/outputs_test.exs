defmodule OutputsTest do
  use ExUnit.Case, async: true

  defmodule ProjectedWorkflow do
    use Sanad.DSL

    execute :inner do
      elixir_cog(:a, do: 1)
      elixir_cog(:b, do: 2)

      outputs do
        {output!(ctx, :a), output!(ctx, :b)}
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule TopLevelWorkflow do
    use Sanad.DSL

    execute do
      elixir_cog(:a, do: 4)

      outputs do
        output!(ctx, :a) * 10
      end
    end
  end

  defmodule ScopeValueWorkflow do
    use Sanad.DSL

    execute :echo do
      elixir_cog(:ignored, do: :ignored)

      outputs do
        {ctx.scope_value, ctx.scope_index}
      end
    end

    execute do
      call_cog(:called, scope: :echo, index: 7, do: :value)
    end
  end

  defmodule SkippingWorkflow do
    use Sanad.DSL

    execute :inner do
      elixir_cog(:a, do: 1)

      outputs do
        skip!()
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule FailingWorkflow do
    use Sanad.DSL

    config do
      %{abort_on_failure: false}
    end

    execute :inner do
      elixir_cog(:a, do: 1)

      outputs do
        fail!("bad projection")
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule NextWorkflow do
    use Sanad.DSL

    execute :inner do
      elixir_cog(:a, do: 1)

      outputs do
        next!()
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule FailedReadWorkflow do
    use Sanad.DSL

    config do
      %{abort_on_failure: false}
    end

    execute :inner do
      elixir_cog(:a, do: fail!("cog failed"))

      outputs do
        output!(ctx, :a)
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule NestedReadWorkflow do
    use Sanad.DSL

    execute :leaf do
      elixir_cog :a do
        if ctx.scope_value == :stop, do: break!()
        :leaf_value
      end
    end

    execute :middle do
      call_cog(:a, scope: :leaf, do: :stop)

      outputs do
        # `:a` is declared here too, but this read is against the child
        # scope's context, so it must not be swallowed as one of ours.
        from(output!(ctx, :a), fn child -> output!(child, :a) end)
      end
    end

    execute do
      call_cog(:called, scope: :middle, do: :ignored)
    end
  end

  defmodule TypoWorkflow do
    use Sanad.DSL

    execute :inner do
      elixir_cog(:a, do: 1)

      outputs do
        output!(ctx, :nope)
      end
    end

    execute do
      call_cog(:called, scope: :inner, do: :ignored)
    end
  end

  defmodule LenientBreakWorkflow do
    use Sanad.DSL

    execute :item do
      elixir_cog :first do
        if ctx.scope_value == 2, do: break!()
        ctx.scope_value
      end

      elixir_cog(:second, do: :reached)

      outputs do
        {output!(ctx, :first), output!(ctx, :second)}
      end
    end

    execute do
      map_cog :mapped, scope: :item do
        [1, 2]
      end
    end
  end

  defmodule StrictBreakWorkflow do
    use Sanad.DSL

    execute :item do
      elixir_cog :first do
        if ctx.scope_value == 2, do: break!()
        ctx.scope_value
      end

      elixir_cog(:second, do: :reached)

      outputs! do
        {output!(ctx, :first), output!(ctx, :second)}
      end
    end

    execute do
      map_cog :mapped, scope: :item do
        [1, 2]
      end
    end
  end

  defmodule RepeatWorkflow do
    use Sanad.DSL

    execute :step do
      elixir_cog(:added, do: ctx.scope_value + 1)

      outputs do
        doubled = output!(ctx, :added) * 2
        if doubled > 6, do: break!()
        doubled
      end
    end

    execute do
      repeat_cog(:looped, scope: :step, do: 0)
    end
  end

  defmodule MapWorkflow do
    use Sanad.DSL

    execute :item do
      elixir_cog(:doubled, do: ctx.scope_value * 2)

      outputs do
        {:wrapped, output!(ctx, :doubled)}
      end
    end

    execute do
      map_cog :mapped, scope: :item do
        [1, 2]
      end
    end
  end

  test "a scope returns what its outputs block returns" do
    ctx = Sanad.run(ProjectedWorkflow, [])

    assert ctx.outputs[:called].value == {1, 2}
    assert ctx.outputs[:called].context.outputs[:b] == 2
  end

  test "the top-level scope stores its value on the context" do
    assert Sanad.run(TopLevelWorkflow, []).final_output == 40
  end

  test "the block sees the scope value and index" do
    assert Sanad.run(ScopeValueWorkflow, []).outputs[:called].value == {:value, 7}
  end

  test "skip! inside the block makes the value nil" do
    ctx = Sanad.run(SkippingWorkflow, [])

    assert ctx.outputs[:called].value == nil
    assert ctx.outputs[:called].context.outputs[:a] == 1
  end

  test "fail! inside the block raises, even with abort_on_failure disabled" do
    assert_raise Sanad.OutputsFailedError, ~r/scope :inner called fail!: "bad projection"/, fn ->
      Sanad.run(FailingWorkflow, [])
    end
  end

  test "next! inside the block makes the value nil" do
    assert Sanad.run(NextWorkflow, []).outputs[:called].value == nil
  end

  test "reading a cog that failed always raises, as upstream leaves it unswallowed" do
    assert_raise Sanad.CogFailedError, ~r/:a/, fn ->
      Sanad.run(FailedReadWorkflow, [])
    end
  end

  test "a missing output read out of a nested context is not swallowed as our own" do
    assert_raise Sanad.OutputNotFoundError, ~r/:a/, fn ->
      Sanad.run(NestedReadWorkflow, [])
    end
  end

  test "reading a name the scope never declared raises even from lenient outputs" do
    assert_raise Sanad.OutputNotFoundError, ~r/:nope/, fn ->
      Sanad.run(TypoWorkflow, [])
    end
  end

  test "outputs swallows reads of cogs a break! prevented from running" do
    assert Sanad.run(LenientBreakWorkflow, []).outputs[:mapped].items == [{1, :reached}, nil]
  end

  @tag capture_log: true
  test "outputs! raises on those same reads" do
    assert_raise Sanad.OutputNotFoundError, ~r/:first/, fn ->
      Sanad.run(StrictBreakWorkflow, [])
    end
  end

  test "break! inside the block ends the enclosing loop" do
    assert Sanad.run(RepeatWorkflow, []).outputs[:looped].results == [2, 6, nil]
  end

  test "map items come from the block while contexts still hold the cog outputs" do
    result = Sanad.run(MapWorkflow, []).outputs[:mapped]

    assert result.items == [{:wrapped, 2}, {:wrapped, 4}]
    assert Sanad.Cogs.Map.from(result, & &1.outputs[:doubled]) == [2, 4]
  end

  test "outputs is scope metadata, not a step" do
    assert Enum.map(ProjectedWorkflow.__sanad_scopes__()[:inner], & &1.name) == [:a, :b]
    assert %{kind: :outputs} = ProjectedWorkflow.__sanad_outputs__()[:inner]
  end

  test "declaring outputs twice for one scope is a compile error" do
    source = """
    defmodule DoubledOutputs do
      use Sanad.DSL

      execute :inner do
        elixir_cog(:a, do: 1)
        outputs do: :first
        outputs! do: :second
      end
    end
    """

    assert_raise CompileError, ~r/at most one outputs/, fn ->
      Code.compile_string(source)
    end
  end

  test "a scope without an outputs block still returns its last cog's output" do
    ctx = Sanad.run(MapWorkflow, [])

    assert ctx.final_output == ctx.outputs[:mapped]
  end
end
