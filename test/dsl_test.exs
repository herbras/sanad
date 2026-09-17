defmodule RoastEx.DSLTest do
  use ExUnit.Case, async: true

  defmodule SimpleWorkflow do
    use RoastEx.DSL

    config do
      %{abort_on_failure: false, chat: %{provider: :openai}}
    end

    execute do
      cmd(:hello, "echo hello")

      cmd :block_cmd do
        "echo block"
      end

      elixir_cog(:calc, do: 1 + 1)

      elixir_cog :uses_ctx do
        cmd!(ctx, :hello).stdout
      end
    end
  end

  defmodule StderrWorkflow do
    use RoastEx.DSL

    execute do
      cmd(:out, "echo out")
      cmd(:err, "echo err >&2")
    end
  end

  defmodule ScopedWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:top, do: :top)
    end

    execute :inner do
      elixir_cog(:a, do: :a)
      elixir_cog(:b, do: :b)
    end

    execute :other do
      elixir_cog(:c, do: :c)
    end
  end

  defmodule PerStepOptsWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog :a, abort_on_failure: false do
        fail!("nope")
      end

      elixir_cog(:b, do: :ran)
    end
  end

  defmodule FailingCmdWorkflow do
    use RoastEx.DSL

    execute do
      cmd(:bad, "false")
      elixir_cog(:after, do: :never)
    end
  end

  defmodule CmdOptsWorkflow do
    use RoastEx.DSL

    execute do
      cmd(:cwd, "pwd", cwd: "/tmp")
      cmd(:env, "echo $ROAST_TEST_VAR", env: %{"ROAST_TEST_VAR" => "ok"})
      cmd(:soft_fail, "false", fail_on_error: false)
    end
  end

  defmodule ShadowCtxWorkflow do
    use RoastEx.DSL

    execute do
      elixir_cog(:shadow, do: Enum.map([1, 2], fn ctx -> ctx * 2 end))
    end
  end

  test "config is normalized" do
    assert SimpleWorkflow.__roast_config__() ==
             %{abort_on_failure: false, chat: %{provider: :openai}}
  end

  test "steps keep source order, types and names" do
    steps = SimpleWorkflow.__roast_steps__()

    assert Enum.map(steps, & &1.type) == [:cmd, :cmd, :elixir, :elixir]
    assert Enum.map(steps, & &1.name) == [:hello, :block_cmd, :calc, :uses_ctx]
  end

  test "runner executes cmd and elixir steps without network" do
    ctx = RoastEx.run(SimpleWorkflow)

    assert ctx.outputs[:hello].stdout == "hello\n"
    assert ctx.outputs[:hello].stderr == ""
    assert ctx.outputs[:hello].status == 0
    assert ctx.outputs[:block_cmd].stdout == "block\n"
    assert ctx.outputs[:calc] == 2
    assert ctx.outputs[:uses_ctx] == "hello\n"
    assert ctx.statuses[:hello] == :ok
    assert ctx.statuses[:calc] == :ok
  end

  test "cmd separates stderr from stdout" do
    ctx = RoastEx.run(StderrWorkflow)

    assert ctx.outputs[:out].stdout == "out\n"
    assert ctx.outputs[:out].stderr == ""
    assert ctx.outputs[:err].stdout == ""
    assert ctx.outputs[:err].stderr == "err\n"
  end

  test "named scopes are grouped and excluded from the default scope" do
    scopes = ScopedWorkflow.__roast_scopes__()

    assert Enum.sort(Map.keys(scopes)) == [:inner, nil, :other]
    assert Enum.map(scopes[nil], & &1.name) == [:top]
    assert Enum.map(scopes[:inner], & &1.name) == [:a, :b]
    assert Enum.map(scopes[:other], & &1.name) == [:c]
    assert Enum.map(ScopedWorkflow.__roast_steps__(), & &1.name) == [:top]
  end

  test "top-level run does not execute named scopes" do
    ctx = RoastEx.run(ScopedWorkflow)

    assert ctx.outputs[:top] == :top
    refute Map.has_key?(ctx.outputs, :a)
  end

  test "per-step abort_on_failure: false from DSL options" do
    ctx = RoastEx.run(PerStepOptsWorkflow)

    assert ctx.statuses[:a] == :failed
    assert ctx.outputs[:b] == :ran
  end

  test "cmd failure with default fail_on_error aborts the workflow" do
    assert_raise RoastEx.CogFailedError, ~r/status 1/, fn ->
      RoastEx.run(FailingCmdWorkflow)
    end
  end

  test "cmd supports cwd, env and fail_on_error: false" do
    ctx = RoastEx.run(CmdOptsWorkflow)

    assert String.trim(ctx.outputs[:cwd].stdout) in ["/tmp", "/private/tmp"]
    assert String.trim(ctx.outputs[:env].stdout) == "ok"
    assert ctx.outputs[:soft_fail].status == 1
  end

  test "ctx shadowed by a nested fn does not break the step" do
    ctx = RoastEx.run(ShadowCtxWorkflow)

    assert ctx.outputs[:shadow] == [2, 4]
  end
end
