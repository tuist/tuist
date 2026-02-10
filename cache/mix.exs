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
      {:sentry, "~> 11.0.4"},
      {:hackney, "~> 1.8"},
      # Using fork with client disconnect detection during body read timeouts
      # PR: https://github.com/mtrudel/bandit/pull/564
      {:bandit, git: "https://github.com/tuist/bandit", branch: "detect-client-disconnect-on-timeout", override: true},
      {:briefly, "~> 0.5"},
      {:broadway, "~> 1.0"},
      {:cachex, "~> 3.6"},
      {:off_broadway_memory, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.17"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:guardian, "~> 2.3"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
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
      {:req, "~> 0.5"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sweet_xml, "~> 0.7"},
      {:uuid_v7, "~> 0.6"},
      {:ymlr, "~> 5.0"},
      {:tuist_common, path: "../tuist_common"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto,
       github: "open-telemetry/opentelemetry-erlang-contrib", sparse: "instrumentation/opentelemetry_ecto"},
      {:opentelemetry_finch, "~> 0.2"},
      {:opentelemetry_logger_metadata, "~> 0.1"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_broadway, "~> 0.3"},
      {:loki_logger_handler, "~> 0.2"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
