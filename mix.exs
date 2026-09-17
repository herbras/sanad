defmodule Sanad.MixProject do
  use Mix.Project

  def project do
    [
      app: :sanad,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: "Elixir rewrite of Shopify Roast — structured AI workflows"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Sanad.Application, []}
    ]
  end

  defp escript do
    [main_module: Sanad.CLI, name: "sanad"]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", only: :test}
    ]
  end
end
