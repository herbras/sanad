defmodule Sanad.Events.Renderer do
  @moduledoc """
  Renders run events as Roast-style log lines.

      🔥🔥🔥 Workflow Starting
      cmd(:files) Starting
      cmd(:files) ❯ lib/sanad.ex
      cmd(:files) Complete
      chat(:summary) [prompt]↓
      ────────────────────────────────────────
      Summarize this
      ────────────────────────────────────────
      🔥🔥🔥 Workflow Complete

  `render/1` is a pure function from an event to iodata, so the format is
  testable without attaching anything. `attach/1` wires it to the event
  stream, writing each event with a single `IO.write/2` — the device's
  group leader is what keeps concurrent `map` iterations from interleaving
  mid-line.

  Output goes to stderr by default, leaving stdout free for a workflow's
  own results.
  """

  alias Sanad.Event

  @handler_id {__MODULE__, :cli}
  @separator String.duplicate("─", 40)

  @doc """
  Attaches the renderer.

  Options: `:device` (default `:standard_error`) and `:id`.
  """
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    config = %{device: Keyword.get(opts, :device, :standard_error)}

    :telemetry.attach_many(
      Keyword.get(opts, :id, @handler_id),
      Event.names(),
      &__MODULE__.handle/4,
      config
    )
  end

  @doc "Detaches the renderer."
  @spec detach(term()) :: :ok | {:error, :not_found}
  def detach(id \\ @handler_id), do: :telemetry.detach(id)

  @doc false
  def handle(name, measurements, metadata, %{device: device}) do
    case render(Event.new(name, measurements, metadata)) do
      [] -> :ok
      iodata -> IO.write(device, iodata)
    end
  end

  @doc "Renders one event as the iodata to write, including the trailing newline."
  @spec render(Event.t()) :: iodata()
  def render(%Event{name: [:sanad, :workflow, :start]}), do: "🔥🔥🔥 Workflow Starting\n"
  def render(%Event{name: [:sanad, :workflow, :stop]}), do: "🔥🔥🔥 Workflow Complete\n"

  def render(%Event{name: [:sanad, :workflow, :exception]} = event) do
    ["🔥🔥🔥 Workflow Failed: ", describe(event.metadata.reason), "\n"]
  end

  def render(%Event{name: [:sanad, _kind, :start]} = event) do
    [Event.format_path(event), " Starting\n"]
  end

  def render(%Event{name: [:sanad, _kind, :stop]} = event) do
    [Event.format_path(event), " ", completion(event), "\n"]
  end

  def render(%Event{name: [:sanad, _kind, :exception]} = event) do
    [Event.format_path(event), " Failed: ", describe(event.metadata.reason), "\n"]
  end

  def render(%Event{name: [:sanad, :cog, :stdout]} = event) do
    stream(event, event.metadata.data, "❯", "❙")
  end

  def render(%Event{name: [:sanad, :cog, :stderr]} = event) do
    stream(event, event.metadata.data, "❯❯", "❙❙")
  end

  def render(%Event{name: [:sanad, :cog, :block]} = event) do
    path = Event.format_path(event)

    [
      path,
      " [",
      event.metadata.header,
      "]↓\n",
      @separator,
      "\n",
      String.trim_trailing(event.metadata.content),
      "\n",
      @separator,
      "\n"
    ]
  end

  def render(%Event{name: [:sanad, :cog, :log]} = event) do
    [
      Event.format_path(event),
      " [",
      to_string(event.metadata.level),
      "] ",
      event.metadata.message,
      "\n"
    ]
  end

  # A cancelled scope did not finish; anything else reports how it ended, with
  # `:ok` staying the bare "Complete" that upstream prints.
  defp completion(%Event{metadata: %{control: :cancelled, reason: reason}}) do
    "Cancelled (#{reason})"
  end

  defp completion(%Event{metadata: %{status: :ok}}), do: "Complete"
  defp completion(%Event{metadata: %{status: status}}), do: "Complete (#{status})"
  defp completion(%Event{metadata: %{control: :ok}}), do: "Complete"
  defp completion(%Event{metadata: %{control: control}}), do: "Complete (#{control})"
  defp completion(%Event{}), do: "Complete"

  # Roast prefixes the first line with the path and every continuation line
  # with dots of the same width, so output stays visually attached to its cog.
  defp stream(event, data, first_marker, rest_marker) do
    path = Event.format_path(event)
    dots = String.duplicate("·", String.length(path))

    data
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn
      {line, 0} -> [path, " ", first_marker, " ", String.trim_trailing(line), "\n"]
      {line, _} -> [dots, " ", rest_marker, " ", String.trim_trailing(line), "\n"]
    end)
  end

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(other), do: inspect(other)
end
