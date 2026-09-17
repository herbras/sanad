defmodule RoastEx.Output do
  @moduledoc """
  Output structs returned by built-in cogs.
  """

  defmodule Chat do
    @moduledoc "Output of the chat cog."
    defstruct [:response, :model, :provider, raw: %{}]
  end

  defmodule Cmd do
    @moduledoc "Output of the cmd cog."
    defstruct stdout: "", stderr: "", status: 0
  end

  defmodule Agent do
    @moduledoc "Output of the agent cog."
    defstruct response: "", provider: :pi, raw: %{}
  end

  defmodule MapResult do
    @moduledoc "Output of the (transitional) map cog."
    defstruct items: []
  end
end
