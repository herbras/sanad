defmodule Sanad.Output do
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

  defmodule Agent.Usage do
    @moduledoc """
    Token usage for an agent run, and its cost when the provider reports one.

    Fields are `nil` rather than zero when the provider says nothing about
    them, so "not reported" stays distinguishable from "none used".
    """

    defstruct input_tokens: nil,
              output_tokens: nil,
              cache_read_tokens: nil,
              cache_write_tokens: nil,
              cost_usd: nil

    @type t :: %__MODULE__{
            input_tokens: non_neg_integer() | nil,
            output_tokens: non_neg_integer() | nil,
            cache_read_tokens: non_neg_integer() | nil,
            cache_write_tokens: non_neg_integer() | nil,
            cost_usd: float() | nil
          }
  end

  defmodule Agent.Stats do
    @moduledoc """
    What an agent run cost, normalized across providers.

    `usage` is the total; `model_usage` breaks it down by model for providers
    that report per-model figures.
    """

    defstruct num_turns: nil, usage: %Agent.Usage{}, model_usage: %{}

    @type t :: %__MODULE__{
            num_turns: non_neg_integer() | nil,
            usage: Agent.Usage.t(),
            model_usage: %{optional(String.t()) => Agent.Usage.t()}
          }
  end

  defmodule Agent do
    @moduledoc """
    Output of the agent cog.

    `session` is the provider's conversation id when it has one, so a later
    agent step can resume from it. It is `nil` for providers with no session
    concept.
    """

    defstruct response: "",
              provider: :pi,
              session: nil,
              stats: %Agent.Stats{},
              raw: %{}
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
