defmodule RoastEx.E2ETest do
  @moduledoc """
  End-to-end tests: run workflow files through the real `mix roast.execute` CLI
  in separate OS processes (file -> Code.require_file -> DSL -> runner -> cogs
  -> summary + printed outputs), with no network or API keys involved.
  """

  use ExUnit.Case, async: false

  @project_root Path.expand("..", __DIR__)

  defp run_cli(args) do
    System.cmd("mix", ["roast.execute" | args],
      cd: @project_root,
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}]
    )
  end

  test "mix roast.execute runs a full cmd/elixir/call/map/repeat workflow" do
    {output, status} = run_cli(["examples/local_pipeline.exs", "--module", "LocalPipeline"])

    assert status == 0, "mix roast.execute exited #{status}:\n#{output}"

    # summary line
    assert output =~ "RoastEx workflow finished in"
    # cmd + elixir cog
    assert output =~ ~s("hello world")
    # call + nested scope final output
    assert output =~ ~s("HELLO WORLD")
    # map over ["a", "bb", "ccc"] in parallel
    assert output =~ "[1, 2, 3]"
    # repeat feeding values forward and stopping on break!
    assert output =~ "results: [1, 2, 3, nil]"
  end

  test "named scopes, call_cog and from/2 (ported upstream tutorial)" do
    {output, status} = run_cli(["examples/reusable_scopes.exs", "--module", "ReusableScopes"])

    assert status == 0, output
    assert output =~ "===================="
    assert output =~ "FIRST, SECOND"
  end

  test "--param values reach params(ctx)" do
    {output, status} =
      run_cli([
        "examples/params_demo.exs",
        "--module",
        "ParamsDemo",
        "--param",
        "name=world",
        "--param",
        "loud=true"
      ])

    assert status == 0, output
    assert output =~ "HELLO WORLD"
  end

  test "control flow example: fail! gating and fail_on_error: false" do
    {output, status} = run_cli(["examples/control_flow.exs", "--module", "ControlFlow"])

    assert status == 0, output
    assert output =~ "recipe with milk for: milk, eggs, bread"
    assert output =~ "grep: milk"
  end

  test "a failing workflow exits non-zero with the fail! message" do
    path = Path.join(System.tmp_dir!(), "roast_failing_#{System.unique_integer([:positive])}.exs")

    File.write!(path, """
    defmodule RoastFailingWorkflow do
      use RoastEx.DSL

      execute do
        elixir_cog(:a, do: fail!("intentional failure"))
      end
    end
    """)

    try do
      {output, status} = run_cli([path, "--module", "RoastFailingWorkflow"])

      assert status != 0
      assert output =~ "intentional failure"
    after
      File.rm(path)
    end
  end
end
