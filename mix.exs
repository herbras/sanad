defmodule Sanad.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/herbras/sanad"

  def project do
    [
      app: :sanad,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: escript(),
      description: "Elixir rewrite of Shopify Roast — structured AI workflows",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :telemetry],
      mod: {Sanad.Application, []}
    ]
  end

  defp package do
    [
      name: "sanad",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Upstream (Shopify Roast)" => "https://github.com/Shopify/roast"
      },
      # Planning docs stay out of the package; tutorials and examples go in,
      # because they are what a new reader actually needs.
      files: ~w(lib examples tutorial mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md" | tutorial_extras()],
      groups_for_extras: [Tutorial: ~r{tutorial/}]
    ]
  end

  # Every tutorial chapter is a README.md, so each needs its own title or
  # HexDocs shows nine identical entries.
  defp tutorial_extras do
    "tutorial/**/README.md"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      {String.to_atom(path), [title: extra_title(path), filename: extra_filename(path)]}
    end)
  end

  # Nine files all named README.md would fight over readme.html, and the
  # project's own README would lose.
  defp extra_filename("tutorial/README.md"), do: "tutorial"

  defp extra_filename(path) do
    "tutorial-" <> (path |> Path.dirname() |> Path.basename() |> String.replace("_", "-"))
  end

  defp extra_title("tutorial/README.md"), do: "Tutorial: daftar isi"

  defp extra_title(path) do
    path
    |> Path.dirname()
    |> Path.basename()
    |> String.split("_", parts: 2)
    |> case do
      [number, rest] -> "Bab #{number} - #{String.replace(rest, "_", " ")}"
      [other] -> other
    end
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
      {:plug, "~> 1.16", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
