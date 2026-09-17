defmodule Sanad.Command do
  @moduledoc false

  # Internal external-command runner used by the cmd and agent cogs.
  #
  # Wraps `Port.open/2` so we get: separate stdout/stderr capture, stdin from a
  # temp file (Erlang ports cannot half-close stdin), cwd/env, and an optional
  # timeout with best-effort process termination.

  @type result :: {:ok, binary(), binary(), integer()} | {:timeout, binary(), binary()}

  @spec run([String.t()], keyword()) :: result()
  def run([binary | args], opts) when is_binary(binary) do
    stdin = Keyword.get(opts, :input)
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, :infinity)

    stdin_path = if is_binary(stdin), do: write_temp(stdin, "stdin"), else: nil
    stderr_path = temp_path("stderr")

    try do
      script =
        "exec \"$0\" \"$@\"" <>
          if(stdin_path, do: " < " <> sh_quote(stdin_path), else: "") <>
          " 2> " <> sh_quote(stderr_path)

      port_opts = [:binary, :exit_status, :hide, args: ["-c", script, binary | args]]

      port_opts = if cwd, do: [{:cd, cwd} | port_opts], else: port_opts
      port_opts = if env != [], do: [{:env, normalize_env(env)} | port_opts], else: port_opts

      port = Port.open({:spawn_executable, System.find_executable("sh")}, port_opts)

      case collect(port, timeout, []) do
        {:ok, stdout, status} -> {:ok, stdout, read_and_rm(stderr_path), status}
        {:timeout, stdout} -> {:timeout, stdout, read_and_rm(stderr_path)}
      end
    after
      if stdin_path, do: File.rm(stdin_path)
    end
  end

  def run([], _opts) do
    raise ArgumentError, "no command provided"
  end

  defp collect(port, timeout, acc) do
    receive do
      {^port, {:data, data}} ->
        collect(port, timeout, [acc, data])

      {^port, {:exit_status, status}} ->
        {:ok, IO.iodata_to_binary(acc), status}
    after
      timeout ->
        terminate(port)
        drain_port(port)
        {:timeout, IO.iodata_to_binary(acc)}
    end
  end

  # A killed port may still deliver `{port, {:exit_status, _}}`; consume any
  # pending port messages so they do not leak into the caller's mailbox.
  defp drain_port(port) do
    receive do
      {^port, _message} -> drain_port(port)
    after
      20 -> :ok
    end
  end

  defp terminate(port) do
    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    if os_pid do
      pid_string = Integer.to_string(os_pid)
      System.cmd("pkill", ["-TERM", "-P", pid_string], stderr_to_stdout: true)
      System.cmd("kill", ["-TERM", pid_string], stderr_to_stdout: true)
      Process.sleep(50)
      System.cmd("kill", ["-KILL", pid_string], stderr_to_stdout: true)
    end

    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp normalize_env(env) when is_map(env), do: merge_env(env)
  defp normalize_env(env) when is_list(env), do: merge_env(Map.new(env))

  # The port `:env` option is layered on top of the inherited environment, so
  # PATH etc. stay available (same spirit as System.cmd).
  defp merge_env(overrides) do
    System.get_env()
    |> Map.merge(Map.new(overrides, fn {key, value} -> {to_string(key), to_string(value)} end))
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp write_temp(contents, label) do
    path = temp_path(label)
    File.write!(path, contents)
    path
  end

  defp temp_path(label) do
    Path.join(System.tmp_dir!(), "sanad_#{label}_#{System.unique_integer([:positive])}")
  end

  defp read_and_rm(path) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, _} -> ""
      end

    File.rm(path)
    contents
  end

  defp sh_quote(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end
end
