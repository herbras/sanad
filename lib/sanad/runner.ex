defmodule Sanad.Runner do
  @moduledoc """
  Recursive step runner.

  Steps are data (`%{type, name, opts, fun}`) produced by `Sanad.DSL`; the
  runner resolves each step's cog through `Sanad.Cog.Registry`, runs the
  input block against the current context, and stores outputs by name.

  Control flow (`skip!`, `fail!`, `next!`, `break!`) is caught at the step
  boundary. `next!` / `break!` stop the current scope and are surfaced upward
  through the return value of `run_steps/2` so nested cogs (call/map/repeat)
  can implement Roast semantics.
  """

  alias Sanad.{Cog, Config, Context}

  @typedoc "Signal returned by `run_steps/2` to the enclosing scope."
  @type control :: :ok | :next | :break

  @doc """
  Runs a workflow module (or a workflow file when given a path and `:module`).
  """
  def run(module, opts) when is_atom(module) do
    ctx = %Context{
      config: Config.normalize(module.__sanad_config__()),
      params: Keyword.get(opts, :params, %{}),
      workflow_dir: Keyword.get(opts, :workflow_dir, File.cwd!()),
      module: module
    }

    {ctx, _control} = run_steps(module.__sanad_steps__(), ctx)
    ctx
  end

  def run(path, opts) when is_binary(path) do
    Code.require_file(path)
    module = Keyword.fetch!(opts, :module)
    run(module, Keyword.put_new(opts, :workflow_dir, Path.dirname(Path.expand(path))))
  end

  @doc """
  Runs a list of steps against a context.

  Returns `{ctx, control}` where `control` is `:ok`, `:next` (scope ended
  early) or `:break` (scope ended and the signal should propagate).
  """
  @spec run_steps([map()], Context.t()) :: {Context.t(), control()}
  def run_steps(steps, %Context{} = ctx) when is_list(steps) do
    Enum.reduce_while(steps, {ctx, :ok}, fn step, {ctx, _control} ->
      case execute_step(step, ctx) do
        {:cont, ctx} -> {:cont, {ctx, :ok}}
        {:halt, ctx, control} -> {:halt, {ctx, control}}
      end
    end)
  end

  @doc """
  Runs a named `execute :scope` block in an isolated child context.

  The child context starts with empty outputs/statuses, inherits config,
  params, workflow_dir and module, and carries `scope_value` / `scope_index`.

  Returns `{final_output, child_ctx, control}` where `final_output` is the last
  step's output (nil when the scope was skipped/ended early), matching
  upstream Roast's default final output.
  """
  @spec run_scope(Context.t(), atom(), term(), non_neg_integer()) ::
          {term(), Context.t(), control()}
  def run_scope(%Context{} = parent, scope, value, index \\ 0) when is_atom(scope) do
    steps = fetch_scope!(parent, scope)

    child = %{
      parent
      | outputs: %{},
        statuses: %{},
        failures: %{},
        scope_value: value,
        scope_index: index
    }

    {ctx, control} = run_steps(steps, child)
    {final_output(steps, ctx), ctx, control}
  end

  defp fetch_scope!(%Context{module: nil}, scope) do
    raise Sanad.UnknownScopeError, scope: scope, module: nil
  end

  defp fetch_scope!(%Context{module: module}, scope) do
    case Map.get(module.__sanad_scopes__(), scope) do
      nil -> raise Sanad.UnknownScopeError, scope: scope, module: module
      steps -> steps
    end
  end

  defp final_output(steps, ctx) do
    case List.last(steps) do
      nil -> nil
      %{name: name} -> Map.get(ctx.outputs, name)
    end
  end

  defp execute_step(%{type: type, name: name, opts: opts, fun: fun}, ctx) do
    opts = normalize_opts(opts)
    started = System.monotonic_time(:millisecond)

    result =
      try do
        input = eval_fun(fun, ctx)
        cog = fetch_cog!(type)
        {:ok, Cog.run(cog, input, opts, ctx)}
      catch
        {:sanad_control, kind, message} -> {:control, kind, message}
      end

    elapsed = System.monotonic_time(:millisecond) - started

    case handle_result(result, name, opts, ctx) do
      {:cont, ctx} -> {:cont, Context.put_timing(ctx, name, elapsed)}
      {:halt, ctx, control} -> {:halt, Context.put_timing(ctx, name, elapsed), control}
    end
  end

  defp handle_result({:ok, output}, name, _opts, ctx) do
    {:cont, Context.put(ctx, name, output)}
  end

  defp handle_result({:control, :skip, _message}, name, _opts, ctx) do
    {:cont, Context.put_status(ctx, name, :skipped)}
  end

  defp handle_result({:control, :fail, message}, name, opts, ctx) do
    ctx = ctx |> Context.put_status(name, :failed) |> Context.put_failure(name, message)

    if Config.abort_on_failure?(ctx, opts) do
      raise Sanad.CogFailedError, name: name, reason: message
    else
      {:cont, ctx}
    end
  end

  defp handle_result({:control, :next, _message}, _name, _opts, ctx), do: {:halt, ctx, :next}
  defp handle_result({:control, :break, _message}, _name, _opts, ctx), do: {:halt, ctx, :break}

  defp eval_fun(fun, ctx) when is_function(fun, 1), do: fun.(ctx)

  defp eval_fun({module, name}, ctx) when is_atom(module) and is_atom(name) do
    apply(module, name, [ctx])
  end

  defp fetch_cog!(type) do
    case Sanad.Cog.Registry.lookup(type) do
      {:ok, cog} -> cog
      :error -> raise Sanad.UnknownCogError, type: type
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(nil), do: []

  defp normalize_opts(other) do
    raise ArgumentError,
          "step opts must be a keyword list or a map, got: #{inspect(other)}"
  end
end
