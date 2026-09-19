defmodule Sanad.ExamplesTest do
  @moduledoc """
  Runs every example through the built escript, the way a reader of the README
  would.

  Unit tests call the runtime directly, so a change to what a cog returns can
  stay green while every example in the repository breaks. That already
  happened once: `map` and `repeat` started returning structs and nothing
  noticed. These tests exist to make that impossible to miss.

  Which examples need a provider is decided by reading each workflow's own
  step manifest, not by a list kept here — a list would drift exactly like the
  documentation it is meant to protect.
  """

  use ExUnit.Case, async: false

  @project_root Path.expand("..", __DIR__)
  @escript Path.join(@project_root, "sanad")

  setup_all do
    {output, status} =
      System.cmd("mix", ["escript.build"], cd: @project_root, stderr_to_stdout: true)

    assert status == 0, "mix escript.build failed:\n#{output}"
    assert File.exists?(@escript), "escript was not built at #{@escript}"

    {:ok, examples: classify_examples()}
  end

  defp classify_examples do
    @project_root
    |> Path.join("examples/*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.split_with(&needs_provider?/1)
    |> then(fn {live, offline} -> %{live: live, offline: offline} end)
  end

  # A workflow needs a provider when any of its steps is a chat or an agent.
  # Asking the compiled module beats guessing from the filename.
  defp needs_provider?(path) do
    # `require_file` registers the path, so the later `Sanad.run_file/2` in this
    # suite reuses it instead of recompiling the module.
    Code.require_file(path)

    path
    |> Sanad.guess_module()
    |> then(&Module.concat([&1]))
    |> apply(:__sanad_scopes__, [])
    |> Map.values()
    |> List.flatten()
    |> Enum.any?(&(&1.type in [:chat, :agent]))
  end

  defp run_escript(path, args \\ []) do
    System.cmd(@escript, [path | args], cd: @project_root, stderr_to_stdout: true)
  end

  test "every offline example still runs through the escript", %{examples: examples} do
    assert length(examples.offline) >= 3,
           "expected the offline examples to be discovered, found: #{inspect(examples.offline)}"

    for path <- examples.offline do
      {output, status} = run_escript(path)
      relative = Path.relative_to(path, @project_root)

      assert status == 0, "#{relative} exited #{status}:\n#{output}"
      assert output =~ "Sanad workflow finished in", "#{relative} printed no summary:\n#{output}"
    end
  end

  test "the examples needing a provider are exactly the ones we think", %{examples: examples} do
    names = Enum.map(examples.live, &Path.basename/1)

    assert "analyze_codebase.exs" in names
    assert "pi_and_claude.exs" in names
  end

  @tag :live_providers
  test "examples that need a provider run too", %{examples: examples} do
    for path <- examples.live do
      {output, status} = run_escript(path)
      assert status == 0, "#{Path.relative_to(path, @project_root)} exited #{status}:\n#{output}"
    end
  end

  describe "the public accessors the examples and README rely on" do
    setup do
      {:ok, ctx: Sanad.run_file(Path.join(@project_root, "examples/local_pipeline.exs"), [])}
    end

    test "Sanad.Cogs.Map keeps the shape README documents", %{ctx: ctx} do
      mapped = ctx.outputs[:lengths]

      assert %Sanad.Output.MapResult{} = mapped
      assert Sanad.Cogs.Map.collect(mapped) == [1, 2, 3]
      assert Sanad.Cogs.Map.from(mapped, & &1.scope_value) == ["a", "bb", "ccc"]
      assert Sanad.Cogs.Map.reduce(mapped, 0, fn acc, n -> acc + n end) == 6
    end

    test "Sanad.Cogs.Repeat keeps the shape README documents", %{ctx: ctx} do
      looped = ctx.outputs[:counter]

      assert %Sanad.Output.Repeat{} = looped
      assert Sanad.Cogs.Repeat.collect(looped) == [1, 2, 3, nil]
    end

    test "Sanad.Cogs.Call keeps the shape README documents", %{ctx: ctx} do
      called = ctx.outputs[:loud]

      assert %Sanad.Output.Call{} = called
      assert called.value == "HELLO WORLD"
      assert Sanad.Cogs.Call.from(called, & &1.outputs[:value]) == "HELLO WORLD"
    end
  end
end
