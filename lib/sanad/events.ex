defmodule Sanad.Events do
  @moduledoc """
  Emission side of the run event system.

  Events are dispatched with `:telemetry.execute/3` in the process that does
  the work — there is no event process and no queue. Handlers attach to the
  names in `Sanad.Event.names/0`.

  The event path lives on `Sanad.Context` rather than in the process
  dictionary, because `map` runs every iteration in a task under
  `Sanad.TaskSupervisor`: the context is captured by the task closure and
  copied into the child process, so the path crosses the boundary as ordinary
  data. Nothing needs to be re-installed on the other side.

  Ordering: events of one path are totally ordered; concurrent `map` children
  interleave. Readers must not assume a global order.
  """

  alias Sanad.Context
  alias Sanad.Event.{Cog, Scope}

  @typedoc "Open span: its correlation ref and the monotonic time it started."
  @type span :: {reference(), integer()}

  @doc "Appends a cog element to the context path."
  @spec push_cog(Context.t(), atom(), atom()) :: Context.t()
  def push_cog(%Context{} = ctx, type, name) do
    %{ctx | path: ctx.path ++ [%Cog{type: type, name: name}]}
  end

  @doc "Appends a scope element to the context path."
  @spec push_scope(Context.t(), atom() | nil, non_neg_integer()) :: Context.t()
  def push_scope(%Context{} = ctx, scope, index) do
    %{ctx | path: ctx.path ++ [%Scope{scope: scope, index: index}]}
  end

  @doc """
  Opens a span, emitting `[:sanad, kind, :start]`.

  Pass `ref` to reuse a correlation ref the caller allocated, so it can close
  the span itself if the process that opened it is killed.
  """
  @spec span_start(Context.t(), atom(), map(), reference() | nil) :: span()
  def span_start(%Context{} = ctx, kind, metadata, ref \\ nil) do
    ref = ref || make_ref()
    started = System.monotonic_time()

    execute(
      [:sanad, kind, :start],
      %{system_time: System.system_time(), monotonic_time: started},
      ctx,
      Map.put(metadata, :telemetry_span_context, ref)
    )

    {ref, started}
  end

  @doc "Closes a span, emitting `[:sanad, kind, :stop]`."
  @spec span_stop(Context.t(), atom(), span(), map()) :: :ok
  def span_stop(%Context{} = ctx, kind, {ref, started}, metadata) do
    execute(
      [:sanad, kind, :stop],
      %{duration: System.monotonic_time() - started, monotonic_time: System.monotonic_time()},
      ctx,
      Map.put(metadata, :telemetry_span_context, ref)
    )
  end

  @doc """
  Closes a span that ended in an exception, emitting
  `[:sanad, kind, :exception]`.
  """
  @spec span_exception(Context.t(), atom(), span(), atom(), term(), Exception.stacktrace(), map()) ::
          :ok
  def span_exception(%Context{} = ctx, kind, {ref, started}, error_kind, reason, stacktrace, meta) do
    execute(
      [:sanad, kind, :exception],
      %{duration: System.monotonic_time() - started, monotonic_time: System.monotonic_time()},
      ctx,
      Map.merge(meta, %{
        telemetry_span_context: ref,
        kind: error_kind,
        reason: reason,
        stacktrace: stacktrace
      })
    )
  end

  @doc """
  Closes a span on behalf of a process that was killed before it could close
  its own, used when `break!` or a failing sibling cancels `map` children.
  """
  @spec span_cancelled(Context.t(), atom(), reference(), integer(), map()) :: :ok
  def span_cancelled(%Context{} = ctx, kind, ref, started, metadata) do
    span_stop(ctx, kind, {ref, started}, Map.put(metadata, :control, :cancelled))
  end

  @doc "Emits output a cog captured on stdout."
  @spec stdout(Context.t(), binary()) :: :ok
  def stdout(ctx, data), do: emit_data(ctx, :stdout, data)

  @doc "Emits output a cog captured on stderr."
  @spec stderr(Context.t(), binary()) :: :ok
  def stderr(ctx, data), do: emit_data(ctx, :stderr, data)

  @doc "Emits a titled block, used for prompts and model responses."
  @spec block(Context.t(), String.t(), binary()) :: :ok
  def block(%Context{} = ctx, header, content) when is_binary(content) do
    execute(
      [:sanad, :cog, :block],
      %{system_time: System.system_time(), bytes: byte_size(content)},
      ctx,
      %{header: header, content: content}
    )
  end

  @doc "Emits a log line attributed to the current path."
  @spec log(Context.t(), atom(), binary()) :: :ok
  def log(%Context{} = ctx, level, message) when is_binary(message) do
    execute(
      [:sanad, :cog, :log],
      %{system_time: System.system_time()},
      ctx,
      %{level: level, message: message}
    )
  end

  defp emit_data(%Context{} = ctx, kind, data) when is_binary(data) do
    execute(
      [:sanad, :cog, kind],
      %{system_time: System.system_time(), bytes: byte_size(data)},
      ctx,
      %{data: data}
    )
  end

  defp execute(name, measurements, %Context{} = ctx, metadata) do
    :telemetry.execute(
      name,
      measurements,
      Map.merge(metadata, %{run_id: ctx.run_id, path: ctx.path, pid: self()})
    )
  end
end
