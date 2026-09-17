defmodule RoastEx.Cogs.Cmd do
  alias RoastEx.Output.Cmd

  def run(command, _opts \\ []) when is_binary(command) do
    {stdout, status} = System.cmd("sh", ["-c", command], stderr_to_stdout: true)
    %Cmd{stdout: stdout, stderr: "", status: status}
  end
end
