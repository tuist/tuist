defmodule Cache.MixProject do
  use Mix.Project

  def project do
    [
      app: :cache,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  def application do
    [
      mod: {Cache.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:briefly, "~> 0.5", only: :test},
      {:cachex, "~> 3.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.17"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:mimic, "~> 1.7", only: :test},
      {:oban, "~> 2.17"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_pubsub, "~> 2.1"},
      {:req, "~> 0.1"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sweet_xml, "~> 0.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
