defmodule Sanad.Cog.RegistryTest do
  use ExUnit.Case, async: false

  alias Sanad.{Context, Runner}

  defmodule FakeCog do
    def run(input, _opts, _ctx), do: {:fake, input}
  end

  defmodule ValidatingCog do
    def validate_input(input, _opts) when is_integer(input), do: :ok
    def validate_input(_input, _opts), do: {:error, :not_an_integer}
    def run(input, _opts, _ctx), do: input * 2
  end

  setup do
    Sanad.Cog.Registry.register(:fake, FakeCog)
    on_exit(fn -> Sanad.Cog.Registry.unregister(:fake) end)
  end

  test "registry resolves builtins and overrides" do
    assert {:ok, Sanad.Cogs.Cmd} = Sanad.Cog.Registry.lookup(:cmd)
    assert {:ok, FakeCog} = Sanad.Cog.Registry.lookup(:fake)
    assert :error = Sanad.Cog.Registry.lookup(:missing)
  end

  test "runner executes a registered custom cog" do
    steps = [%{type: :fake, name: :x, opts: [], fun: fn _ctx -> 41 end}]

    {ctx, :ok} = Runner.run_steps(steps, %Context{})
    assert ctx.outputs[:x] == {:fake, 41}
  end

  test "validate_input/2 is enforced when a cog implements it" do
    Sanad.Cog.Registry.register(:validating, ValidatingCog)
    on_exit(fn -> Sanad.Cog.Registry.unregister(:validating) end)

    good = [%{type: :validating, name: :x, opts: [], fun: fn _ctx -> 21 end}]
    {ctx, :ok} = Runner.run_steps(good, %Context{})
    assert ctx.outputs[:x] == 42

    bad = [%{type: :validating, name: :x, opts: [], fun: fn _ctx -> "nope" end}]

    assert_raise ArgumentError, ~r/invalid input/, fn ->
      Runner.run_steps(bad, %Context{})
    end
  end

  test "register/2 rejects nil modules" do
    assert_raise ArgumentError, ~r/cannot be nil/, fn ->
      Sanad.Cog.Registry.register(:bad, nil)
    end
  end
end
