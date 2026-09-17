defmodule RoastEx.Cogs.AgentTest do
  use ExUnit.Case, async: false

  alias RoastEx.Context

  setup do
    dir = Path.join(System.tmp_dir!(), "roast_agent_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  defp stub(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp ctx(dir), do: %Context{workflow_dir: dir}

  test "pi: prompt via stdin, JSON protocol parsed, session captured", %{dir: dir} do
    stub_path =
      stub(dir, "pi", """
      cat > "$CAPTURE"
      pwd > "$PWD_OUT"
      printf '%s\\n' '{"type":"session","version":3,"id":"sess-42"}'
      printf '%s\\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"PO"}}'
      printf '%s\\n' '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"PONG"}]}]}'
      """)

    capture = Path.join(dir, "prompt.txt")
    pwd_out = Path.join(dir, "pwd.txt")

    out =
      RoastEx.Cogs.Agent.run(
        "hello pi",
        [command: [stub_path], env: %{"CAPTURE" => capture, "PWD_OUT" => pwd_out}],
        ctx(dir)
      )

    assert out.response == "PONG"
    assert out.provider == :pi
    assert out.raw.session == "sess-42"
    assert File.read!(capture) == "hello pi"
    pwd = String.trim(File.read!(pwd_out))
    assert pwd == dir or pwd == Path.join("/private", dir)
  end

  test "claude: stream-json result parsed", %{dir: dir} do
    stub_path =
      stub(dir, "claude", """
      cat > /dev/null
      printf '%s\\n' '{"type":"system","subtype":"init"}'
      printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"CLAUDE OK"}'
      """)

    out = RoastEx.Cogs.Agent.run("hi", [provider: :claude, command: [stub_path]], ctx(dir))

    assert out.response == "CLAUDE OK"
    assert out.provider == :claude
  end

  test "opencode: prompt passed as argv and text returned", %{dir: dir} do
    stub_path =
      stub(dir, "opencode", """
      printf '%s' "$*" > "$CAPTURE"
      printf 'OPENCODE OK'
      """)

    capture = Path.join(dir, "argv.txt")

    out =
      RoastEx.Cogs.Agent.run(
        "hello opencode",
        [provider: :opencode, command: [stub_path], env: %{"CAPTURE" => capture}],
        ctx(dir)
      )

    assert out.response == "OPENCODE OK"
    assert String.contains?(File.read!(capture), "hello opencode")
  end

  test "agy: prompt passed as argv and text returned", %{dir: dir} do
    stub_path =
      stub(dir, "agy", """
      printf '%s' "$*" > "$CAPTURE"
      printf 'AGY OK'
      """)

    capture = Path.join(dir, "argv.txt")

    out =
      RoastEx.Cogs.Agent.run(
        "hello agy",
        [provider: :agy, command: [stub_path], env: %{"CAPTURE" => capture}],
        ctx(dir)
      )

    assert out.response == "AGY OK"
    assert String.contains?(File.read!(capture), "hello agy")
  end

  test "non-zero exit raises AgentError including stderr", %{dir: dir} do
    stub_path =
      stub(dir, "pi", """
      echo "boom stderr" >&2
      exit 3
      """)

    assert_raise RoastEx.AgentError, ~r/status 3.*boom stderr/s, fn ->
      RoastEx.Cogs.Agent.run("hi", [command: [stub_path]], ctx(dir))
    end
  end

  test "missing binary raises a clear error" do
    assert_raise RoastEx.MissingExecutableError, ~r/not found on PATH/, fn ->
      RoastEx.Cogs.Agent.run("hi", [command: ["definitely-not-real-xyz"]], %Context{})
    end
  end

  test "timeout raises AgentError", %{dir: dir} do
    stub_path = stub(dir, "pi", "sleep 5\n")

    assert_raise RoastEx.AgentError, ~r/timed out/, fn ->
      RoastEx.Cogs.Agent.run("hi", [command: [stub_path], timeout: 150], ctx(dir))
    end
  end
end
