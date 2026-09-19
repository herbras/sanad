defmodule Sanad.DSL do
  @moduledoc """
  Macro DSL for defining Sanad workflows.

  A workflow is a regular Elixir module that `use`s this module and declares a
  `config` block plus one or more `execute` blocks containing cogs:

      defmodule MyWorkflow do
        use Sanad.DSL

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
  (`__sanad_steps__/0`, `__sanad_scopes__/0`, `__sanad_config__/0`); the runner
  never evaluates quoted source at runtime.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Sanad.DSL
      import Sanad.Helpers

      Module.register_attribute(__MODULE__, :sanad_steps, accumulate: true)
      Module.register_attribute(__MODULE__, :sanad_declared_scopes, accumulate: true)
      Module.register_attribute(__MODULE__, :sanad_outputs, accumulate: true)
      Module.register_attribute(__MODULE__, :sanad_config, accumulate: false)
      Module.register_attribute(__MODULE__, :sanad_step_counter, accumulate: false)
      Module.register_attribute(__MODULE__, :sanad_scope, accumulate: false)
      Module.register_attribute(__MODULE__, :sanad_outputs_kinds, accumulate: false)

      @sanad_config %{}
      @sanad_outputs_kinds %{}
      @sanad_step_counter 0
      @sanad_scope nil

      @before_compile Sanad.DSL
    end
  end

  @doc """
  Declares workflow configuration. The block must evaluate to a map or a
  keyword list; nested keyword lists are normalized to maps.
  """
  defmacro config(do: block) do
    case scoped_entries(block) do
      nil ->
        quote do
          @sanad_config Sanad.Config.normalize(unquote(block))

          @doc false
          def __sanad_config_index__, do: Sanad.Config.Index.from_legacy(@sanad_config)
        end

      entries ->
        quote do
          @sanad_config Sanad.Config.Index.legacy_map(Sanad.Config.Index.build(unquote(entries)))

          # Built on call, not stored: a compiled regex holds a reference,
          # which cannot live in a module attribute.
          @doc false
          def __sanad_config_index__, do: Sanad.Config.Index.build(unquote(entries))
        end
    end
  end

  # The scoped form is a block of `cog_type(opts)`, `cog_type(:name, opts)` or
  # `cog_type(~r/pattern/, opts)` calls. Anything else — a map literal, a
  # function call returning config — is the legacy value form. A block that
  # mixes the two is rejected rather than guessed at.
  defp scoped_entries(block) do
    expressions =
      case block do
        {:__block__, _meta, expressions} -> expressions
        single -> [single]
      end

    cond do
      Enum.all?(expressions, &scoped_entry?/1) -> Enum.map(expressions, &scoped_entry/1)
      Enum.any?(expressions, &scoped_entry?/1) -> raise_mixed_config!(expressions)
      true -> nil
    end
  end

  defp scoped_entry?({name, _meta, args})
       when is_atom(name) and is_list(args) and length(args) in 1..2 do
    Keyword.keyword?(List.last(args))
  end

  defp scoped_entry?(_expression), do: false

  defp scoped_entry({name, _meta, [opts]}), do: quote(do: {unquote(name), nil, unquote(opts)})

  defp scoped_entry({name, _meta, [scope, opts]}) do
    quote(do: {unquote(name), unquote(scope), unquote(opts)})
  end

  defp raise_mixed_config!(expressions) do
    offender = Enum.find(expressions, &(not scoped_entry?(&1)))

    raise ArgumentError,
          "config must be either a single value (a map or keyword list) or a block of " <>
            "scoped declarations like `chat(:name, model: \"x\")`, not both; got: " <>
            Macro.to_string(offender)
  end

  @doc "Declares the default (unnamed) execution scope."
  defmacro execute(do: block) do
    Module.put_attribute(__CALLER__.module, :sanad_scope, nil)
    block
  end

  @doc "Declares a named execution scope, callable with `call(:name, value)`."
  defmacro execute(name, do: block) when is_atom(name) do
    # `@sanad_scope` must be written at expansion time: nested cog macros read it
    # while expanding (before any emitted module-body expression is evaluated).
    Module.put_attribute(__CALLER__.module, :sanad_scope, name)

    quote do
      # `@sanad_declared_scopes` must be written as a module-body expression so
      # it persists for __before_compile__/function-body reads.
      @sanad_declared_scopes unquote(name)
      unquote(block)
      Sanad.DSL.__reset_scope__()
    end
  end

  defmacro execute(name, do: _block) do
    raise ArgumentError,
          "execute scope name must be a literal atom, got: #{Macro.to_string(name)}"
  end

  @doc false
  defmacro __reset_scope__ do
    Module.put_attribute(__CALLER__.module, :sanad_scope, nil)
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

  @doc """
  Declares what the surrounding scope returns.

  Without it, a scope returns the output of its last cog. At most one
  `outputs` or `outputs!` per scope. The block runs after the scope's cogs
  with `ctx` bound to the scope's own context, so `ctx.scope_value` and
  `ctx.scope_index` are available:

      execute :review_one do
        chat(:draft) do "Review \#{ctx.scope_value}" end
        cmd(:lint, "mix credo")

        outputs do
          %{draft: chat!(ctx, :draft).response, lint: cmd!(ctx, :lint).status}
        end
      end

  `skip!` and `next!` inside the block make the scope's value `nil`;
  `break!` does too and ends the enclosing loop; `fail!` raises
  `Sanad.OutputsFailedError`.

  Reading a cog that was skipped or never ran — the usual case after a
  `break!` — is swallowed here and makes the value `nil`, so callers need no
  guard code. Use `outputs!` when you would rather those reads raise.
  """
  defmacro outputs(do: block), do: define_outputs(__CALLER__, :outputs, block)

  defmacro outputs(other) do
    raise ArgumentError, "outputs requires a do block, got: #{Macro.to_string(other)}"
  end

  @doc """
  Strict `outputs/1`: reading a cog that was skipped or never ran raises
  instead of making the scope's value `nil`.
  """
  defmacro outputs!(do: block), do: define_outputs(__CALLER__, :outputs!, block)

  defmacro outputs!(other) do
    raise ArgumentError, "outputs! requires a do block, got: #{Macro.to_string(other)}"
  end

  defp define_outputs(caller, kind, block) do
    scope = claim_outputs!(caller, kind)
    counter = Module.get_attribute(caller.module, :sanad_step_counter) || 0
    Module.put_attribute(caller.module, :sanad_step_counter, counter + 1)
    fun_name = :"__sanad_outputs_#{counter}__"

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

      @sanad_outputs {unquote(scope),
                      %{kind: unquote(kind), fun: {__MODULE__, unquote(fun_name)}}}
    end
  end

  # Claimed at expansion time, so a second declaration reports its own line.
  # The accumulating `@sanad_outputs` is still empty while macros expand.
  defp claim_outputs!(caller, kind) do
    scope = Module.get_attribute(caller.module, :sanad_scope)
    claimed = Module.get_attribute(caller.module, :sanad_outputs_kinds) || %{}

    case Map.get(claimed, scope) do
      nil ->
        Module.put_attribute(caller.module, :sanad_outputs_kinds, Map.put(claimed, scope, kind))
        scope

      existing ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "#{kind} declared for scope #{inspect(scope)} of #{inspect(caller.module)}, " <>
              "but #{existing} was already declared for it; " <>
              "at most one outputs/outputs! per execute scope"
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
    counter = Module.get_attribute(caller.module, :sanad_step_counter) || 0
    Module.put_attribute(caller.module, :sanad_step_counter, counter + 1)
    fun_name = :"__sanad_step_#{counter}__"
    scope = Module.get_attribute(caller.module, :sanad_scope)

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

      @sanad_steps {unquote(scope),
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

  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :sanad_steps) || []

    steps
    |> Enum.reverse()
    |> Enum.group_by(fn {scope, _step} -> scope end, fn {_scope, step} -> step.name end)
    |> Enum.each(fn {scope, names} -> validate_unique_names!(env, scope, names) end)

    quote do
      @doc false
      def __sanad_config__, do: @sanad_config

      unless Module.defines?(__MODULE__, {:__sanad_config_index__, 0}) do
        @doc false
        def __sanad_config_index__, do: Sanad.Config.Index.from_legacy(@sanad_config)
      end

      @doc false
      def __sanad_scopes__ do
        scopes =
          @sanad_steps
          |> Enum.reverse()
          |> Enum.group_by(fn {scope, _step} -> scope end, fn {_scope, step} -> step end)

        Enum.reduce(@sanad_declared_scopes, scopes, fn name, acc ->
          Map.put_new(acc, name, [])
        end)
      end

      @doc false
      def __sanad_steps__, do: Map.get(__sanad_scopes__(), nil, [])

      @doc false
      def __sanad_outputs__, do: Map.new(@sanad_outputs)
    end
  end

  defp validate_unique_names!(env, scope, names) do
    case names -- Enum.uniq(names) do
      [] ->
        :ok

      duplicates ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "duplicate cog name(s) #{inspect(Enum.uniq(duplicates))} in scope #{inspect(scope)} " <>
              "of #{inspect(env.module)}; cog names must be unique per scope"
    end
  end
end
