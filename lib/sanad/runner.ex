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

  alias Sanad.{Cog, Config, Context, Events}

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
      module: module,
      run_id: Keyword.get(opts, :run_id) || make_ref()
    }

    meta = %{module: module, params: ctx.params, workflow_dir: ctx.workflow_dir}
    span = Events.span_start(ctx, :workflow, meta)

    try do
      {ctx, _control} = run_steps(module.__sanad_steps__(), ctx)
      Events.span_stop(ctx, :workflow, span, Map.put(meta, :statuses, ctx.statuses))
      ctx
    rescue
      error ->
        Events.span_exception(ctx, :workflow, span, :error, error, __STACKTRACE__, meta)
        reraise error, __STACKTRACE__
    end
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
  @spec run_scope(Context.t(), atom(), term(), non_neg_integer(), keyword()) ::
          {term(), Context.t(), control()}
  def run_scope(%Context{} = parent, scope, value, index \\ 0, opts \\ []) when is_atom(scope) do
    steps = fetch_scope!(parent, scope)

    child =
      %{
        parent
        | outputs: %{},
          statuses: %{},
          failures: %{},
          scope_value: value,
          scope_index: index
      }
      |> Events.push_scope(scope, index)

    meta = %{scope: scope, index: index, scope_value: value}
    span = Events.span_start(child, :scope, meta, Keyword.get(opts, :span_context))

    try do
      {ctx, control} = run_steps(steps, child)
      output = final_output(steps, ctx)
      Events.span_stop(ctx, :scope, span, Map.merge(meta, %{control: control, output: output}))
      {output, ctx, control}
    rescue
      error ->
        Events.span_exception(child, :scope, span, :error, error, __STACKTRACE__, meta)
        reraise error, __STACKTRACE__
    end
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

    # The cog element is appended for the duration of this step only: the input
    # block and the cog see it (so nested scopes hang off it), while the outer
    # context keeps recording outputs one level up.
    cog_ctx = Events.push_cog(ctx, type, name)
    meta = %{type: type, name: name, opts: opts}
    span = Events.span_start(cog_ctx, :cog, meta)

    result =
      try do
        input = eval_fun(fun, cog_ctx)
        cog = fetch_cog!(type)
        {:ok, Cog.run(cog, input, opts, cog_ctx)}
      rescue
        error ->
          Events.span_exception(cog_ctx, :cog, span, :error, error, __STACKTRACE__, meta)
          reraise error, __STACKTRACE__
      catch
        {:sanad_control, kind, message} -> {:control, kind, message}
      end

    elapsed = System.monotonic_time(:millisecond) - started

    # Emitted before `handle_result/4`, which raises when a `fail!` aborts the
    # workflow; otherwise an aborting step would never report how it ended.
    Events.span_stop(cog_ctx, :cog, span, Map.put(meta, :status, status_of(result)))

    case handle_result(result, name, opts, ctx) do
      {:cont, ctx} -> {:cont, Context.put_timing(ctx, name, elapsed)}
      {:halt, ctx, control} -> {:halt, Context.put_timing(ctx, name, elapsed), control}
    end
  end

  defp status_of({:ok, _output}), do: :ok
  defp status_of({:control, :skip, _message}), do: :skipped
  defp status_of({:control, :fail, _message}), do: :failed
  defp status_of({:control, kind, _message}), do: kind

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
