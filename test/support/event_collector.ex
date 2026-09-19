defmodule Sanad.EventCollector do
  @moduledoc """
  Collects run events in tests.

  `:telemetry` handlers are global, so every collector filters on the
  `run_id` of the run it cares about. That keeps `async: true` suites from
  seeing each other's events.
  """

  alias Sanad.Event

  @doc "Attaches a collector for `run_id`, forwarding events to the test process."
  @spec attach(reference()) :: :ok
  def attach(run_id) do
    id = {__MODULE__, run_id}
    config = %{pid: self(), run_id: run_id}

    :telemetry.attach_many(id, Event.names(), &__MODULE__.handle/4, config)
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def handle(name, measurements, %{run_id: run_id} = metadata, %{pid: pid, run_id: run_id}) do
    send(pid, {:sanad_event, Event.new(name, measurements, metadata)})
    :ok
  end

  def handle(_name, _measurements, _metadata, _config), do: :ok

  @doc """
  Drains collected events.

  Returns once the workflow's `stop` or `exception` event has arrived, then
  sweeps briefly for events still in flight from `map` children, whose
  delivery is not ordered against the parent's.
  """
  @spec drain(timeout()) :: [Event.t()]
  def drain(timeout \\ 2_000), do: collect([], timeout, false)

  defp collect(acc, timeout, finished?) do
    receive do
      {:sanad_event, event} ->
        collect([event | acc], timeout, finished? or workflow_over?(event))
    after
      sweep(timeout, finished?) -> Enum.reverse(acc)
    end
  end

  defp sweep(_timeout, true), do: 50
  defp sweep(timeout, false), do: timeout

  defp workflow_over?(%Event{name: [:sanad, :workflow, last]}), do: last in [:stop, :exception]
  defp workflow_over?(%Event{}), do: false

  @doc "Renders events as `{short_name, path}` pairs, for readable assertions."
  @spec trace([Event.t()]) :: [{atom(), String.t()}]
  def trace(events) do
    Enum.map(events, fn event ->
      {short_name(event), Event.format_path(event)}
    end)
  end

  @doc "Keeps only the events that happened at or inside `path`."
  @spec inside([Event.t()], String.t()) :: [Event.t()]
  def inside(events, path) do
    Enum.filter(events, &String.starts_with?(Event.format_path(&1), path))
  end

  @doc "Keeps only events with the given telemetry name."
  @spec named([Event.t()], [atom()]) :: [Event.t()]
  def named(events, name), do: Enum.filter(events, &(&1.name == name))

  defp short_name(%Event{name: [:sanad, kind, suffix]}), do: :"#{kind}_#{suffix}"
end
