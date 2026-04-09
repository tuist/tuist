defmodule Noora.MixProject do
  use Mix.Project

  def project do
    [
      app: :noora,
      description: "A component library for Phoenix LiveView applications",
      version: "0.79.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:timex, "~> 3.7"},
      {:deep_merge, "~> 1.0"},
      {:uniq, "~> 0.6"},
      {:jason, "~> 1.4"},
      {:styler, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "noora",
      maintainers: ["Christoph Schmatzler", "Marek Fořt", "Pedro Piñera", "Asmit Malakannawar"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tuist/tuist"},
      files: [
        "lib",
        "mix.exs",
        "js",
        "css",
        "package.json",
        "priv",
        "README.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "Noora",
      extras: ["CHANGELOG.md"]
    ]
  end
end
