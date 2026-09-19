defmodule Sanad.Events.Jsonl do
  @moduledoc """
  Writes run events as JSON Lines, one object per event.

      {"event":"cog.start","path":"cmd(:files)","type":"cmd","name":"files"}
      {"event":"cog.stdout","path":"cmd(:files)","data":"lib/sanad.ex\\n"}
      {"event":"cog.stop","path":"cmd(:files)","status":"ok","duration_ms":12}

  This is the machine-readable half of `Sanad.Events.Renderer`: same events,
  no formatting decisions. `mix sanad.execute --events jsonl` turns it on.

  Only fields worth reading downstream are emitted, and each event is encoded
  independently — metadata holds pids, refs and exception structs that have no
  meaning to a reader and no JSON encoding. Long payloads are truncated to
  `:max_bytes` so a single line stays a single line.
  """

  alias Sanad.Event

  @handler_id {__MODULE__, :cli}
  @max_bytes 2_048

  @doc "Attaches the writer. Options: `:device`, `:id`, `:max_bytes`."
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    config = %{
      device: Keyword.get(opts, :device, :standard_error),
      max_bytes: Keyword.get(opts, :max_bytes, @max_bytes)
    }

    :telemetry.attach_many(
      Keyword.get(opts, :id, @handler_id),
      Event.names(),
      &__MODULE__.handle/4,
      config
    )
  end

  @doc "Detaches the writer."
  @spec detach(term()) :: :ok | {:error, :not_found}
  def detach(id \\ @handler_id), do: :telemetry.detach(id)

  @doc false
  def handle(name, measurements, metadata, config) do
    event = Event.new(name, measurements, metadata)
    IO.write(config.device, [render(event, config.max_bytes), "\n"])
  end

  @doc "Renders one event as a JSON object, without the trailing newline."
  @spec render(Event.t(), pos_integer()) :: iodata()
  def render(%Event{} = event, max_bytes \\ @max_bytes) do
    %{event: short_name(event), path: Event.format_path(event)}
    |> Map.merge(fields(event, max_bytes))
    |> put_duration(event)
    |> Jason.encode_to_iodata!()
  end

  defp short_name(%Event{name: [:sanad, kind, suffix]}), do: "#{kind}.#{suffix}"

  defp fields(%Event{name: [:sanad, :workflow, :start], metadata: meta}, _max) do
    %{module: inspect(meta.module)}
  end

  defp fields(%Event{name: [:sanad, :workflow, :stop], metadata: meta}, _max) do
    %{statuses: Map.new(meta.statuses, fn {name, status} -> {name, to_string(status)} end)}
  end

  defp fields(%Event{name: [:sanad, :scope, suffix], metadata: meta}, _max)
       when suffix in [:start, :stop] do
    %{scope: to_string(meta.scope), index: meta.index}
    |> put_present(:control, meta[:control])
    |> put_present(:reason, meta[:reason])
  end

  defp fields(%Event{name: [:sanad, :cog, suffix], metadata: meta}, _max)
       when suffix in [:start, :stop] do
    %{type: to_string(meta.type), name: to_string(meta.name)}
    |> put_present(:status, meta[:status])
  end

  defp fields(%Event{name: [:sanad, _kind, :exception], metadata: meta}, max) do
    %{kind: to_string(meta.kind), reason: truncate(describe(meta.reason), max)}
  end

  defp fields(%Event{name: [:sanad, :cog, kind], metadata: meta}, max)
       when kind in [:stdout, :stderr] do
    %{data: truncate(meta.data, max)}
  end

  defp fields(%Event{name: [:sanad, :cog, :block], metadata: meta}, max) do
    %{header: meta.header, content: truncate(meta.content, max)}
  end

  defp fields(%Event{name: [:sanad, :cog, :log], metadata: meta}, max) do
    %{level: to_string(meta.level), message: truncate(meta.message, max)}
  end

  defp put_duration(fields, event) do
    case Event.duration_ms(event) do
      nil -> fields
      ms -> Map.put(fields, :duration_ms, ms)
    end
  end

  defp put_present(fields, _key, nil), do: fields
  defp put_present(fields, key, value), do: Map.put(fields, key, to_string(value))

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(other), do: inspect(other)

  defp truncate(binary, max) when byte_size(binary) > max do
    binary_part(binary, 0, max) <> "…"
  end

  defp truncate(binary, _max), do: binary
end
