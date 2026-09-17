defmodule RoastEx.Cogs.Chat do
  @moduledoc """
  Cloud LLM cog. Supports :openai, :anthropic, :gemini via HTTP.

  API keys (env fallback): OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY.
  Base URLs (env fallback): OPENAI_API_BASE, ANTHROPIC_API_BASE, GEMINI_API_BASE.

  Any OpenAI-compatible endpoint works via :openai + `base_url`, e.g.
  OpenRouter (`https://openrouter.ai/api/v1`) or Cloudflare Workers AI
  (`https://api.cloudflare.com/client/v4/accounts/<id>/ai/v1`).

  Per-workflow overrides in config (so OpenRouter and CF can coexist):

      config do
        %{chat: %{provider: :openai, model: "deepseek/deepseek-v4-flash",
                 base_url: "https://openrouter.ai/api/v1", key_env: "OPENROUTER_API_KEY"}}
      end

  Supported override keys: `:base_url`, `:api_key` (literal), `:key_env`
  (name of the env var holding the key).
  """

  alias RoastEx.Output.Chat

  def run(prompt, opts, ctx) when is_binary(prompt) do
    chat_cfg = Map.get(ctx.config, :chat, %{})
    provider = Keyword.get(opts, :provider) || Map.get(chat_cfg, :provider, default_provider())
    model = Keyword.get(opts, :model) || Map.get(chat_cfg, :model) || default_model(provider)

    body = request(provider, model, prompt, chat_cfg, opts)
    %Chat{response: body, model: model, provider: provider, raw: %{}}
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "chat expects a prompt string, got: #{inspect(other)}"
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

  defp request(:openai, model, prompt, cfg, opts) do
    key = api_key(cfg, opts, :openai)
    base = base_url(cfg, opts, "OPENAI_API_BASE", "https://api.openai.com/v1")

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

  defp request(:anthropic, model, prompt, cfg, opts) do
    key = api_key(cfg, opts, :anthropic)
    base = base_url(cfg, opts, "ANTHROPIC_API_BASE", "https://api.anthropic.com")

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

  defp request(:gemini, model, prompt, cfg, opts) do
    key = api_key(cfg, opts, :gemini)

    base =
      base_url(cfg, opts, "GEMINI_API_BASE", "https://generativelanguage.googleapis.com/v1beta")

    url = "#{base}/models/#{model}:generateContent?key=#{key}"

    {:ok, resp} =
      Req.post(url,
        json: %{contents: [%{parts: [%{text: prompt}]}]}
      )

    get_in(resp.body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) ||
      inspect(resp.body)
  end

  defp request(other, _model, _prompt, _cfg, _opts) do
    raise "Unsupported chat provider: #{inspect(other)}"
  end

  defp api_key(cfg, opts, provider) do
    cond do
      k = Keyword.get(opts, :api_key) -> k
      k = Map.get(cfg, :api_key) -> k
      env = Keyword.get(opts, :key_env) || Map.get(cfg, :key_env) -> System.fetch_env!(env)
      true -> System.fetch_env!("#{provider |> Atom.to_string() |> String.upcase()}_API_KEY")
    end
  end

  defp base_url(cfg, opts, env_var, default) do
    Keyword.get(opts, :base_url) || Map.get(cfg, :base_url) ||
      System.get_env(env_var) || default
  end
end
