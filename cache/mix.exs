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

  def application do
    [
      mod: {Cache.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:appsignal, "~> 2.8"},
      {:appsignal_phoenix, "~> 2.7.0"},
      {:bandit, "~> 1.8"},
      {:briefly, "~> 0.5", only: :test},
      {:broadway, "~> 1.0"},
      {:cachex, "~> 3.6"},
      {:off_broadway_memory, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.17"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:guardian, "~> 2.3"},
      {:hackney, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:jose, git: "https://github.com/jtdowney/erlang-jose.git", branch: "fix-otp28-compatibility", override: true},
      {:mimic, "~> 1.7", only: :test},
      {:oban, "~> 2.17"},
      {:oban_web, "~> 2.10"},
      {:open_api_spex, "~> 3.18"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug, "~> 1.18"},
      {:plug_cowboy, "~> 2.7"},
      {:prom_ex, "~> 1.10"},
      {:req, "~> 0.1"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sweet_xml, "~> 0.7"},
      {:uuid_v7, "~> 0.6"},
      {:ymlr, "~> 5.0"},
      {:tuist_common, path: "../tuist_common"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
