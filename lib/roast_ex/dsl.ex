defmodule RoastEx.DSL do
  @moduledoc """
  Macro DSL approximating Roast's Ruby `execute` / cog syntax.

      defmodule AnalyzeCodebase do
        use RoastEx.DSL

        config do
          chat provider: :openai, model: "gpt-4o-mini"
        end

        execute do
          cmd :recent_changes, "git diff --name-only HEAD~5..HEAD"

          agent :review do
            files = cmd!(:recent_changes).stdout
            \"\"\"
            Review these files:
            \#{files}
            \"\"\"
          end

          chat :summary do
            "Summarize for stakeholders:\\n\\n\#{agent!(:review).response}"
          end
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import RoastEx.DSL
      import RoastEx.Helpers
      Module.register_attribute(__MODULE__, :roast_steps, accumulate: true)
      Module.register_attribute(__MODULE__, :roast_config, accumulate: false)
      @roast_config %{}
      @before_compile RoastEx.DSL
    end
  end

  defmacro config(do: block) do
    quote do
      @roast_config unquote(block) |> RoastEx.DSL.__normalize_config__()
    end
  end

  defmacro execute(do: block) do
    quote do
      unquote(block)
    end
  end

  defmacro chat(name, opts \\ [], do: block) do
    add_step(:chat, name, opts, block)
  end

  defmacro chat(name, prompt) when is_binary(prompt) or is_tuple(prompt) do
    add_step(:chat, name, [], quote(do: unquote(prompt)))
  end

  defmacro cmd(name, command) do
    add_step(:cmd, name, [], quote(do: unquote(command)))
  end

  defmacro cmd(name, opts, do: block) do
    add_step(:cmd, name, opts, block)
  end

  defmacro agent(name, opts \\ [], do: block) do
    add_step(:agent, name, opts, block)
  end

  defmacro ruby(name, opts \\ [], do: block) do
    # Keep the Roast name; in Elixir this is just an Elixir callback.
    add_step(:elixir, name, opts, block)
  end

  defmacro elixir_cog(name, opts \\ [], do: block) do
    add_step(:elixir, name, opts, block)
  end

  defmacro map_cog(name, opts \\ [], do: block) do
    add_step(:map, name, opts, block)
  end

  defp add_step(type, name, opts, block) do
    quote do
      @roast_steps %{
        type: unquote(type),
        name: unquote(name),
        opts: unquote(opts),
        fun: fn ctx ->
          var!(ctx) = ctx
          unquote(block)
        end
      }
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __roast_config__, do: @roast_config
      def __roast_steps__, do: Enum.reverse(@roast_steps)
    end
  end

  def __normalize_config__(cfg) when is_map(cfg), do: cfg
  def __normalize_config__(cfg) when is_list(cfg), do: Map.new(cfg)
  def __normalize_config__(_), do: %{}
end
