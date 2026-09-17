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
    @moduledoc """
    Output of the map cog.

    `items` holds each iteration's final output (in input order, `nil` for
    iterations that never ran); `contexts` holds the matching child contexts.
    """
    defstruct items: [], contexts: []
  end

  defmodule Call do
    @moduledoc """
    Output of the call cog: the named scope's final output plus the child
    context, for use with `from/2`.
    """
    defstruct [:scope, :index, :value, :context]
  end

  defmodule Repeat do
    @moduledoc """
    Output of the repeat cog: each iteration's final output plus child contexts.
    `value` is the final iteration's output.
    """
    defstruct [:scope, :value, results: [], contexts: []]
  end
end
