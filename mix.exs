defmodule Tuist.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: [:prod, :stag, :can] |> Enum.member?(Mix.env()),
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tuist.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "credo"]
  defp elixirc_paths(:dev), do: ["lib", "credo"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.12"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:bamboo, "~> 2.3.0"},
      {:finch, "~> 0.18"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.24"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:appsignal, "~> 2.0"},
      {:appsignal_phoenix, "~> 2.0"},
      {:castore, "~> 1.0"},
      {:uniq, "~> 0.6"},
      {:encrypted_secrets, "~> 0.3.0"},
      {:configparser_ex, "~> 4.0"},
      {:sweet_xml, "~> 0.7"},
      {:number, "~> 1.0"},
      {:mimic, "~> 1.7", only: :test},
      {:open_api_spex, "~> 3.18"},
      {:ymlr, "~> 2.0"},
      {:poison, "~> 5.0"},
      {:oban, "~> 2.17"},
      {:bcrypt_elixir, "~> 3.0"},
      {:stripity_stripe, "~> 3.1"},
      {:rustler, "~> 0.34.0", override: true},
      {:ueberauth, "~> 0.10.8"},
      {:ueberauth_github, "~> 0.8"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_okta, "~> 1.0"},
      {:req, "~> 0.5.0"},
      {:telemetry_test, "~> 0.1.2"},
      {:timescale, "~> 0.1.0"},
      {:flop, "~> 0.25.0"},
      {:timex, "~> 3.7"},
      {:prom_ex, git: "https://github.com/akoutmos/prom_ex", branch: "master"},
      {:ranch, "~> 2.1.0", override: true},
      {:hammer, "~> 6.0"},
      {:memoize, "~> 1.4"},
      {:guardian, "~> 2.3"},
      {:guardian_db, "~> 3.0"},
      {:uuidv7, "~> 0.2"},
      # OpenTelemetry
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_telemetry, "~> 1.1"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.7"},
      {:opentelemetry_phoenix, "~> 1.2"},
      {:opentelemetry_bandit, "~> 0.1.4"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_oban, "~> 1.1"},
      {:opentelemetry_req, "~> 0.2.0"},
      {:opentelemetry_finch, "~> 0.2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.create": ["db.create"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.load", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild app", "esbuild marketing"],
      "assets.deploy": [
        "esbuild app --minify",
        "esbuild marketing --minify",
        "phx.digest"
      ]
    ]
  end
end
