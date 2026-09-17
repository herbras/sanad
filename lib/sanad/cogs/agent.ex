defmodule Sanad.Cogs.Agent do
  @moduledoc """
  Local coding-agent cog, mirroring Roast's `agent` cog.

  Invokes a provider CLI and returns its response as `%Sanad.Output.Agent{}`:

  * `:pi` (default) runs `pi --mode json -p [--model M] [--system-prompt S]
    [--append-system-prompt S] (--fork SESSION | --no-session)`. The prompt goes
    on stdin and stdout is the line-delimited JSON protocol v3.
  * `:claude` runs `claude -p --verbose --output-format stream-json [--model M]
    [--system-prompt S] [--append-system-prompt S] [--resume SESSION]
    [--dangerously-skip-permissions]`. The prompt goes on stdin.
  * `:opencode` runs `opencode run <prompt>` with the prompt as an argument.
  * `:agy` runs `agy -p <prompt>` with the prompt as an argument.

  Options come from step opts first, then workflow config (`agent:` block).

  Options:

  * `:provider` is one of the providers above. It falls back to workflow config,
    then `SANAD_DEFAULT_AGENT_PROVIDER` (default `:pi`).
  * `:model`, `:system_prompt`, `:append_system_prompt` (pi/claude)
  * `:command` is a String or list overriding the base binary/argv prefix,
    useful for wrappers such as `pi -ne` or a stub in tests.
  * `:session` forks or resumes a provider session (pi/claude).
  * `:fork_session` adds `--fork-session` for claude when a session is set
    (default `true`).
  * `:skip_permissions` is Claude only and adds `--dangerously-skip-permissions`.
  * `:cwd` defaults to `ctx.workflow_dir`.
  * `:env`, `:timeout`
  """

  alias Sanad.Context
  alias Sanad.Output.Agent

  @providers [:pi, :claude, :opencode, :agy]

  def run(prompt, opts, ctx) when is_binary(prompt) do
    opts = Keyword.merge(agent_config(ctx), opts)
    provider = provider(opts)
    [binary | base_args] = command(provider, opts)
    {args, input} = invocation(provider, base_args, prompt, opts)
    validate_executable!(binary, provider)

    command_opts = [
      input: input,
      cwd: Keyword.get(opts, :cwd, ctx.workflow_dir),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, :infinity)
    ]

    case Sanad.Command.run([binary | args], command_opts) do
      {:ok, stdout, stderr, 0} ->
        %Agent{
          response: parse_response(provider, stdout),
          provider: provider,
          raw: %{status: 0, session: session_id(provider, stdout), stderr: stderr}
        }

      {:ok, stdout, stderr, status} ->
        raise Sanad.AgentError,
          provider: provider,
          reason: "exited with status #{status}: #{String.trim(stderr <> "\n" <> stdout)}"

      {:timeout, partial, stderr} ->
        raise Sanad.AgentError,
          provider: provider,
          reason:
            "timed out after #{inspect(Keyword.get(opts, :timeout))}ms " <>
              "(partial output: #{inspect(partial <> stderr)})"
    end
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "agent expects a prompt string, got: #{inspect(other)}"
  end

  defp provider(opts) do
    provider = Keyword.get(opts, :provider) || default_provider()

    if provider in @providers do
      provider
    else
      raise Sanad.InvalidConfigError,
        message: "agent provider must be one of #{inspect(@providers)}, got: #{inspect(provider)}"
    end
  end

  defp default_provider do
    case normalize_provider(System.get_env("SANAD_DEFAULT_AGENT_PROVIDER")) do
      nil ->
        :pi

      "pi" ->
        :pi

      "claude" ->
        :claude

      "opencode" ->
        :opencode

      "agy" ->
        :agy

      other ->
        raise Sanad.InvalidConfigError,
          message:
            "invalid SANAD_DEFAULT_AGENT_PROVIDER: #{inspect(other)} " <>
              "(expected pi | claude | opencode | agy)"
    end
  end

  defp normalize_provider(nil), do: nil

  defp normalize_provider(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp command(provider, opts) do
    case Keyword.get(opts, :command) do
      nil ->
        default_command(provider)

      command when is_binary(command) ->
        String.split(command)

      command when is_list(command) ->
        Enum.map(command, &to_string/1)

      other ->
        raise Sanad.InvalidConfigError,
          message: "agent :command must be a string or list, got: #{inspect(other)}"
    end
  end

  defp default_command(:pi), do: ["pi"]
  defp default_command(:claude), do: ["claude"]
  defp default_command(:opencode), do: ["opencode"]
  defp default_command(:agy), do: ["agy"]

  defp invocation(provider, base_args, prompt, opts) do
    case provider do
      :pi ->
        {base_args ++ pi_args(opts), prompt}

      :claude ->
        {base_args ++ claude_args(opts), prompt}

      provider when provider in [:opencode, :agy] ->
        {base_args ++ prompt_args(provider, prompt), nil}
    end
  end

  defp prompt_args(:opencode, prompt), do: ["run", prompt]
  defp prompt_args(:agy, prompt), do: ["-p", prompt]

  defp pi_args(opts) do
    args = ["--mode", "json", "-p"]
    args = args ++ flag("--model", model(opts))
    args = args ++ flag("--system-prompt", Keyword.get(opts, :system_prompt))
    args = args ++ flag("--append-system-prompt", Keyword.get(opts, :append_system_prompt))

    case Keyword.get(opts, :session) do
      nil -> args ++ ["--no-session"]
      session -> args ++ ["--fork", session]
    end
  end

  defp claude_args(opts) do
    args = ["-p", "--verbose", "--output-format", "stream-json"]
    args = args ++ flag("--model", strip_anthropic_prefix(model(opts)))
    args = args ++ flag("--system-prompt", Keyword.get(opts, :system_prompt))
    args = args ++ flag("--append-system-prompt", Keyword.get(opts, :append_system_prompt))

    args =
      case Keyword.get(opts, :session) do
        nil ->
          args

        session ->
          args = args ++ ["--resume", session]

          if Keyword.get(opts, :fork_session, true) do
            args ++ ["--fork-session"]
          else
            args
          end
      end

    if Keyword.get(opts, :skip_permissions, false) do
      args ++ ["--dangerously-skip-permissions"]
    else
      args
    end
  end

  defp model(opts), do: Keyword.get(opts, :model)

  defp strip_anthropic_prefix(nil), do: nil

  defp strip_anthropic_prefix(model),
    do: String.replace_prefix(to_string(model), "anthropic/", "")

  defp flag(_name, nil), do: []
  defp flag(name, value), do: [name, to_string(value)]

  defp validate_executable!(binary, provider) do
    if System.find_executable(binary) == nil do
      raise Sanad.MissingExecutableError,
        name: binary,
        hint:
          "agent provider #{inspect(provider)} requires the `#{binary}` CLI on PATH " <>
            "(or pass :command with an explicit path)"
    end
  end

  # --- response parsing -----------------------------------------------------

  defp parse_response(provider, stdout) when provider in [:opencode, :agy], do: stdout

  defp parse_response(:pi, stdout) do
    events = decode_lines(stdout)
    from_agent_end = pi_agent_end_text(events)
    deltas = pi_deltas(events)

    cond do
      is_binary(from_agent_end) and from_agent_end != "" -> from_agent_end
      deltas != "" -> deltas
      true -> stdout
    end
  end

  defp parse_response(:claude, stdout) do
    result =
      stdout
      |> decode_lines()
      |> Enum.reduce(nil, fn
        %{"type" => "result", "is_error" => true} = event, _acc ->
          raise Sanad.AgentError,
            provider: :claude,
            reason: "claude reported an error: #{inspect(event["result"])}"

        %{"type" => "result", "result" => result}, _acc when is_binary(result) ->
          result

        %{"type" => "assistant", "message" => %{"content" => content}}, acc
        when is_list(content) ->
          text = Enum.map_join(content, "", &(&1["text"] || ""))
          if text == "", do: acc, else: text

        _event, acc ->
          acc
      end)

    result || stdout
  end

  defp pi_agent_end_text(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "agent_end", "messages" => messages} when is_list(messages) ->
        messages
        |> Enum.reverse()
        |> Enum.find_value(fn
          %{"role" => "assistant"} = message -> assistant_text(message)
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  defp pi_deltas(events) do
    events
    |> Enum.reduce([], fn
      %{
        "type" => "message_update",
        "assistantMessageEvent" => %{"type" => "text_delta", "delta" => delta}
      },
      acc ->
        [acc, delta]

      _event, acc ->
        acc
    end)
    |> IO.iodata_to_binary()
  end

  defp assistant_text(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
  end

  defp assistant_text(_message), do: nil

  defp session_id(:pi, stdout) do
    stdout
    |> decode_lines()
    |> Enum.find_value(fn
      %{"type" => "session", "id" => id} -> id
      _ -> nil
    end)
  end

  defp session_id(_provider, _stdout), do: nil

  defp decode_lines(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, decoded} when is_map(decoded) -> [decoded]
        _ -> []
      end
    end)
  end

  defp agent_config(%Context{config: config}) do
    config
    |> Map.get(:agent, %{})
    |> Enum.to_list()
  end
end
