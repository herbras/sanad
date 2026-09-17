defmodule Sanad.Cogs.CmdTest do
  use ExUnit.Case, async: true

  alias Sanad.{Context, Runner}

  defp run(command, opts \\ []) do
    step = %{type: :cmd, name: :x, opts: opts, fun: fn _ctx -> command end}
    {ctx, _control} = Runner.run_steps([step], %Context{})
    ctx.outputs[:x]
  end

  test "captures stdout, stderr and status separately" do
    out = run("echo out; echo err >&2")

    assert out.stdout == "out\n"
    assert out.stderr == "err\n"
    assert out.status == 0
  end

  test "fail_on_error: false records a non-zero status instead of failing" do
    out = run("exit 7", fail_on_error: false)

    assert out.status == 7
  end

  test "cwd and env options are honored" do
    out = run("pwd; echo $ROAST_CMD_TEST", cwd: "/tmp", env: %{"ROAST_CMD_TEST" => "ok"})

    assert String.trim(out.stdout) in ["/tmp\nok", "/private/tmp\nok"]
  end

  test "timeout raises CommandTimeoutError" do
    assert_raise Sanad.CommandTimeoutError, ~r/timed out/, fn ->
      run("sleep 5", timeout: 100)
    end
  end
end
