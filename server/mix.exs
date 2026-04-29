defmodule Tuist.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [check_cwd: false],
      test_paths: ["test"],
      start_permanent: Enum.member?([:prod, :stag, :can], Mix.env()),
      releases: releases(),
      aliases: aliases(),
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tuist.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :ssh]
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
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.12"},
      {:db_connection, "~> 2.9", override: true},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.6.1", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_view, "~> 2.0"},
      {:floki, ">= 0.33.0"},
      {:html2markdown, "~> 0.3.1"},
      {:phoenix_live_dashboard, "~> 0.8.4"},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.1.1", sparse: "optimized", app: false, compile: false, depth: 1},
      {:bamboo, "~> 2.4"},
      {:finch, "~> 0.21.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0", override: true},
      {:jason, "~> 1.2"},
      {:libcluster, "~> 3.5"},
      # Using fork with client disconnect detection during body read timeouts
      # PR: https://github.com/mtrudel/bandit/pull/564
      {:bandit, git: "https://github.com/tuist/bandit", branch: "detect-client-disconnect-on-timeout", override: true},
      {:credo, "== 1.7.13", only: [:dev, :test], runtime: false},
      {:sentry, "~> 11.0.4"},
      {:tower, "0.8.0"},
      {:tower_opentelemetry, "~> 0.2.0"},
      {:hackney, "~> 1.8"},
      {:castore, "~> 1.0.12"},
      {:uniq, "~> 0.6"},
      {:encrypted_secrets, "~> 0.3.0"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3,
       git: "https://github.com/tuist/ex_aws_s3/", ref: "7f3278bef49cc3fa6b4138a4077804d328a41c9c", override: true},
      {:ex_cldr, "~> 2.37"},
      {:ex_cldr_numbers, "~> 2.38"},
      {:number, "~> 1.0"},
      {:mimic, "~> 2.0", only: :test},
      {:ymlr, "~> 5.0"},
      {:open_api_spex, "~> 3.18"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:bcrypt_elixir, "~> 3.0"},
      {:stripity_stripe, "~> 3.1"},
      {:ueberauth, "~> 0.10.8"},
      {:ueberauth_github, "~> 0.8"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_apple, "~> 0.6"},
      {:req, "~> 0.5.6"},
      {:req_telemetry, "~> 0.1.1"},
      {:telemetry_test, "~> 0.1.2"},
      {:sweet_xml, "~> 0.7.4"},
      {:flop, "~> 0.26.0"},
      {:timex, "~> 3.7.13"},
      {:prom_ex, git: "https://github.com/pepicrft/prom_ex", branch: "finch"},
      {:ranch, "~> 2.2.0", override: true},
      {:hammer, "~> 7.0"},
      {:guardian, "~> 2.3"},
      {:guardian_db, "~> 3.0"},
      {:uuidv7, "~> 1.0"},
      {:decorator, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:ecto_psql_extras, "~> 0.8.1"},
      {:cachex, "~> 4.0.4"},
      {:excellent_migrations, "~> 0.1.8"},
      {:ex_aws_sts, "~> 2.2"},
      {:qr_code, "~> 3.2.0"},
      {:nimble_publisher, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      {:plug_cowboy, "~> 2.7"},
      {:retry, "~> 0.19"},
      {:redirect, "~> 0.4.0"},
      {:let_me, "~> 1.2"},
      {:emcp, "~> 0.3.2"},
      {:ua_parser, "~> 1.8"},
      {:money, "~> 1.12"},
      {:image, "~> 0.60"},
      {:boundary, "~> 0.10", runtime: false},
      {:makeup, "~> 1.2", override: true},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:solid, "~> 1.0"},
      {:plug_minify_html, "~> 0.1.0"},
      {:briefly, "~> 0.5.0"},
      {:fun_with_flags, "~> 1.13.0"},
      {:fun_with_flags_ui, "~> 1.1.0"},
      {:esbuild, "~> 0.10"},
      {:deep_merge, "~> 1.0"},
      {:broadway, "~> 1.2"},
      {:off_broadway_memory, "~> 1.2"},
      {:broadway_dashboard, "~> 0.4.1"},
      {:zxcvbn, "~> 0.3.0"},
      {:styler, "~> 1.8", only: [:dev, :test], runtime: false},
      {:redix, "~> 1.1"},
      {:redis_mutex, "~> 1.1"},
      {:hammer_backend_redis, "~> 7.0"},
      {:ch, git: "https://github.com/tuist/ch.git", branch: "codex/experimental-transactions", override: true},
      {:ecto_ch, git: "https://github.com/tuist/ecto_ch.git", branch: "codex/experimental-transactions", override: true},
      {:noora, path: "../noora"},
      {:zstream, "~> 0.6"},
      {:cloak_ecto, "~> 1.3.0"},
      {:boruta, git: "https://github.com/malach-it/boruta_auth", branch: "master"},
      {:minio_server, github: "LostKobrakai/minio_server", only: :dev},
      {:tuist_common, path: "../tuist_common"},
      {:slipstream, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:peep, "4.2.1", override: true},
      {:langchain, "~> 0.4"},
      {:earmark, "~> 1.4"},
      {:mdex, "~> 0.11"},
      {:mdex_mermaid, "~> 0.3"},
      {:html_sanitize_ex, "~> 1.4"},
      {:posthog, "~> 1.0", runtime: false},
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
      {:loki_logger_handler, "~> 0.2"},
      {:xcode_processor, path: "../xcode_processor", runtime: false},
      {:tidewave, "~> 0.5", only: :dev},
      {:carta, "~> 0.2.0"},
      {:browse_chrome, "~> 0.4.0"},
      {:browse, "~> 0.5.0", override: true},
      {:muontrap, "~> 1.7", override: true}
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
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "run priv/repo/timezone.exs",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": [
        "ecto.drop",
        "ecto.create",
        "run priv/repo/timezone.exs",
        "ecto.load",
        "ecto.migrate"
      ],
      test: ["ecto.create --quiet", "run priv/repo/timezone.exs", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "cmd --cd .. pnpm install --filter noora",
        "esbuild.install --if-missing"
      ],
      "assets.build": [
        "cmd --cd ../noora pnpm run build",
        "esbuild app",
        "esbuild marketing",
        "esbuild docs",
        "esbuild apidocs"
      ],
      "assets.deploy": [
        "esbuild marketing --minify",
        "esbuild docs --minify",
        "esbuild app --minify",
        "esbuild apidocs --minify",
        "phx.digest"
      ]
    ]
  end

  defp releases do
    [tuist: []]
  end
end
