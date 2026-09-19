defmodule Sanad.MixProject do
  use Mix.Project

  def project do
    [
      app: :sanad,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: escript(),
      description: "Elixir rewrite of Shopify Roast — structured AI workflows"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :telemetry],
      mod: {Sanad.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp escript do
    [main_module: Sanad.CLI, name: "sanad"]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", only: :test}
    ]
  end
end
