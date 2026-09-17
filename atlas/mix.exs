defmodule Atlas.MixProject do
  use Mix.Project

  def project do
    [
      app: :atlas,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Atlas.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.4"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:mdex, "~> 0.13.0"},
      {:req, "~> 0.6"},
      {:server_sent_events, "~> 1.0"},
      {:ex_aws_auth, "~> 1.3"},
      {:sweet_xml, "~> 0.7"},
      {:toml, "~> 0.7"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0", override: true},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:noora, path: "../noora"},
      {:money, "~> 1.14"},
      {:forex, "~> 1.1"},
      {:flow, "~> 1.2"},
      {:flop, "~> 0.26.0"},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      {:uniq, "~> 0.6"},
      {:let_me, "~> 3.0"},
      {:cloak, "~> 1.1"},
      {:cloak_ecto, "~> 1.3"},
      {:muontrap, "~> 1.7"},
      {:briefly, "~> 0.5"},
      {:xlsx_reader, "~> 0.8"},
      {:mimic, "~> 2.0", only: :test},
      {:tidewave, "~> 0.9", only: :dev},
      {:hammer, "~> 7.0"},
      {:helmsman, "~> 0.5.0"},
      {:condukt, github: "tuist/condukt", tag: "1.7.0", override: true},
      {:mail, "~> 0.5"},
      {:multipart, "~> 0.4"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:sentry, "~> 13.0"},
      {:guardian, "~> 2.3"},
      {:guardian_db, "~> 3.0"},
      {:jose, "~> 1.11"},
      # Pinned to the upstream fix for intermittent missing Model Context Protocol tool-call responses.
      # Revert to a Hex version once the fix is released.
      {:emcp, github: "addstar34/emcp", ref: "c687e279cf4f550f69934549a1303312ed3a23b5", override: true},
      {:ex_json_schema, "~> 0.11"},
      {:browse, "~> 0.5"},
      {:browse_chrome, "~> 0.4"},
      {:boruta, git: "https://github.com/malach-it/boruta_auth", branch: "master"}
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
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "cmd --cd ../noora aube install",
        "esbuild.install --if-missing"
      ],
      "assets.build": [
        "cmd --cd ../noora aube run build",
        "compile",
        "esbuild atlas"
      ],
      "assets.deploy": [
        "esbuild atlas --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "credo", "test"]
    ]
  end
end
