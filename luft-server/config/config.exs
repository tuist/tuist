import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :luft_server, LuftServer.Repo, migration_timestamps: [type: :utc_datetime]

config :luft_server, LuftServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: LuftServerWeb.ErrorJSON], layout: false]

config :luft_server,
  ecto_repos: [LuftServer.Repo],
  # The Tuist server Luft signs people in with, the OpenID Provider. Its
  # metadata is discovered from `<issuer>/.well-known/openid-configuration`.
  tuist_issuer: "https://tuist.dev"

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
