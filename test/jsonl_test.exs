defmodule JsonlTest do
  use ExUnit.Case, async: true

  alias Sanad.Event
  alias Sanad.Events.Jsonl

  defp render(name, metadata, measurements \\ %{}, path \\ []) do
    name
    |> Event.new(measurements, Map.put(metadata, :path, path))
    |> Jsonl.render()
    |> IO.iodata_to_binary()
    |> Jason.decode!()
  end

  @cmd_path [%Event.Cog{type: :cmd, name: :files}]

  test "a cog span renders its identity and duration" do
    start = render([:sanad, :cog, :start], %{type: :cmd, name: :files}, %{}, @cmd_path)

    assert start == %{
             "event" => "cog.start",
             "path" => "cmd(:files)",
             "type" => "cmd",
             "name" => "files"
           }

    stop =
      render(
        [:sanad, :cog, :stop],
        %{type: :cmd, name: :files, status: :ok},
        %{duration: System.convert_time_unit(7, :millisecond, :native)},
        @cmd_path
      )

    assert stop["status"] == "ok"
    assert stop["duration_ms"] == 7
  end

  test "a cancelled scope keeps its control and reason" do
    path = [%Event.Cog{type: :map, name: :m}, %Event.Scope{scope: :item, index: 2}]

    event =
      render(
        [:sanad, :scope, :stop],
        %{scope: :item, index: 2, control: :cancelled, reason: :break},
        %{},
        path
      )

    assert event["scope"] == "item"
    assert event["index"] == 2
    assert event["control"] == "cancelled"
    assert event["reason"] == "break"
    assert event["path"] == "map(:m) -> {:item}[2]"
  end

  test "an exception renders its message, not the struct" do
    event =
      render(
        [:sanad, :cog, :exception],
        %{kind: :error, reason: %RuntimeError{message: "boom"}},
        %{},
        @cmd_path
      )

    assert event["kind"] == "error"
    assert event["reason"] == "boom"
  end

  test "long payloads are truncated so one event stays one line" do
    data = String.duplicate("x", 5_000)

    line =
      [:sanad, :cog, :stdout]
      |> Event.new(%{}, %{path: @cmd_path, data: data})
      |> Jsonl.render(100)
      |> IO.iodata_to_binary()

    refute line =~ "\n"
    assert String.length(Jason.decode!(line)["data"]) == 101
  end

  test "statuses are rendered as plain strings" do
    event = render([:sanad, :workflow, :stop], %{statuses: %{a: :ok, b: :skipped}})

    assert event["statuses"] == %{"a" => "ok", "b" => "skipped"}
  end
end
