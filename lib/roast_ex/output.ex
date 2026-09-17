defmodule RoastEx.Output do
  defmodule Chat do
    defstruct [:response, :model, :provider, raw: %{}]
  end

  defmodule Cmd do
    defstruct stdout: "", stderr: "", status: 0
  end

  defmodule Agent do
    defstruct response: "", provider: :pi, raw: %{}
  end

  defmodule Elixir do
    defstruct [:value]
  end

  defmodule MapResult do
    defstruct items: []
  end
end
