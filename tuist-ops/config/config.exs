import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :tuist_ops,
  ecto_repos: [TuistOps.Repo],
  generators: [timestamp_type: :utc_datetime]

config :tuist_ops, TuistOps.Repo, migration_timestamps: [type: :utc_datetime]

config :tuist_ops, TuistOpsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TuistOpsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TuistOps.PubSub

config :tuist_ops, Oban,
  engine: Oban.Engines.Basic,
  queues: [revert: 1, preview_monitor: 1],
  repo: TuistOps.Repo

# Bundle the operator UI (Noora + the dead-view hook loader) with esbuild.
# Noora resolves from the Hex package's prebuilt priv/static/noora.js via
# NODE_PATH, so there is no node/npm step and nothing built is committed.
config :esbuild,
  version: "0.25.4",
  tuist_ops: [
    args: ~w(js/app.js --bundle --target=es2022 --format=esm --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

import_config "#{config_env()}.exs"
