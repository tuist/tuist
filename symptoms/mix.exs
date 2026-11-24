defmodule Symptoms.MixProject do
  use Mix.Project

  def project do
    [
      app: :symptoms,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # Support modules under test/ are required by test_helper.exs, not run.
      test_ignore_filters: [&String.starts_with?(&1, "test/support/"), &String.ends_with?(&1, ".ex")]
    ]
  end

  def application do
    [
      mod: {Symptoms.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:jason, "~> 1.4"},
      {:mimic, "~> 1.10", only: :test},
      {:oban, "~> 2.19"},
      {:phoenix, "~> 1.7.12"},
      {:plug, "~> 1.18"},
      {:postgrex, "~> 0.20"},
      {:req, "~> 0.5"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:tz, "~> 0.28"}
    ]
  end

  # `mix test` does not create the database: pure-module tests run without
  # PostgreSQL. Run `mix ecto.setup` and `mix test --include db` for DB tests.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
