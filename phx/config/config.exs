# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tuist_cloud,
  ecto_repos: [TuistCloud.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
host =
  cond do
    config_env() == :stag -> "cloud-staging.tuist.io"
    config_env() == :can -> "cloud-canary.tuist.io"
    config_env() == :prod -> "cloud.tuist.io"
    true -> "localhost"
  end

config :tuist_cloud, TuistCloudWeb.Endpoint,
  url: [host: host],
  check_origin: [
    "https://cloud-staging.tuist.io",
    "https://cloud-canary.tuist.io",
    "https://cloud.tuist.io"
  ],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TuistCloudWeb.ErrorHTML, json: TuistCloudWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TuistCloud.PubSub,
  live_view: [signing_salt: "laTbtzV8"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tuist_cloud, TuistCloud.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  tuist_cloud: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/v2/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban
config :tuist_cloud, Oban,
  repo: TuistCloud.Repo,
  queues: [default: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"@hourly", TuistCloud.CommandEvents.UpdateCacheEventCountWorker}
     ]}
  ]

base_url =
  cond do
    config_env() == :prod -> "https://cloud.tuist.io/v2/users/auth"
    config_env() == :stag -> "https://cloud-staging.tuist.io/v2/users/auth"
    config_env() == :can -> "https://cloud-canary.tuist.io/v2/users/auth"
    true -> "http://127.0.0.1:4000/v2/users/auth"
  end

config :ueberauth, Ueberauth,
  base_path: "/v2/users/auth",
  providers: [
    github: {Ueberauth.Strategy.Github, [callback_url: "#{base_url}/github/callback"]},
    google:
      {Ueberauth.Strategy.Google,
       [
         callback_url: "#{base_url}/google/callback"
       ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
