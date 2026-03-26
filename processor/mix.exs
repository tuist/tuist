defmodule Processor.MixProject do
  use Mix.Project

  def project do
    [
      app: :processor,
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
      mod: {Processor.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:briefly, "~> 0.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sts, "~> 2.2"},
      {:loki_logger_handler, "~> 0.2"},
      {:mimic, "~> 2.0", only: :test},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_finch, "~> 0.2"},
      {:opentelemetry_logger_metadata, "~> 0.1"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug, "~> 1.18"},
      {:prom_ex, git: "https://github.com/pepicrft/prom_ex", branch: "finch"},
      {:hackney, "~> 1.8"},
      {:req, "~> 0.5"},
      {:sentry, "~> 11.0.4"},
      {:sweet_xml, "~> 0.7"},
      {:tuist_common, path: "../tuist_common"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
