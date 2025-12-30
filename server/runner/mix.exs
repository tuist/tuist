defmodule Runner.MixProject do
  use Mix.Project

  def project do
    [
      app: :runner,
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
      mod: {Runner, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.0"},
      {:langchain, git: "https://github.com/brainlid/langchain", branch: "main"},
      {:briefly, "~> 0.5.0"},
      {:slipstream, "~> 1.2.0"},
      {:web_driver_client, "~> 0.2.0"},
      {:sax_map, "~> 1.2"}
    ]
  end

  defp releases do
    [
      runner: [
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
