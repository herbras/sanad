defmodule RoastEx.E2ETest do
  @moduledoc """
  End-to-end test: runs a workflow file through the real `mix roast.execute`
  CLI in a separate OS process (file -> Code.require_file -> DSL -> runner ->
  cogs -> printed outputs), with no network or API keys involved.
  """

  use ExUnit.Case, async: false

  @project_root Path.expand("..", __DIR__)

  test "mix roast.execute runs a full cmd/elixir/call/map/repeat workflow" do
    {output, status} =
      System.cmd(
        "mix",
        ["roast.execute", "examples/local_pipeline.exs", "--module", "LocalPipeline"],
        cd: @project_root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    assert status == 0, "mix roast.execute exited #{status}:\n#{output}"

    # cmd + elixir cog
    assert output =~ ~s("hello world")
    # call + nested scope final output
    assert output =~ ~s("HELLO WORLD")
    # map over ["a", "bb", "ccc"] in parallel
    assert output =~ "[1, 2, 3]"
    # repeat feeding values forward and stopping on break!
    assert output =~ "results: [1, 2, 3, nil]"
  end
end
