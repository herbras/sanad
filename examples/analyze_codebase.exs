defmodule AnalyzeCodebase do
  use RoastEx.DSL

  config do
    %{
      chat: %{provider: :openai, model: "gpt-4o-mini"},
      agent: %{provider: :pi}
    }
  end

  execute do
    cmd(:recent_changes, "git diff --name-only HEAD~5..HEAD")

    agent :review do
      files = cmd!(ctx, :recent_changes).stdout

      """
      Review these recently changed files for potential issues:
      #{files}

      Focus on security, performance, and maintainability.
      """
    end

    chat :summary do
      "Summarize this for non-technical stakeholders:\n\n#{agent!(ctx, :review).response}"
    end
  end
end
