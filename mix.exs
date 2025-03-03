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
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tuist.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
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
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.33.0"},
      {:phoenix_live_dashboard, "~> 0.8.4"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:bamboo, "~> 2.3.0"},
      {:finch, "~> 0.19"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:appsignal, "~> 2.14"},
      # Fix hackney version until AppSignal lifts the Hackney version to 1.13.0
      # to address this issue https://github.com/appsignal/appsignal-elixir/issues/981
      {:hackney, "1.21.0"},
      {:appsignal_phoenix, "~> 2.5"},
      {:castore, "~> 1.0.12"},
      {:uniq, "~> 0.6"},
      {:encrypted_secrets, "~> 0.3.0"},
      {:ex_aws, "~> 2.5.5"},
      {:ex_aws_s3, "~> 2.5.5"},
      {:configparser_ex, "~> 4.0"},
      {:number, "~> 1.0"},
      {:mimic, "~> 1.11.0", only: :test},
      {:open_api_spex, "~> 3.18"},
      {:ymlr, "~> 2.0"},
      {:poison, "~> 5.0"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:bcrypt_elixir, "~> 3.0"},
      {:stripity_stripe, "~> 3.1"},
      {:ueberauth, "~> 0.10.8"},
      {:ueberauth_github, "~> 0.8"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_okta, "~> 1.0"},
      {:req, "~> 0.5.6"},
      {:req_telemetry, "~> 0.1.1"},
      {:telemetry_test, "~> 0.1.2"},
      {:sweet_xml, "~> 0.7.4"},
      {:timescale, "~> 0.1.0"},
      {:flop, "~> 0.26.0"},
      {:timex, "~> 3.7"},
      {:prom_ex, git: "https://github.com/akoutmos/prom_ex", branch: "master"},
      {:ranch, "~> 2.1.0", override: true},
      {:hammer, "~> 6.0"},
      {:guardian, "~> 2.3"},
      {:guardian_db, "~> 3.0"},
      {:uuidv7, "~> 1.0"},
      {:decorator, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:ecto_psql_extras, "~> 0.8.1"},
      {:cachex, "~> 4.0.2"},
      {:nebulex, "~> 2.6"},
      {:horde, "~> 0.8.0"},
      {:nebulex_adapters_horde, "~> 1.0"},
      {:error_tracker, "~> 0.5.0"},
      {:excellent_migrations, "~> 0.1.8"},
      {:ex_aws_sts, "~> 2.2"},
      {:qr_code, "~> 3.2.0"},
      {:nimble_publisher, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      {:reading_time, "~> 0.2.0"},
      {:plug_cowboy, "~> 2.7"},
      {:retry, "~> 0.18"},
      {:redirect, "~> 0.4.0"},
      {:let_me, "~> 1.2"},
      {:ua_parser, "~> 1.8"},
      {:money, "~> 1.12"},
      {:image, "~> 0.56.0"},
      {:boundary, "~> 0.10", runtime: false},
      {:makeup, "~> 1.2", override: true},
      {:phoenix_storybook, "~> 0.8.1"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:solid, "~> 0.17.1"},
      {:plug_minify_html, "~> 0.1.0"},
      {:briefly, "~> 0.5.0"},
      {:fun_with_flags, "~> 1.12.0"},
      {:fun_with_flags_ui, "~> 1.0.0"},
      {:esbuild, "~> 0.8"}
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
      "assets.build": ["esbuild app", "esbuild marketing", "esbuild apidocs", "esbuild storybook"],
      "assets.deploy": [
        "esbuild marketing --minify",
        "esbuild app --minify",
        "esbuild apidocs --minify",
        "esbuild storybook --minify",
        "phx.digest"
      ]
    ]
  end
end
