defmodule RoastEx.Cogs.Chat do
  @moduledoc """
  Cloud LLM cog. Supports :openai, :anthropic, :gemini via HTTP.

  API keys:
    OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY
  """

  alias RoastEx.Output.Chat

  def run(prompt, opts, config) when is_binary(prompt) do
    chat_cfg = Map.get(config, :chat, %{})
    provider = Keyword.get(opts, :provider) || Map.get(chat_cfg, :provider, default_provider())
    model = Keyword.get(opts, :model) || Map.get(chat_cfg, :model) || default_model(provider)

    body = request(provider, model, prompt)
    %Chat{response: body, model: model, provider: provider, raw: %{}}
  end

  defp default_provider do
    case System.get_env("ROAST_DEFAULT_CHAT_PROVIDER") do
      "anthropic" -> :anthropic
      "gemini" -> :gemini
      _ -> :openai
    end
  end

  defp default_model(:openai), do: "gpt-4o-mini"
  defp default_model(:anthropic), do: "claude-haiku-4-5"
  defp default_model(:gemini), do: "gemini-2.0-flash"
  defp default_model(_), do: "gpt-4o-mini"

  defp request(:openai, model, prompt) do
    key = System.fetch_env!("OPENAI_API_KEY")
    base = System.get_env("OPENAI_API_BASE") || "https://api.openai.com/v1"

    {:ok, resp} =
      Req.post(base <> "/chat/completions",
        auth: {:bearer, key},
        json: %{
          model: model,
          messages: [%{role: "user", content: prompt}]
        }
      )

    get_in(resp.body, ["choices", Access.at(0), "message", "content"]) || inspect(resp.body)
  end

  defp request(:anthropic, model, prompt) do
    key = System.fetch_env!("ANTHROPIC_API_KEY")
    base = System.get_env("ANTHROPIC_API_BASE") || "https://api.anthropic.com"

    {:ok, resp} =
      Req.post(base <> "/v1/messages",
        headers: [
          {"x-api-key", key},
          {"anthropic-version", "2023-06-01"}
        ],
        json: %{
          model: model,
          max_tokens: 2048,
          messages: [%{role: "user", content: prompt}]
        }
      )

    case get_in(resp.body, ["content", Access.at(0), "text"]) do
      nil -> inspect(resp.body)
      text -> text
    end
  end

  defp request(:gemini, model, prompt) do
    key = System.fetch_env!("GEMINI_API_KEY")
    base = System.get_env("GEMINI_API_BASE") || "https://generativelanguage.googleapis.com/v1beta"
    url = "#{base}/models/#{model}:generateContent?key=#{key}"

    {:ok, resp} =
      Req.post(url,
        json: %{contents: [%{parts: [%{text: prompt}]}]}
      )

    get_in(resp.body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) ||
      inspect(resp.body)
  end

  defp request(other, _model, _prompt) do
    raise "Unsupported chat provider: #{inspect(other)}"
  end
end
