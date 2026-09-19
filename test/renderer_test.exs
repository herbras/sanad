defmodule RendererTest do
  use ExUnit.Case, async: true

  alias Sanad.Event
  alias Sanad.Events.Renderer

  defp event(name, metadata, path \\ []) do
    Event.new(name, %{}, Map.put(metadata, :path, path))
  end

  defp render(event), do: event |> Renderer.render() |> IO.iodata_to_binary()

  @cmd_path [%Event.Cog{type: :cmd, name: :files}]

  test "workflow boundaries" do
    assert render(event([:sanad, :workflow, :start], %{})) == "🔥🔥🔥 Workflow Starting\n"
    assert render(event([:sanad, :workflow, :stop], %{})) == "🔥🔥🔥 Workflow Complete\n"

    assert render(
             event([:sanad, :workflow, :exception], %{reason: %RuntimeError{message: "boom"}})
           ) ==
             "🔥🔥🔥 Workflow Failed: boom\n"
  end

  test "cog start and completion" do
    assert render(event([:sanad, :cog, :start], %{}, @cmd_path)) == "cmd(:files) Starting\n"

    assert render(event([:sanad, :cog, :stop], %{status: :ok}, @cmd_path)) ==
             "cmd(:files) Complete\n"

    assert render(event([:sanad, :cog, :stop], %{status: :skipped}, @cmd_path)) ==
             "cmd(:files) Complete (skipped)\n"
  end

  test "a cancelled scope says why it was cancelled" do
    path = [%Event.Cog{type: :map, name: :m}, %Event.Scope{scope: :item, index: 2}]

    assert render(event([:sanad, :scope, :stop], %{control: :cancelled, reason: :break}, path)) ==
             "map(:m) -> {:item}[2] Cancelled (break)\n"
  end

  test "stdout continuation lines align under the path" do
    rendered = render(event([:sanad, :cog, :stdout], %{data: "one\ntwo\n"}, @cmd_path))

    assert rendered == """
           cmd(:files) ❯ one
           ··········· ❙ two
           """
  end

  test "stderr uses the doubled markers" do
    rendered = render(event([:sanad, :cog, :stderr], %{data: "bad\nworse"}, @cmd_path))

    assert rendered == """
           cmd(:files) ❯❯ bad
           ··········· ❙❙ worse
           """
  end

  test "blocks are fenced" do
    path = [%Event.Cog{type: :chat, name: :summary}]
    rendered = render(event([:sanad, :cog, :block], %{header: "prompt", content: "hi"}, path))

    separator = String.duplicate("─", 40)

    assert rendered == "chat(:summary) [prompt]↓\n#{separator}\nhi\n#{separator}\n"
  end

  test "attaching renders a real run to the given device" do
    {:ok, device} = StringIO.open("")
    id = {__MODULE__, make_ref()}
    :ok = Renderer.attach(id: id, device: device)
    on_exit(fn -> Renderer.detach(id) end)

    Sanad.run(RendererTest.Workflow, run_id: make_ref())

    {_in, out} = StringIO.contents(device)

    assert out =~ "🔥🔥🔥 Workflow Starting"
    assert out =~ "cmd(:greeting) ❯ hello"
    assert out =~ "cmd(:greeting) Complete"
    assert out =~ "🔥🔥🔥 Workflow Complete"
  end

  defmodule Workflow do
    use Sanad.DSL

    execute do
      cmd(:greeting, "echo hello")
    end
  end
end
