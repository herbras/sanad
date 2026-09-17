defmodule RoastEx.DSL do
  @moduledoc """
  Macro DSL for defining RoastEx workflows.

  A workflow is a regular Elixir module that `use`s this module and declares a
  `config` block plus one or more `execute` blocks containing cogs:

      defmodule MyWorkflow do
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
            "Review these recently changed files:\\n\\n\#{files}"
          end

          chat :summary do
            "Summarize:\\n\\n\#{agent!(ctx, :review).response}"
          end
        end
      end

  Inside each input block the runtime context is bound to `ctx`. Helper
  functions such as `cmd!/2`, `chat!/2`, `agent!/2`, `output!/2`, `skip!/1`,
  `fail!/1`, `next!/1` and `break!/1` are imported automatically.

  The second argument of a cog macro is either a prompt/command value, a
  keyword list of step options, or a keyword list that includes `:do`. A
  keyword list *without* `:do` is treated as the value (not as options).

  Steps are compiled into one generated function per step plus a manifest
  (`__roast_steps__/0`, `__roast_scopes__/0`, `__roast_config__/0`); the runner
  never evaluates quoted source at runtime.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import RoastEx.DSL
      import RoastEx.Helpers

      Module.register_attribute(__MODULE__, :roast_steps, accumulate: true)
      Module.register_attribute(__MODULE__, :roast_config, accumulate: false)
      Module.register_attribute(__MODULE__, :roast_step_counter, accumulate: false)
      Module.register_attribute(__MODULE__, :roast_scope, accumulate: false)

      @roast_config %{}
      @roast_step_counter 0
      @roast_scope nil

      @before_compile RoastEx.DSL
    end
  end

  @doc """
  Declares workflow configuration. The block must evaluate to a map or a
  keyword list; nested keyword lists are normalized to maps.
  """
  defmacro config(do: block) do
    quote do
      @roast_config RoastEx.Config.normalize(unquote(block))
    end
  end

  @doc "Declares the default (unnamed) execution scope."
  defmacro execute(do: block) do
    Module.put_attribute(__CALLER__.module, :roast_scope, nil)
    block
  end

  @doc "Declares a named execution scope, callable with `call(:name, value)`."
  defmacro execute(name, do: block) when is_atom(name) do
    # The attribute must be written at expansion time: nested cog macros expand
    # before any expression emitted in the returned quote would be evaluated.
    Module.put_attribute(__CALLER__.module, :roast_scope, name)

    quote do
      unquote(block)
      RoastEx.DSL.__reset_scope__()
    end
  end

  defmacro execute(name, do: _block) do
    raise ArgumentError,
          "execute scope name must be a literal atom, got: #{Macro.to_string(name)}"
  end

  @doc false
  defmacro __reset_scope__ do
    Module.put_attribute(__CALLER__.module, :roast_scope, nil)
    quote(do: :ok)
  end

  # Generates the public cog macros: `chat`, `cmd`, `agent`, and the
  # Elixir-evaluated `elixir_cog` / `ruby` variants plus `map_cog`.
  for {dsl_name, type} <- [
        {:chat, :chat},
        {:cmd, :cmd},
        {:agent, :agent},
        {:elixir_cog, :elixir},
        {:ruby, :elixir},
        {:map_cog, :map},
        {:call_cog, :call},
        {:repeat_cog, :repeat}
      ] do
    defmacro unquote(dsl_name)(step_name, prompt_or_opts) do
      case split_do(prompt_or_opts) do
        {:do, opts, block} -> add_step(__CALLER__, unquote(type), step_name, opts, block)
        {:value, value} -> add_step(__CALLER__, unquote(type), step_name, [], value)
      end
    end

    defmacro unquote(dsl_name)(step_name, opts, do: block) do
      add_step(__CALLER__, unquote(type), step_name, opts, block)
    end

    defmacro unquote(dsl_name)(step_name, value, opts) when is_list(opts) do
      add_step(__CALLER__, unquote(type), step_name, opts, value)
    end
  end

  defp split_do(arg) when is_list(arg) do
    if Keyword.keyword?(arg) and Keyword.has_key?(arg, :do) do
      {block, opts} = Keyword.pop(arg, :do)
      {:do, opts, block}
    else
      {:value, arg}
    end
  end

  defp split_do(arg), do: {:value, arg}

  defp add_step(caller, type, name, opts, block) do
    counter = Module.get_attribute(caller.module, :roast_step_counter) || 0
    Module.put_attribute(caller.module, :roast_step_counter, counter + 1)
    fun_name = :"__roast_step_#{counter}__"
    scope = Module.get_attribute(caller.module, :roast_scope)

    fun_def =
      if ctx_used?(block) do
        quote do
          @doc false
          def unquote(fun_name)(ctx) do
            var!(ctx) = ctx
            unquote(block)
          end
        end
      else
        quote do
          @doc false
          def unquote(fun_name)(_ctx) do
            unquote(block)
          end
        end
      end

    quote do
      unquote(fun_def)

      @roast_steps {unquote(scope),
                    %{
                      type: unquote(type),
                      name: unquote(name),
                      opts: unquote(opts),
                      fun: {__MODULE__, unquote(fun_name)}
                    }}
    end
  end

  # Detects whether an input block references the runtime `ctx` variable, so
  # blocks that ignore it do not produce unused-variable warnings. Variables
  # named `ctx` bound by a nested `fn`/closure are treated as shadowing and do
  # not count.
  defp ctx_used?(block), do: scan_ctx(block, false)

  defp scan_ctx({:fn, _meta, clauses}, used) do
    if Enum.any?(clauses, &clause_binds_ctx?/1), do: used, else: scan_ctx(clauses, used)
  end

  defp scan_ctx({:ctx, meta, context}, _used)
       when is_list(meta) and (is_atom(context) or is_nil(context)),
       do: true

  defp scan_ctx(list, used) when is_list(list), do: Enum.reduce(list, used, &scan_ctx/2)
  defp scan_ctx(tuple, used) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> scan_ctx(used)
  defp scan_ctx(_other, used), do: used

  defp clause_binds_ctx?({:->, _meta, [params | _body]}), do: binds_ctx?(params)
  defp clause_binds_ctx?(_other), do: false

  defp binds_ctx?({:ctx, meta, context})
       when is_list(meta) and (is_atom(context) or is_nil(context)),
       do: true

  defp binds_ctx?(list) when is_list(list), do: Enum.any?(list, &binds_ctx?/1)
  defp binds_ctx?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> binds_ctx?()
  defp binds_ctx?(_other), do: false

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __roast_config__, do: @roast_config

      @doc false
      def __roast_scopes__ do
        @roast_steps
        |> Enum.reverse()
        |> Enum.group_by(fn {scope, _step} -> scope end, fn {_scope, step} -> step end)
      end

      @doc false
      def __roast_steps__, do: Map.get(__roast_scopes__(), nil, [])
    end
  end
end
