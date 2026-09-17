defmodule RoastEx.Cogs.Cmd do
  @moduledoc """
  Runs a shell command (`sh -c`), mirroring Roast's `cmd` cog.

  stdout, stderr and the exit status are captured separately. When
  `fail_on_error` is true (the default), a non-zero exit calls `fail!/1`, which
  aborts the workflow unless `abort_on_failure` is disabled.

  Options: `:cwd`, `:env`, `:fail_on_error`.
  """

  alias RoastEx.Output.Cmd

  def run(command, opts, _ctx) when is_binary(command) do
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, %{})
    fail_on_error? = Keyword.get(opts, :fail_on_error, true)

    {stdout, stderr, status} = exec(command, cwd, env)

    if status != 0 and fail_on_error? do
      RoastEx.ControlFlow.fail!("command exited with status #{status}: #{command}")
    end

    %Cmd{stdout: stdout, stderr: stderr, status: status}
  end

  def run(other, _opts, _ctx) do
    raise ArgumentError, "cmd expects a shell command string, got: #{inspect(other)}"
  end

  defp exec(command, cwd, env) do
    stderr_path = tmp_path()
    shell_command = "(#{command}) 2>#{shell_quote(stderr_path)}"

    opts =
      []
      |> maybe_put(:cd, cwd)
      |> maybe_put(:env, normalize_env(env))

    try do
      {stdout, status} = System.cmd("sh", ["-c", shell_command], opts)
      {stdout, read_stderr(stderr_path), status}
    rescue
      exception ->
        File.rm(stderr_path)
        reraise exception, __STACKTRACE__
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, value) when value in [%{}, []], do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_env(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp tmp_path do
    Path.join(System.tmp_dir!(), "roast_ex_stderr_#{System.unique_integer([:positive])}")
  end

  defp shell_quote(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end

  defp read_stderr(path) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, _reason} -> ""
      end

    File.rm(path)
    contents
  end
end
