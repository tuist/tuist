defmodule TuistOps.MixProject do
  use Mix.Project

  def project do
    [
      app: :tuist_ops,
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
      mod: {TuistOps.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:floki, ">= 0.30.0", only: :test},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:mimic, "~> 1.7", only: :test},
      {:noora, path: "../noora"},
      {:oban, "~> 2.18"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug, "~> 1.18"},
      {:postgrex, "~> 0.20"},
      {:req, "~> 0.5"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # Noora ships a prebuilt bundle in its priv/static; we don't run a
      # Tailwind/esbuild pass here, just copy the bundle into our static
      # dir so Plug.Static can serve it.
      "assets.setup": ["cmd mkdir -p priv/static/assets", &copy_noora_assets/1],
      "assets.build": [&copy_noora_assets/1],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp copy_noora_assets(_) do
    File.mkdir_p!("priv/static/assets")

    for file <- ~w(noora.css noora.js) do
      File.cp!(Path.join("../noora/priv/static", file), Path.join("priv/static/assets", file))
    end
  end
end
