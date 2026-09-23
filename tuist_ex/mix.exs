defmodule TuistEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist_ex,
      version: "0.1.0",
      description: "Build and test instrumentation for Elixir projects",
      elixir: "~> 1.18",
      deps: [
        {:jason, "~> 1.4"},
        {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
        {:mimic, "~> 2.0", only: :test},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false}
      ],
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/tuist/tuist/tree/main/tuist_ex"},
        files: ["lib", "mix.exs", "README.md", "LICENSE"]
      ],
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  def application, do: [extra_applications: [:inets, :ssl, :public_key, :crypto]]
end
