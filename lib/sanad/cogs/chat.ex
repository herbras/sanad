defmodule Sanad.Cogs.Chat do
  @moduledoc """
  Cloud LLM cog with OpenAI, Anthropic, Gemini and Perplexity providers.

  ## Providers and credentials

  | provider | default key env | default base URL env |
  |---|---|---|
  | `:openai` | `OPENAI_API_KEY` | `OPENAI_API_BASE` |
  | `:anthropic` | `ANTHROPIC_API_KEY` | `ANTHROPIC_API_BASE` |
  | `:gemini` | `GEMINI_API_KEY` | `GEMINI_API_BASE` |
  | `:perplexity` | `PERPLEXITY_API_KEY` | `PERPLEXITY_API_BASE` |

  Any OpenAI-compatible endpoint works via `:openai` + `:base_url`, e.g.
  OpenRouter (`https://openrouter.ai/api/v1`) or Cloudflare Workers AI.
  Per-workflow overrides (config) let endpoints coexist:

      config do
        %{chat: %{provider: :openai, model: "deepseek/deepseek-v4-flash",
                 base_url: "https://openrouter.ai/api/v1", key_env: "OPENROUTER_API_KEY"}}
      end

  Resolution order: step opts › workflow config › env vars.

  ## Options

  * `:provider` defaults to `SANAD_DEFAULT_CHAT_PROVIDER` or `:openai`.
  * `:model`
  * `:system_prompt`, `:temperature`, `:max_tokens`
  * `:api_key` (literal), `:key_env` (env var name), `:base_url`
  * `:timeout` is the request receive timeout in ms (default `60_000`).
  * `:max_retries` defaults to 3. POST requests are retried with
    `retry: :transient`.
  * `:req_options` passes extra `Req` options, e.g. `plug: {Req.Test, Name}` in tests.

  Failures raise `Sanad.ChatError`; missing keys raise
  `Sanad.MissingEnvError`; invalid providers `Sanad.InvalidConfigError`.
  """

  alias Sanad.Config
  alias Sanad.Events
  alias Sanad.Output.Chat

  @providers [:openai, :anthropic, :gemini, :perplexity]

  def run(prompt, opts, ctx) when is_binary(prompt) do
    cfg = Map.get(ctx.config, :chat, %{})
    provider = provider(opts, cfg)

    model =
      (Keyword.get(opts, :model) || Map.get(cfg, :model) || default_model(provider))
      |> expand_model()

    request = build_request(provider, model, prompt, opts, cfg)

    options =
      [
        headers: request.headers,
        json: request.body,
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 3),
        receive_timeout: Keyword.get(opts, :timeout, 60_000)
      ] ++ Keyword.get(opts, :req_options, [])

    Events.block(ctx, "prompt", prompt)

    case Req.post(request.url, options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        response = extract_text(provider, body)
        Events.block(ctx, "response", response)
        %Chat{response: response, model: model, provider: provider, raw: body}

      {:ok, %{status: status, body: body}} ->
        raise Sanad.ChatError, provider: provider, status: status, body: body

      {:error, reason} ->
        raise Sanad.ChatError, provider: provider, reason: reason
    end
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "chat expects a prompt string, got: #{inspect(other)}"
  end

  defp provider(opts, cfg) do
    provider =
      (Keyword.get(opts, :provider) || Map.get(cfg, :provider) || default_provider())
      |> alias_provider()

    if provider in @providers do
      provider
    else
      raise Sanad.InvalidConfigError,
        message: "chat provider must be one of #{inspect(@providers)}, got: #{inspect(provider)}"
    end
  end

  # `:claude` is what people call the models; Anthropic is what the API is
  # called. Accept both.
  defp alias_provider(:claude), do: :anthropic
  defp alias_provider(other), do: other

  defp default_provider do
    case normalize_provider(System.get_env("SANAD_DEFAULT_CHAT_PROVIDER")) do
      nil ->
        :openai

      "openai" ->
        :openai

      provider when provider in ["anthropic", "claude"] ->
        :anthropic

      "gemini" ->
        :gemini

      "perplexity" ->
        :perplexity

      other ->
        raise Sanad.InvalidConfigError,
          message:
            "invalid SANAD_DEFAULT_CHAT_PROVIDER: #{inspect(other)} " <>
              "(expected openai | anthropic | claude | gemini | perplexity)"
    end
  end

  defp normalize_provider(nil), do: nil

  defp normalize_provider(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  # Short names for the current Claude models, so workflows do not carry long
  # version strings around.
  @model_aliases %{
    opus: "claude-opus-5",
    sonnet: "claude-sonnet-5",
    haiku: "claude-haiku-4-5",
    fable: "claude-fable-5-1"
  }

  @doc "Model aliases accepted by `:model`, e.g. `model: :opus`."
  @spec model_aliases() :: %{atom() => String.t()}
  def model_aliases, do: @model_aliases

  defp expand_model(model) when is_atom(model) do
    case Map.fetch(@model_aliases, model) do
      {:ok, expanded} ->
        expanded

      :error ->
        raise Sanad.InvalidConfigError,
          message:
            "unknown model alias #{inspect(model)}, " <>
              "expected one of #{inspect(Map.keys(@model_aliases))} or a model string"
    end
  end

  defp expand_model(model), do: model

  defp default_model(:openai), do: "gpt-4o-mini"
  defp default_model(:anthropic), do: "claude-haiku-4-5"
  defp default_model(:gemini), do: "gemini-3.1-flash-lite"
  defp default_model(:perplexity), do: "sonar"

  # --- per-provider request building ---------------------------------------

  defp build_request(provider, model, prompt, opts, cfg)
       when provider in [:openai, :perplexity] do
    key = api_key(opts, cfg, provider)
    base = base_url(opts, cfg, provider)

    %{
      url: base <> "/chat/completions",
      headers: [{"authorization", "Bearer " <> key}],
      body:
        %{model: model, messages: openai_messages(prompt, opts, cfg)}
        |> put_if_present(:temperature, param(opts, cfg, :temperature))
        |> put_if_present(:max_tokens, param(opts, cfg, :max_tokens))
    }
  end

  defp build_request(:anthropic, model, prompt, opts, cfg) do
    key = api_key(opts, cfg, :anthropic)
    base = base_url(opts, cfg, :anthropic)

    %{
      url: base <> "/v1/messages",
      headers: [{"x-api-key", key}, {"anthropic-version", "2023-06-01"}],
      body:
        %{
          model: model,
          max_tokens: param(opts, cfg, :max_tokens) || 4096,
          messages: [%{role: "user", content: prompt}]
        }
        |> put_if_present(:temperature, param(opts, cfg, :temperature))
        |> put_if_present(:system, system_prompt(opts, cfg))
    }
  end

  defp build_request(:gemini, model, prompt, opts, cfg) do
    key = api_key(opts, cfg, :gemini)
    base = base_url(opts, cfg, :gemini)

    generation_config =
      %{}
      |> put_if_present(:temperature, param(opts, cfg, :temperature))
      |> put_if_present(:maxOutputTokens, param(opts, cfg, :max_tokens))

    body =
      %{contents: [%{parts: [%{text: prompt}]}]}
      |> put_if_present(
        :generationConfig,
        if(generation_config == %{}, do: nil, else: generation_config)
      )
      |> put_if_present(:systemInstruction, gemini_system_instruction(opts, cfg))

    %{
      url: base <> "/models/#{model}:generateContent",
      headers: [{"x-goog-api-key", key}],
      body: body
    }
  end

  defp api_key(opts, cfg, provider) do
    hint = "set #{default_key_env(provider)} or configure chat :key_env / :api_key"

    cond do
      key = Keyword.get(opts, :api_key) -> key
      key = Map.get(cfg, :api_key) -> key
      env = Keyword.get(opts, :key_env) || Map.get(cfg, :key_env) -> Config.fetch_env!(env, hint)
      true -> Config.fetch_env!(default_key_env(provider), hint)
    end
  end

  defp default_key_env(:openai), do: "OPENAI_API_KEY"
  defp default_key_env(:anthropic), do: "ANTHROPIC_API_KEY"
  defp default_key_env(:gemini), do: "GEMINI_API_KEY"
  defp default_key_env(:perplexity), do: "PERPLEXITY_API_KEY"

  defp base_url(opts, cfg, provider) do
    {env_var, default} = default_base_url(provider)

    (Keyword.get(opts, :base_url) || Map.get(cfg, :base_url) ||
       System.get_env(env_var) || default)
    |> String.trim_trailing("/")
  end

  defp default_base_url(:openai), do: {"OPENAI_API_BASE", "https://api.openai.com/v1"}
  defp default_base_url(:anthropic), do: {"ANTHROPIC_API_BASE", "https://api.anthropic.com"}
  defp default_base_url(:perplexity), do: {"PERPLEXITY_API_BASE", "https://api.perplexity.ai"}

  defp default_base_url(:gemini),
    do: {"GEMINI_API_BASE", "https://generativelanguage.googleapis.com/v1beta"}

  defp openai_messages(prompt, opts, cfg) do
    case system_prompt(opts, cfg) do
      nil -> [%{role: "user", content: prompt}]
      system -> [%{role: "system", content: system}, %{role: "user", content: prompt}]
    end
  end

  defp gemini_system_instruction(opts, cfg) do
    case system_prompt(opts, cfg) do
      nil -> nil
      system -> %{parts: [%{text: system}]}
    end
  end

  defp system_prompt(opts, cfg) do
    Keyword.get(opts, :system_prompt) || Map.get(cfg, :system_prompt)
  end

  defp param(opts, cfg, key) do
    Keyword.get(opts, key) || Map.get(cfg, key)
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  # --- response extraction --------------------------------------------------

  defp extract_text(provider, %{"choices" => [%{"message" => %{"content" => content}} | _]})
       when provider in [:openai, :perplexity] and is_binary(content),
       do: content

  defp extract_text(:anthropic, %{"content" => content}) when is_list(content) do
    case Enum.find_value(content, fn
           %{"type" => "text", "text" => text} when is_binary(text) -> text
           _ -> nil
         end) do
      nil ->
        raise Sanad.ChatError,
          provider: :anthropic,
          reason: "no text block in response: #{inspect(content)}"

      text ->
        text
    end
  end

  defp extract_text(:gemini, %{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       })
       when is_binary(text),
       do: text

  defp extract_text(provider, body) do
    raise Sanad.ChatError,
      provider: provider,
      reason: "could not extract text from response: #{inspect(body)}"
  end
end
