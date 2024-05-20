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

config :tuist_cloud, TuistCloudWeb.Endpoint,
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
config :tuist_cloud, TuistCloud.Mailer, adapter: Bamboo.LocalAdapter

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  tuist_cloud: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
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

# TuistCloud.Slack.InternalDailyReportWorker

config :tuist_cloud, Oban,
  repo: TuistCloud.Repo,
  queues: [default: 10]

base_url =
  cond do
    config_env() == :prod -> "https://cloud.tuist.io/users/auth"
    config_env() == :stag -> "https://cloud-staging.tuist.io/users/auth"
    config_env() == :can -> "https://cloud-canary.tuist.io/users/auth"
    true -> "http://127.0.0.1:8080/users/auth"
  end

config :ueberauth, Ueberauth,
  base_path: "/users/auth",
  providers: [
    github: {Ueberauth.Strategy.Github, []},
    google: {Ueberauth.Strategy.Google, []}
  ]

config :flop, repo: TuistCloud.Repo

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
