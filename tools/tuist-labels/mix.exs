defmodule TuistLabels.MixProject do
  use Mix.Project

  def project do
    [app: :tuist_labels, version: "0.1.0", elixir: "~> 1.18", deps: deps()]
  end

  def application do
    [mod: {TuistLabels.Application, []}, extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:noora, path: "../../noora"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:floki, "~> 0.36", only: :test}
    ]
  end
end
