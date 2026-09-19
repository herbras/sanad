defmodule Sanad.LiveProvidersTest do
  @moduledoc """
  Smoke tests against the real agent CLIs.

  Every other agent test drives a stub shell script, which proves sanad parses
  what we *think* the CLIs emit. If a provider changes its JSON protocol, those
  stay green while real workflows break. These tests close that gap by running
  the built escript against the actual binaries.

  They are opt-in — they cost real tokens and need the CLIs configured:

      mix test --include live_providers
      SANAD_LIVE=1 mix test

  A provider whose binary is not on PATH generates no test at all; if none are
  installed the suite reports one skipped test rather than passing vacuously.
  That check happens while this file compiles, so a CLI installed afterwards
  needs `mix test --force` before its test appears. Note that the container
  toolchain (`bin/mix`) cannot see CLIs installed on the host — run these
  natively.
  """

  use ExUnit.Case, async: false

  @moduletag :live_providers
  @moduletag timeout: 180_000

  @project_root Path.expand("..", __DIR__)
  @escript Path.join(@project_root, "sanad")
  @providers [pi: "pi", claude: "claude", opencode: "opencode", agy: "agy"]

  @installed Enum.filter(@providers, fn {_provider, binary} ->
               System.find_executable(binary) != nil
             end)

  setup_all do
    {output, status} =
      System.cmd("mix", ["escript.build"], cd: @project_root, stderr_to_stdout: true)

    assert status == 0, "mix escript.build failed:\n#{output}"

    dir = Path.join(System.tmp_dir!(), "sanad_live_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, dir: dir}
  end

  if @installed == [] do
    @tag :skip
    test "no agent CLI on PATH, so there is nothing to smoke test" do
      assert File.exists?(@escript)
    end
  end

  for {provider, binary} <- @installed do
    test "#{provider}: answers a one-line prompt through the escript", %{dir: dir} do
      provider = unquote(provider)
      binary = unquote(binary)

      module = "LivePing" <> (provider |> Atom.to_string() |> String.capitalize())
      path = Path.join(dir, Macro.underscore(module) <> ".exs")

      File.write!(path, """
      defmodule #{module} do
        use Sanad.DSL

        config do
          agent(provider: #{inspect(provider)}, timeout: 120_000)
        end

        execute do
          agent :ping do
            "Reply with exactly one word: PONG"
          end
        end
      end
      """)

      {output, status} = System.cmd(@escript, [path], cd: @project_root, stderr_to_stdout: true)

      assert status == 0, "#{binary} run exited #{status}:\n#{output}"
      assert output =~ "[ok] ping", "#{binary} did not complete the agent step:\n#{output}"

      # The model's wording is its own business. What this pins is that sanad
      # got a non-empty response out of the provider's real protocol.
      assert output =~ "response:", "no response field in the output:\n#{output}"
    end
  end
end
