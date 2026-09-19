defmodule ConfigScopedTest do
  use ExUnit.Case, async: false

  alias Sanad.Config
  alias Sanad.Config.Index
  alias Sanad.{Context, Runner}

  defmodule ProbeCog do
    @moduledoc false
    # Returns the options it was run with, so tests can see what config
    # resolution produced.
    def run(_input, opts, _ctx), do: Enum.sort(opts)
  end

  defmodule ScopedWorkflow do
    use Sanad.DSL

    config do
      global(abort_on_failure: true, tag: :global)
      probe(model: "base", tag: :general)
      probe(~r/^review_/, model: "regex-first")
      probe(~r/_one$/, model: "regex-second")
      probe(:review_one, model: "exact")
    end

    execute do
      elixir_cog(:noop, do: :ok)
    end
  end

  defmodule LegacyWorkflow do
    use Sanad.DSL

    config do
      %{probe: %{model: "base"}, abort_on_failure: false}
    end

    execute do
      elixir_cog(:noop, do: :ok)
    end
  end

  setup do
    Sanad.Cog.Registry.register(:probe, ProbeCog)
    on_exit(fn -> Sanad.Cog.Registry.unregister(:probe) end)
  end

  defp resolved(index, name, step_opts \\ []) do
    steps = [%{type: :probe, name: name, opts: step_opts, fun: fn _ctx -> :input end}]
    {ctx, :ok} = Runner.run_steps(steps, %Context{config_index: index})
    ctx.outputs[name]
  end

  describe "resolve/4" do
    test "an empty index returns the step's own options" do
      assert Config.resolve(%Index{}, :chat, :x, a: 1) == [a: 1]
    end

    test "a cog type's general config beats global" do
      index = Index.build([{:global, nil, [model: "g"]}, {:chat, nil, [model: "c"]}])

      assert Config.resolve(index, :chat, :x)[:model] == "c"
      assert Config.resolve(index, :cmd, :x)[:model] == "g"
    end

    test "later patterns win over earlier ones" do
      forwards = Index.build([{:chat, ~r/^rev/, [m: 1]}, {:chat, ~r/iew$/, [m: 2]}])
      backwards = Index.build([{:chat, ~r/iew$/, [m: 2]}, {:chat, ~r/^rev/, [m: 1]}])

      assert Config.resolve(forwards, :chat, :review)[:m] == 2
      assert Config.resolve(backwards, :chat, :review)[:m] == 1
    end

    test "an exact name wins over every matching pattern, whatever the order" do
      index = Index.build([{:chat, :summary, [m: "n"]}, {:chat, ~r/^sum/, [m: "r"]}])

      assert Config.resolve(index, :chat, :summary)[:m] == "n"
    end

    test "a pattern that does not match contributes nothing" do
      index = Index.build([{:chat, ~r/^nope/, [m: "r", extra: true]}])

      assert Config.resolve(index, :chat, :summary) == []
    end

    test "without a name, only global and general apply" do
      index = Index.build([{:chat, nil, [m: "c"]}, {:chat, :summary, [m: "n"]}])

      assert Config.resolve(index, :chat, nil)[:m] == "c"
    end

    test "merging is shallow, as upstream's is" do
      index =
        Index.build([{:global, nil, [req_options: [a: 1]]}, {:chat, nil, [req_options: []]}])

      assert Config.resolve(index, :chat, :x)[:req_options] == []
    end
  end

  describe "the legacy map form" do
    test "lifts registered cog types to general config and the rest to global" do
      index = Index.from_legacy(%{probe: %{m: 1}, abort_on_failure: true, mystery: 2})

      assert index.general == %{probe: %{m: 1}}
      assert index.global == %{abort_on_failure: true, mystery: 2}
    end

    test "still exposes __sanad_config__ unchanged" do
      assert LegacyWorkflow.__sanad_config__() == %{
               probe: %{model: "base"},
               abort_on_failure: false
             }
    end
  end

  describe "the scoped form" do
    test "indexes each declaration by how specific it is" do
      index = ScopedWorkflow.__sanad_config_index__()

      assert index.global == %{abort_on_failure: true, tag: :global}
      assert index.general == %{probe: %{model: "base", tag: :general}}
      assert index.names == %{probe: %{review_one: %{model: "exact"}}}
      assert [{_, %{model: "regex-first"}}, {_, %{model: "regex-second"}}] = index.patterns.probe
    end

    test "still fills __sanad_config__ for workflows that read ctx.config" do
      assert ScopedWorkflow.__sanad_config__()[:abort_on_failure] == true
      assert ScopedWorkflow.__sanad_config__()[:probe][:model] == "base"
    end

    test "a block mixing both forms is rejected" do
      source = """
      defmodule MixedConfig do
        use Sanad.DSL

        config do
          chat(model: "x")
          %{agent: %{provider: :pi}}
        end
      end
      """

      assert_raise ArgumentError, ~r/not both/, fn -> Code.compile_string(source) end
    end
  end

  describe "resolution through the runner" do
    test "each layer reaches the cog, most specific last" do
      index = ScopedWorkflow.__sanad_config_index__()

      assert resolved(index, :plain)[:model] == "base"
      assert resolved(index, :plain)[:tag] == :general
      assert resolved(index, :plain)[:abort_on_failure] == true
      assert resolved(index, :review_other)[:model] == "regex-first"
      assert resolved(index, :other_one)[:model] == "regex-second"
      assert resolved(index, :review_one)[:model] == "exact"
    end

    test "step options beat everything" do
      index = ScopedWorkflow.__sanad_config_index__()

      assert resolved(index, :review_one, model: "step")[:model] == "step"
    end

    test "keyword-valued options survive config as keyword lists" do
      index = Index.build([{:probe, :x, [req_options: [plug: {Req.Test, :stub}]]}])

      assert resolved(index, :x)[:req_options] == [plug: {Req.Test, :stub}]
    end
  end
end
