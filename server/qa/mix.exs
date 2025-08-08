defmodule QA.MixProject do
  use Mix.Project

  def project do
    [
      app: :qa,
      version: "0.1.0",
      build_path: "../_build",
      deps_path: "../deps",
      lockfile: "../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {QA, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.0"},
      {:langchain, git: "https://github.com/brainlid/langchain", branch: "main"},
      {:briefly, "~> 0.5.0"}
    ]
  end

  defp releases do
    [
      qa: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
