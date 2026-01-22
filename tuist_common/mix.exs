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

  defp elixirc_paths(:test), do: ["lib", "test/support", "credo"]
  defp elixirc_paths(:dev), do: ["lib", "credo"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:appsignal, "~> 2.8"},
      {:bandit, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.0"},
      {:plug, "~> 1.14"},
      {:req, "~> 0.5"},
      {:mimic, "~> 1.7", only: :test}
    ]
  end
end
