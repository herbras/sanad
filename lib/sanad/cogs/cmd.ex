defmodule Sanad.Cogs.Cmd do
  @moduledoc """
  Runs a shell command (`sh -c`), mirroring Roast's `cmd` cog.

  stdout, stderr and the exit status are captured separately. When
  `fail_on_error` is true (the default), a non-zero exit calls `fail!/1`, which
  aborts the workflow unless `abort_on_failure` is disabled.

  Options: `:cwd`, `:env`, `:fail_on_error`, `:timeout` (ms; exceeding it
  raises `Sanad.CommandTimeoutError`).
  """

  alias Sanad.Output.Cmd

  def run(command, opts, _ctx) when is_binary(command) do
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, :infinity)
    fail_on_error? = Keyword.get(opts, :fail_on_error, true)

    case Sanad.Command.run(["sh", "-c", command], cwd: cwd, env: env, timeout: timeout) do
      {:ok, stdout, stderr, status} ->
        if status != 0 and fail_on_error? do
          Sanad.ControlFlow.fail!("command exited with status #{status}: #{command}")
        end

        %Cmd{stdout: stdout, stderr: stderr, status: status}

      {:timeout, stdout, stderr} ->
        raise Sanad.CommandTimeoutError,
          command: command,
          timeout: timeout,
          stdout: stdout,
          stderr: stderr
    end
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "cmd expects a shell command string, got: #{inspect(other)}"
  end
end
