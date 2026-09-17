defmodule RoastEx.Cogs.Agent do
  @moduledoc """
  Local coding-agent cog. Shells out to `pi`, `claude`, `opencode`, or `agy`
  CLI, matching Roast.
  """

  alias RoastEx.Output.Agent

  def run(prompt, opts, ctx) when is_binary(prompt) do
    agent_cfg = Map.get(ctx.config, :agent, %{})
    provider = Keyword.get(opts, :provider) || Map.get(agent_cfg, :provider, default_provider())

    {bin, args} =
      case provider do
        :claude -> {"claude", ["-p", prompt]}
        :pi -> {"pi", [prompt]}
        :opencode -> {"opencode", ["run", prompt]}
        :agy -> {"agy", ["-p", prompt]}
        other -> raise "Unsupported agent provider: #{inspect(other)}"
      end

    {stdout, status} = System.cmd(bin, args, stderr_to_stdout: true)

    if status != 0 do
      raise "agent #{provider} exited #{status}: #{stdout}"
    end

    %Agent{response: stdout, provider: provider, raw: %{status: status}}
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "agent expects a prompt string, got: #{inspect(other)}"
  end

  defp default_provider do
    case System.get_env("ROAST_DEFAULT_AGENT_PROVIDER") do
      "claude" -> :claude
      "opencode" -> :opencode
      "agy" -> :agy
      _ -> :pi
    end
  end
end
