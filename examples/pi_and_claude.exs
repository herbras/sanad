defmodule PiAndClaude do
  @moduledoc """
  Reviews the working tree with the `pi` agent, then has Claude turn each
  review into a one-line verdict.

  Needs the `pi` binary on PATH and ANTHROPIC_API_KEY set:

      mix sanad.execute examples/pi_and_claude.exs
  """

  use Sanad.DSL

  config do
    global(abort_on_failure: true)
    agent(provider: :pi)
    chat(provider: :claude, model: :sonnet)
    chat(:verdict, model: :opus)
  end

  execute :one_file do
    agent :review do
      """
      Review #{ctx.scope_value} for correctness and clarity.
      Answer in at most five bullet points.
      """
    end

    chat :verdict do
      """
      Turn this review into a single line: SHIP or FIX, then why, in under 20 words.

      #{agent!(ctx, :review).response}
      """
    end

    outputs do
      %{file: ctx.scope_value, verdict: chat!(ctx, :verdict).response}
    end
  end

  execute do
    cmd(:changed, "git diff --name-only HEAD~1..HEAD -- '*.ex' '*.exs'")

    map_cog :reviews, scope: :one_file, parallel: 2 do
      cmd!(ctx, :changed).stdout |> String.split("\n", trim: true) |> Enum.take(3)
    end

    elixir_cog :report do
      collect(output!(ctx, :reviews))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("\n", fn %{file: file, verdict: verdict} -> "#{file}: #{verdict}" end)
    end
  end
end
