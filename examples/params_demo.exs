defmodule ParamsDemo do
  @moduledoc """
  Workflow params from the CLI:

      mix sanad.execute examples/params_demo.exs --param name=world --param loud=true

  Params are exposed to input blocks via `params(ctx)`.
  """

  use Sanad.DSL

  execute do
    elixir_cog :greeting do
      name = params(ctx)["name"] || "stranger"

      if params(ctx)["loud"] == "true" do
        String.upcase("hello #{name}")
      else
        "hello #{name}"
      end
    end
  end
end
