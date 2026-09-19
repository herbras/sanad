defmodule ChatToolsTest do
  use ExUnit.Case, async: false

  alias Sanad.Context

  @weather_tool %{
    name: "get_weather",
    description: "Current weather for a city",
    parameters: %{type: "object", properties: %{city: %{type: "string"}}}
  }

  setup do
    for key <- ~w(OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY) do
      System.put_env(key, "test-key")
    end

    on_exit(fn ->
      Enum.each(~w(OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY), &System.delete_env/1)
    end)

    :ok
  end

  defp run(opts, stub_name, handler) do
    Req.Test.stub(stub_name, handler)
    Sanad.Cogs.Chat.run("hi", opts ++ [req_options: [plug: {Req.Test, stub_name}]], %Context{})
  end

  defp echo_body(parent, response) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(body)})
      Req.Test.json(conn, response)
    end
  end

  describe "JSON mode" do
    test "openai asks for a json object" do
      parent = self()

      run(
        [json: true],
        :json_openai,
        echo_body(parent, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      )

      assert_received {:body, %{"response_format" => %{"type" => "json_object"}}}
    end

    test "a raw response_format wins over the shorthand" do
      parent = self()
      schema = %{"type" => "json_schema", "json_schema" => %{"name" => "x"}}

      run(
        [json: true, response_format: schema],
        :json_schema,
        echo_body(parent, %{"choices" => [%{"message" => %{"content" => "{}"}}]})
      )

      assert_received {:body, %{"response_format" => ^schema}}
    end

    test "gemini asks for a json mime type" do
      parent = self()

      run(
        [provider: :gemini, json: true],
        :json_gemini,
        echo_body(parent, %{
          "candidates" => [%{"content" => %{"parts" => [%{"text" => "{}"}]}}]
        })
      )

      assert_received {:body,
                       %{"generationConfig" => %{"responseMimeType" => "application/json"}}}
    end

    test "anthropic says plainly that it has no JSON mode" do
      assert_raise Sanad.InvalidConfigError, ~r/no JSON mode/, fn ->
        run([provider: :anthropic, json: true], :json_anthropic, fn conn ->
          Req.Test.json(conn, %{})
        end)
      end
    end
  end

  describe "tool definitions" do
    test "openai wraps each tool in a function envelope" do
      parent = self()

      run(
        [tools: [@weather_tool], tool_choice: "auto"],
        :tools_openai,
        echo_body(parent, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
      )

      assert_received {:body, %{"tools" => [tool], "tool_choice" => "auto"}}
      assert tool["type"] == "function"
      assert tool["function"]["name"] == "get_weather"
      assert tool["function"]["parameters"]["properties"]["city"]["type"] == "string"
    end

    test "anthropic uses input_schema" do
      parent = self()

      run(
        [provider: :anthropic, tools: [@weather_tool]],
        :tools_anthropic,
        echo_body(parent, %{"content" => [%{"type" => "text", "text" => "ok"}]})
      )

      assert_received {:body, %{"tools" => [tool]}}
      assert tool["name"] == "get_weather"
      assert tool["input_schema"]["type"] == "object"
    end

    test "gemini nests them under functionDeclarations" do
      parent = self()

      run(
        [provider: :gemini, tools: [@weather_tool]],
        :tools_gemini,
        echo_body(parent, %{
          "candidates" => [%{"content" => %{"parts" => [%{"text" => "ok"}]}}]
        })
      )

      assert_received {:body, %{"tools" => [%{"functionDeclarations" => [tool]}]}}
      assert tool["name"] == "get_weather"
    end

    test "a tool without a name is refused before any request" do
      assert_raise Sanad.InvalidConfigError, ~r/needs a :name/, fn ->
        run([tools: [%{description: "nameless"}]], :tools_bad, fn conn ->
          Req.Test.json(conn, %{})
        end)
      end
    end
  end

  describe "tool calls in the response" do
    test "openai arguments are decoded from their JSON string" do
      out =
        run([tools: [@weather_tool]], :calls_openai, fn conn ->
          Req.Test.json(conn, %{
            "choices" => [
              %{
                "message" => %{
                  "content" => nil,
                  "tool_calls" => [
                    %{
                      "id" => "call_1",
                      "function" => %{
                        "name" => "get_weather",
                        "arguments" => ~s({"city":"Bandung"})
                      }
                    }
                  ]
                }
              }
            ]
          })
        end)

      assert out.response == ""

      assert [%{id: "call_1", name: "get_weather", arguments: %{"city" => "Bandung"}}] =
               out.tool_calls
    end

    test "anthropic tool_use blocks come through alongside text" do
      out =
        run([provider: :anthropic, tools: [@weather_tool]], :calls_anthropic, fn conn ->
          Req.Test.json(conn, %{
            "content" => [
              %{"type" => "text", "text" => "checking"},
              %{
                "type" => "tool_use",
                "id" => "toolu_1",
                "name" => "get_weather",
                "input" => %{"city" => "Bandung"}
              }
            ]
          })
        end)

      assert out.response == "checking"

      assert [%{id: "toolu_1", name: "get_weather", arguments: %{"city" => "Bandung"}}] =
               out.tool_calls
    end

    test "gemini function calls come through" do
      out =
        run([provider: :gemini, tools: [@weather_tool]], :calls_gemini, fn conn ->
          Req.Test.json(conn, %{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{"functionCall" => %{"name" => "get_weather", "args" => %{"city" => "Solo"}}}
                  ]
                }
              }
            ]
          })
        end)

      assert out.response == ""
      assert [%{name: "get_weather", arguments: %{"city" => "Solo"}}] = out.tool_calls
    end

    test "a response with neither text nor tool calls is an error" do
      assert_raise Sanad.ChatError, ~r/neither text nor tool calls/, fn ->
        run([], :calls_empty, fn conn ->
          Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => nil}}]})
        end)
      end
    end

    test "tool arguments that are not a JSON object are an error" do
      assert_raise Sanad.ChatError, ~r/not a JSON object/, fn ->
        run([], :calls_malformed, fn conn ->
          Req.Test.json(conn, %{
            "choices" => [
              %{
                "message" => %{
                  "content" => nil,
                  "tool_calls" => [
                    %{"id" => "c", "function" => %{"name" => "f", "arguments" => "not json"}}
                  ]
                }
              }
            ]
          })
        end)
      end
    end
  end
end
