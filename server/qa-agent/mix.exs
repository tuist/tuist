defmodule QAAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :qa_agent,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {QAAgentCLI, []},
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:rambo, "~> 0.3"},
      {:langchain, "0.4.0-rc.1"},
      {:burrito, "~> 1.0"}
    ]
  end

  defp escript do
    [main_module: QAAgentCLI]
  end

  defp releases do
    [
      qa_agent: [
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
