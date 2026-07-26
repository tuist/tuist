defmodule TuistRegistry.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist_registry,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [check_cwd: false],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {TuistRegistry.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:sentry, "~> 11.0.4"},
      {:hackney, "~> 1.8"},
      {:bandit, git: "https://github.com/tuist/bandit", branch: "detect-client-disconnect-on-timeout", override: true},
      {:cachex, "~> 3.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:configparser_ex, "~> 5.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sts, "~> 2.2"},
      {:mimic, "~> 1.7", only: :test},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug, "~> 1.18"},
      {:plug_cowboy, "~> 2.7"},
      {:prom_ex, git: "https://github.com/pepicrft/prom_ex", branch: "finch"},
      {:req, "~> 0.5"},
      {:req_fuse, "~> 0.3.2"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sweet_xml, "~> 0.7"},
      {:uuid_v7, "~> 0.6"},
      {:ymlr, "~> 5.0"},
      {:tuist_common, path: "../tuist_common"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_finch, "~> 0.2"},
      {:opentelemetry_logger_metadata, "~> 0.1"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:loki_logger_handler, "~> 0.2"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
