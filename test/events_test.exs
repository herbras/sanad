defmodule EventsTest do
  use ExUnit.Case, async: true

  alias Sanad.{Event, EventCollector}

  doctest Sanad.Event

  defmodule SerialWorkflow do
    use Sanad.DSL

    execute do
      elixir_cog(:a, do: 1)
      elixir_cog(:b, do: 2)
    end
  end

  defmodule ControlWorkflow do
    use Sanad.DSL

    config do
      %{abort_on_failure: false}
    end

    execute do
      elixir_cog(:skipped, do: skip!())
      elixir_cog(:failed, do: fail!("nope"))
      elixir_cog(:fine, do: :ok)
    end
  end

  defmodule NestedWorkflow do
    use Sanad.DSL

    execute :inner do
      elixir_cog(:doubled, do: ctx.scope_value * 2)
    end

    execute do
      call_cog(:called, scope: :inner, do: 21)
    end
  end

  defmodule MapWorkflow do
    use Sanad.DSL

    execute :one_item do
      elixir_cog(:upcased, do: String.upcase(ctx.scope_value))
    end

    execute do
      map_cog :mapped, scope: :one_item, parallel: 3 do
        ["a", "b", "c"]
      end
    end
  end

  defmodule BreakWorkflow do
    use Sanad.DSL

    execute :slow_item do
      elixir_cog :work do
        if ctx.scope_value == :breaker do
          Process.sleep(20)
          break!()
        else
          Process.sleep(2_000)
          ctx.scope_value
        end
      end
    end

    execute do
      map_cog :mapped, scope: :slow_item, parallel: 3 do
        [:breaker, :slow_one, :slow_two]
      end
    end
  end

  defmodule RaisingWorkflow do
    use Sanad.DSL

    execute do
      elixir_cog(:boom, do: raise("exploded"))
    end
  end

  setup do
    run_id = make_ref()
    EventCollector.attach(run_id)
    {:ok, run_id: run_id}
  end

  defp run(module, run_id) do
    Sanad.run(module, run_id: run_id)
    EventCollector.drain()
  end

  describe "serial workflows" do
    test "emit workflow and cog spans in source order", %{run_id: run_id} do
      events = run(SerialWorkflow, run_id)

      assert EventCollector.trace(events) == [
               {:workflow_start, ""},
               {:cog_start, "elixir(:a)"},
               {:cog_stop, "elixir(:a)"},
               {:cog_start, "elixir(:b)"},
               {:cog_stop, "elixir(:b)"},
               {:workflow_stop, ""}
             ]
    end

    test "stop events carry a duration", %{run_id: run_id} do
      [stop] =
        SerialWorkflow
        |> run(run_id)
        |> EventCollector.named([:sanad, :cog, :stop])
        |> Enum.take(1)

      assert Event.duration_ms(stop) >= 0
    end

    test "control flow is reported as the cog status", %{run_id: run_id} do
      statuses =
        ControlWorkflow
        |> run(run_id)
        |> EventCollector.named([:sanad, :cog, :stop])
        |> Enum.map(&{&1.metadata.name, &1.metadata.status})

      assert statuses == [{:skipped, :skipped}, {:failed, :failed}, {:fine, :ok}]
    end
  end

  describe "nested scopes" do
    test "hang off the cog that called them", %{run_id: run_id} do
      assert EventCollector.trace(run(NestedWorkflow, run_id)) == [
               {:workflow_start, ""},
               {:cog_start, "call(:called)"},
               {:scope_start, "call(:called) -> {:inner}[0]"},
               {:cog_start, "call(:called) -> {:inner}[0] -> elixir(:doubled)"},
               {:cog_stop, "call(:called) -> {:inner}[0] -> elixir(:doubled)"},
               {:scope_stop, "call(:called) -> {:inner}[0]"},
               {:cog_stop, "call(:called)"},
               {:workflow_stop, ""}
             ]
    end

    test "scope stop carries the scope's final output", %{run_id: run_id} do
      [stop] =
        NestedWorkflow
        |> run(run_id)
        |> EventCollector.named([:sanad, :scope, :stop])

      assert stop.metadata.output == 42
      assert stop.metadata.control == :ok
    end
  end

  describe "parallel map" do
    test "every iteration reports its own path", %{run_id: run_id} do
      events = run(MapWorkflow, run_id)

      paths =
        events
        |> EventCollector.named([:sanad, :scope, :start])
        |> Enum.map(&Event.format_path/1)
        |> Enum.sort()

      assert paths == [
               "map(:mapped) -> {:one_item}[0]",
               "map(:mapped) -> {:one_item}[1]",
               "map(:mapped) -> {:one_item}[2]"
             ]
    end

    test "one iteration's events are ordered even though iterations interleave",
         %{run_id: run_id} do
      trace =
        MapWorkflow
        |> run(run_id)
        |> EventCollector.inside("map(:mapped) -> {:one_item}[1]")
        |> EventCollector.trace()

      assert trace == [
               {:scope_start, "map(:mapped) -> {:one_item}[1]"},
               {:cog_start, "map(:mapped) -> {:one_item}[1] -> elixir(:upcased)"},
               {:cog_stop, "map(:mapped) -> {:one_item}[1] -> elixir(:upcased)"},
               {:scope_stop, "map(:mapped) -> {:one_item}[1]"}
             ]
    end

    test "break! closes the spans of siblings it kills", %{run_id: run_id} do
      events = run(BreakWorkflow, run_id)

      stops = EventCollector.named(events, [:sanad, :scope, :stop])
      cancelled = Enum.filter(stops, &(&1.metadata.control == :cancelled))

      assert length(stops) == 3, "every started iteration must report a stop"
      assert length(cancelled) == 2
      assert Enum.all?(cancelled, &(&1.metadata.reason == :break))

      assert Enum.sort(Enum.map(cancelled, & &1.metadata.index)) == [1, 2]
    end
  end

  describe "exceptions" do
    test "close the cog and the workflow span", %{run_id: run_id} do
      assert_raise RuntimeError, "exploded", fn ->
        Sanad.run(RaisingWorkflow, run_id: run_id)
      end

      events = EventCollector.drain()

      assert [cog_exception] = EventCollector.named(events, [:sanad, :cog, :exception])
      assert cog_exception.metadata.name == :boom
      assert %RuntimeError{} = cog_exception.metadata.reason

      assert [_workflow_exception] = EventCollector.named(events, [:sanad, :workflow, :exception])
    end
  end

  describe "paths" do
    test "inside? matches a prefix" do
      scope = [%Event.Cog{type: :map, name: :m}, %Event.Scope{scope: :inner, index: 1}]
      deeper = scope ++ [%Event.Cog{type: :cmd, name: :c}]

      assert Event.inside?(deeper, scope)
      refute Event.inside?(scope, deeper)
      refute Event.inside?(deeper, [%Event.Cog{type: :map, name: :other}])
    end
  end
end
