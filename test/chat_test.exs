defmodule Sanad.Cogs.ChatTest do
  use ExUnit.Case, async: false

  alias Sanad.Context

  @env_vars ~w(
    OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY PERPLEXITY_API_KEY
    OPENROUTER_TEST_KEY OPENAI_API_BASE
  )

  setup do
    System.put_env("OPENAI_API_KEY", "openai-test-key")
    System.put_env("ANTHROPIC_API_KEY", "anthropic-test-key")
    System.put_env("GEMINI_API_KEY", "gemini-test-key")
    System.put_env("PERPLEXITY_API_KEY", "perplexity-test-key")

    on_exit(fn -> Enum.each(@env_vars, &System.delete_env/1) end)
  end

  defp run_chat(prompt, opts, config \\ %{}) do
    Sanad.Cogs.Chat.run(prompt, opts, %Context{config: Sanad.Config.normalize(config)})
  end

  test "openai returns text" do
    Req.Test.stub(:openai, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "hi from openai"}}]})
    end)

    out = run_chat("hi", provider: :openai, req_options: [plug: {Req.Test, :openai}])

    assert out.response == "hi from openai"
    assert out.provider == :openai
    assert out.model == "gpt-4o-mini"
  end

  test "anthropic returns text" do
    Req.Test.stub(:anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => "hi from claude"}]
      })
    end)

    out = run_chat("hi", provider: :anthropic, req_options: [plug: {Req.Test, :anthropic}])

    assert out.response == "hi from claude"
    assert out.model == "claude-haiku-4-5"
  end

  test "gemini returns text" do
    Req.Test.stub(:gemini, fn conn ->
      Req.Test.json(conn, %{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => "hi from gemini"}]}}]
      })
    end)

    out = run_chat("hi", provider: :gemini, req_options: [plug: {Req.Test, :gemini}])

    assert out.response == "hi from gemini"
  end

  test "perplexity returns text" do
    Req.Test.stub(:perplexity, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "hi from sonar"}}]})
    end)

    out = run_chat("hi", provider: :perplexity, req_options: [plug: {Req.Test, :perplexity}])

    assert out.response == "hi from sonar"
    assert out.model == "sonar"
  end

  test "config base_url, key_env and model override env vars" do
    System.put_env("OPENROUTER_TEST_KEY", "or-key")
    parent = self()

    Req.Test.stub(:openrouter, fn conn ->
      send(
        parent,
        {:request, conn.host, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
    end)

    config = %{
      chat: %{
        base_url: "https://openrouter.ai/api/v1",
        key_env: "OPENROUTER_TEST_KEY",
        model: "vendor/model"
      }
    }

    out =
      run_chat("hi", [provider: :openai, req_options: [plug: {Req.Test, :openrouter}]], config)

    assert_received {:request, "openrouter.ai", "/api/v1/chat/completions", ["Bearer or-key"]}
    assert out.model == "vendor/model"
    assert out.response == "ok"
  end

  test "system prompt, temperature and max_tokens are sent" do
    parent = self()

    Req.Test.stub(:params, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(body)})
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
    end)

    run_chat("hi",
      provider: :openai,
      system_prompt: "be terse",
      temperature: 0.5,
      max_tokens: 64,
      req_options: [plug: {Req.Test, :params}]
    )

    assert_received {:body, body}
    assert body["temperature"] == 0.5
    assert body["max_tokens"] == 64
    assert [%{"role" => "system", "content" => "be terse"} | _] = body["messages"]
  end

  test "missing api key raises an actionable error" do
    System.delete_env("OPENAI_API_KEY")

    assert_raise Sanad.MissingEnvError, ~r/OPENAI_API_KEY/, fn ->
      run_chat("hi", provider: :openai)
    end
  end

  test "http error raises ChatError with status" do
    Req.Test.stub(:err, fn conn ->
      Plug.Conn.send_resp(conn, 401, ~s({"error":"bad key"}))
    end)

    assert_raise Sanad.ChatError, ~r/HTTP 401/, fn ->
      run_chat("hi", provider: :openai, req_options: [plug: {Req.Test, :err}])
    end
  end

  test "transport error raises ChatError without long retries" do
    Req.Test.stub(:tx, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert_raise Sanad.ChatError, ~r/econnrefused/, fn ->
      run_chat("hi", provider: :openai, max_retries: 0, req_options: [plug: {Req.Test, :tx}])
    end
  end

  test "unknown provider raises InvalidConfigError" do
    assert_raise Sanad.InvalidConfigError, ~r/provider/, fn ->
      run_chat("hi", provider: :bogus)
    end
  end
end
