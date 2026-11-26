defmodule LuftServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :luft_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # Build and test insights go to the hosted tuist/luft-server project
      # through `mix tuist.test` (see `.github/workflows/luft-server.yml`).
      tuist: [project: "tuist/luft-server"]
    ]
  end

  def application do
    [
      mod: {LuftServer.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  def cli do
    [preferred_envs: ["tuist.test": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:boruta,
       git: "https://github.com/malach-it/boruta_auth",
       ref: "f72db0b1a85b3ed1bc4e2b1f5ea77421fa92c7d4"},
      {:condukt, path: "../condukt"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.2"},
      {:ecto_sql, "~> 3.10"},
      {:ex_json_schema, "~> 0.11"},
      {:grpc, "~> 0.11.5"},
      {:gun, "~> 2.8"},
      {:jason, "~> 1.4"},
      {:javex, "~> 0.2.0"},
      {:jose, "~> 1.11"},
      {:muontrap, "~> 1.8"},
      {:oban, "~> 2.21.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.4"},
      {:plug, "~> 1.18"},
      {:postgrex, "~> 0.20"},
      {:protobuf, "~> 0.17.1"},
      {:req, "~> 0.5"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:websock_adapter, "~> 0.5"},
      {:tuist_ex, path: "../tuist_ex", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
