defmodule Sanad.Cogs.AgentTest do
  use ExUnit.Case, async: false

  alias Sanad.Context

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
      Sanad.Cogs.Agent.run(
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

  test "pi: turns and per-model usage are normalized into stats", %{dir: dir} do
    stub_path =
      stub(dir, "pi", """
      cat > /dev/null
      printf '%s\\n' '{"type":"session","version":3,"id":"sess-7"}'
      printf '%s\\n' '{"type":"turn_start"}'
      printf '%s\\n' '{"type":"message_end","message":{"role":"assistant","model":"pi-1","usage":{"input":10,"output":4,"cacheRead":2,"cost":{"total":0.5}},"content":[{"type":"text","text":"A"}]}}'
      printf '%s\\n' '{"type":"turn_start"}'
      printf '%s\\n' '{"type":"message_end","message":{"role":"assistant","model":"pi-1","usage":{"input":6,"output":3,"cost":{"total":0.25}},"content":[{"type":"text","text":"B"}]}}'
      """)

    out = Sanad.Cogs.Agent.run("hi", [command: [stub_path]], ctx(dir))

    assert out.session == "sess-7"
    assert out.stats.num_turns == 2
    assert out.stats.usage.input_tokens == 16
    assert out.stats.usage.output_tokens == 7
    assert out.stats.usage.cache_read_tokens == 2
    assert out.stats.usage.cost_usd == 0.75
    assert out.stats.model_usage["pi-1"].input_tokens == 16
  end

  test "a provider that reports no usage leaves the figures nil", %{dir: dir} do
    stub_path = stub(dir, "opencode", "printf 'plain answer\\n'")

    out = Sanad.Cogs.Agent.run("hi", [provider: :opencode, command: [stub_path]], ctx(dir))

    assert out.session == nil
    assert out.stats.num_turns == nil
    assert out.stats.usage.input_tokens == nil
    assert out.stats.model_usage == %{}
  end

  test "claude: session id, turns and usage come off the result event", %{dir: dir} do
    stub_path =
      stub(dir, "claude", """
      cat > /dev/null
      printf '%s\\n' '{"type":"system","subtype":"init","session_id":"claude-sess"}'
      printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"OK","num_turns":3,"total_cost_usd":0.125,"usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":5}}'
      """)

    out = Sanad.Cogs.Agent.run("hi", [provider: :claude, command: [stub_path]], ctx(dir))

    assert out.session == "claude-sess"
    assert out.stats.num_turns == 3
    assert out.stats.usage.input_tokens == 100
    assert out.stats.usage.output_tokens == 20
    assert out.stats.usage.cache_read_tokens == 5
    assert out.stats.usage.cost_usd == 0.125
  end

  test "claude: stream-json result parsed", %{dir: dir} do
    stub_path =
      stub(dir, "claude", """
      cat > /dev/null
      printf '%s\\n' '{"type":"system","subtype":"init"}'
      printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"CLAUDE OK"}'
      """)

    out = Sanad.Cogs.Agent.run("hi", [provider: :claude, command: [stub_path]], ctx(dir))

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
      Sanad.Cogs.Agent.run(
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
      Sanad.Cogs.Agent.run(
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

    assert_raise Sanad.AgentError, ~r/status 3.*boom stderr/s, fn ->
      Sanad.Cogs.Agent.run("hi", [command: [stub_path]], ctx(dir))
    end
  end

  test "missing binary raises a clear error" do
    assert_raise Sanad.MissingExecutableError, ~r/not found on PATH/, fn ->
      Sanad.Cogs.Agent.run("hi", [command: ["definitely-not-real-xyz"]], %Context{})
    end
  end

  test "timeout raises AgentError", %{dir: dir} do
    stub_path = stub(dir, "pi", "sleep 5\n")

    assert_raise Sanad.AgentError, ~r/timed out/, fn ->
      Sanad.Cogs.Agent.run("hi", [command: [stub_path], timeout: 150], ctx(dir))
    end
  end

  test "SANAD_DEFAULT_AGENT_PROVIDER is normalized and selects the provider", %{dir: dir} do
    System.put_env("SANAD_DEFAULT_AGENT_PROVIDER", "CLAUDE")
    on_exit(fn -> System.delete_env("SANAD_DEFAULT_AGENT_PROVIDER") end)

    stub_path =
      stub(dir, "claude", """
      cat > /dev/null
      printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"ENV CLAUDE"}'
      """)

    out = Sanad.Cogs.Agent.run("hi", [command: [stub_path]], ctx(dir))

    assert out.provider == :claude
    assert out.response == "ENV CLAUDE"
  end

  test "invalid SANAD_DEFAULT_AGENT_PROVIDER raises a clear error" do
    System.put_env("SANAD_DEFAULT_AGENT_PROVIDER", "nope")
    on_exit(fn -> System.delete_env("SANAD_DEFAULT_AGENT_PROVIDER") end)

    assert_raise Sanad.InvalidConfigError, ~r/invalid SANAD_DEFAULT_AGENT_PROVIDER/, fn ->
      Sanad.Cogs.Agent.run("hi", [], %Context{})
    end
  end

  test "agent config supplies model/session defaults", %{dir: dir} do
    stub_path =
      stub(dir, "pi", """
      printf '%s' "$*" > "$CAPTURE"
      cat > /dev/null
      printf '%s\\n' '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"OK"}]}]}'
      """)

    capture = Path.join(dir, "args.txt")
    config = %{agent: %{model: "m1", session: "s1"}}

    out =
      Sanad.Cogs.Agent.run(
        "hi",
        [command: [stub_path], env: %{"CAPTURE" => capture}],
        %Context{workflow_dir: dir, config: config}
      )

    assert out.response == "OK"
    args = File.read!(capture)
    assert args =~ "--model m1"
    assert args =~ "--fork s1"
  end
end
