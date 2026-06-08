import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :tuist_ops,
  ecto_repos: [TuistOps.Repo],
  generators: [timestamp_type: :utc_datetime]

config :tuist_ops, TuistOps.Repo,
  migration_timestamps: [type: :utc_datetime]

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
  queues: [revert: 1],
  repo: TuistOps.Repo

import_config "#{config_env()}.exs"
