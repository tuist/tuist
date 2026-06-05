import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :tuist_jit,
  ecto_repos: [TuistJit.Repo],
  generators: [timestamp_type: :utc_datetime]

config :tuist_jit, TuistJit.Repo,
  migration_timestamps: [type: :utc_datetime]

config :tuist_jit, TuistJitWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TuistJitWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TuistJit.PubSub

config :tuist_jit, Oban,
  engine: Oban.Engines.Basic,
  queues: [revert: 1],
  repo: TuistJit.Repo

import_config "#{config_env()}.exs"
