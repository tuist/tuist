defmodule LuftServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :luft_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # Build and test insights go to the hosted tuist/luft-server project
      # through `mix tuist.test` (see `.github/workflows/luft-server.yml`).
      tuist: [project: "tuist/luft-server"]
    ]
  end

  def application do
    [
      mod: {LuftServer.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  def cli do
    [preferred_envs: ["tuist.test": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_ecto, "~> 4.4"},
      {:plug, "~> 1.18"},
      {:postgrex, "~> 0.20"},
      {:req, "~> 0.5"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:tuist_ex, path: "../tuist_ex", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
