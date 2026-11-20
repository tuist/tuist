import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :sandbox_id]

config :luft_server, LuftServer.Repo, migration_timestamps: [type: :utc_datetime]

config :luft_server, LuftServerWeb.Endpoint,
  url: [host: "localhost"],
  pubsub_server: LuftServer.PubSub,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: LuftServerWeb.ErrorJSON], layout: false]

config :luft_server,
  ecto_repos: [LuftServer.Repo],
  # The Tuist server Luft signs people in with, the OpenID Provider. Its
  # metadata is discovered from `<issuer>/.well-known/openid-configuration`.
  tuist_issuer: "https://tuist.dev"

config :phoenix, :json_library, Jason

config :luft_server, Oban,
  repo: LuftServer.Repo,
  queues: [threads: 10, push: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", LuftServer.Threads.RecoveryWorker},
       {"0 * * * *", LuftServer.Notifications.PruneWorker}
     ]}
  ]

config :luft_server, LuftServer.Agents.Runner,
  kinds: %{
    "thread" => LuftServer.Threads.Host,
    "thread_exit_watch" => LuftServer.Threads.ExitWatchWorker
  }

config :boruta, Boruta.Oauth,
  repo: LuftServer.Repo,
  issuer: "luft",
  cache_backend: LuftServer.OAuth.AuthoritativeCache,
  max_ttl: [authorization_code: 120],
  contexts: [
    clients: LuftServer.OAuth.Clients,
    resource_owners: LuftServer.OAuth.ResourceOwners
  ],
  token_generator: LuftServer.OAuth.TokenGenerator

import_config "#{config_env()}.exs"
