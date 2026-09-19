defmodule ChatStreamTest do
  use ExUnit.Case, async: false

  alias Sanad.Cogs.Chat.Stream
  alias Sanad.Context

  setup do
    System.put_env("OPENAI_API_KEY", "test-key")
    System.put_env("ANTHROPIC_API_KEY", "test-key")
    on_exit(fn -> Enum.each(~w(OPENAI_API_KEY ANTHROPIC_API_KEY), &System.delete_env/1) end)
    :ok
  end

  describe "decode/3" do
    test "assembles a delta split across chunks" do
      {deltas, buffer} =
        Stream.decode(:openai, "", ~s(data: {"choices":[{"delta":{"con))

      assert deltas == []

      {deltas, buffer} = Stream.decode(:openai, buffer, ~s(tent":"Hel"}}]}\n))
      assert deltas == ["Hel"]

      {deltas, _buffer} =
        Stream.decode(:openai, buffer, ~s(data: {"choices":[{"delta":{"content":"lo"}}]}\n))

      assert deltas == ["lo"]
    end

    test "ignores terminators, comments and event lines" do
      chunk = ": ping\nevent: message\ndata: [DONE]\n\n"

      assert Stream.decode(:openai, "", chunk) == {[], ""}
    end

    test "reads anthropic content block deltas" do
      chunk = """
      event: content_block_delta
      data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}

      data: {"type":"message_stop"}

      """

      assert {["hi"], ""} = Stream.decode(:anthropic, "", chunk)
    end

    test "reads gemini candidate parts" do
      chunk = ~s(data: {"candidates":[{"content":{"parts":[{"text":"a"},{"text":"b"}]}}]}\n)

      assert {["a", "b"], ""} = Stream.decode(:gemini, "", chunk)
    end

    test "finish/2 flushes a line the stream never terminated" do
      buffer = ~s(data: {"choices":[{"delta":{"content":"tail"}}]})

      assert Stream.finish(:openai, buffer) == ["tail"]
    end
  end

  describe "a streaming chat step" do
    defp collect_stdout do
      parent = self()
      id = {__MODULE__, make_ref()}

      :telemetry.attach(
        id,
        [:sanad, :cog, :stdout],
        fn _name, _measurements, metadata, _config ->
          send(parent, {:stdout, metadata.data})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    defp drain_stdout(acc \\ []) do
      receive do
        {:stdout, data} -> drain_stdout([data | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    test "assembles the answer and emits each delta as it arrives" do
      collect_stdout()

      Req.Test.stub(:stream_openai, fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, ~s(data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n))

        {:ok, conn} =
          Plug.Conn.chunk(
            conn,
            ~s(data: {"choices":[{"delta":{"content":"lo"}}]}\n\ndata: [DONE]\n\n)
          )

        conn
      end)

      out =
        Sanad.Cogs.Chat.run(
          "hi",
          [stream: true, req_options: [plug: {Req.Test, :stream_openai}]],
          %Context{}
        )

      assert out.response == "Hello"
      assert drain_stdout() == ["Hel", "lo"]
    end

    test "asks the provider to stream" do
      parent = self()

      Req.Test.stub(:stream_flag, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:body, Jason.decode!(body)})

        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, ~s(data: {"choices":[{"delta":{"content":"x"}}]}\n\n))
        conn
      end)

      Sanad.Cogs.Chat.run(
        "hi",
        [stream: true, req_options: [plug: {Req.Test, :stream_flag}]],
        %Context{}
      )

      assert_received {:body, %{"stream" => true}}
    end

    test "a stream is not retried, because retrying would replay text" do
      parent = self()

      Req.Test.stub(:stream_failing, fn conn ->
        send(parent, :attempt)
        Plug.Conn.send_resp(conn, 500, ~s({"error":"boom"}))
      end)

      assert_raise Sanad.ChatError, fn ->
        Sanad.Cogs.Chat.run(
          "hi",
          [stream: true, req_options: [plug: {Req.Test, :stream_failing}]],
          %Context{}
        )
      end

      assert_received :attempt
      refute_received :attempt
    end
  end
end
