defmodule TuistCommon.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist_common,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:appsignal, "~> 2.8"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.14"},
      {:mimic, "~> 1.7", only: :test}
    ]
  end
end
