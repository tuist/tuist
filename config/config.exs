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

config :ueberauth, Ueberauth,
  base_path: "/users/auth",
  providers: [
    github: {Ueberauth.Strategy.Github, []},
    google: {Ueberauth.Strategy.Google, []},
    okta: {Ueberauth.Strategy.Okta, []}
  ]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :flop, repo: TuistCloud.Repo

config :guardian, Guardian.DB,
  repo: TuistCloud.Repo,
  schema_name: "tokens",
  token_types: ["refresh"]

config :tuist_cloud, :blocked_handles, [
  "admin",
  "settings",
  "docs",
  "api",
  "login",
  "logout",
  "signup",
  "register",
  "dashboard",
  "profile",
  "account",
  "billing",
  "payments",
  "subscriptions",
  "help",
  "support",
  "faq",
  "terms",
  "privacy",
  "cookie",
  "legal",
  "about",
  "contact",
  "feedback",
  "status",
  "system",
  "blog",
  "news",
  "newsletter",
  "announcements",
  "features",
  "pricing",
  "plan",
  "plans",
  "upgrade",
  "downgrade",
  "cancel",
  "home",
  "index",
  "search",
  "explore",
  "discover",
  "notifications",
  "messages",
  "inbox",
  "mail",
  "team",
  "organization",
  "groups",
  "projects",
  "tasks",
  "reports",
  "analytics",
  "stats",
  "metrics",
  "integrations",
  "apps",
  "marketplace",
  "store",
  "shop",
  "cart",
  "checkout",
  "orders",
  "invoices",
  "downloads",
  "uploads",
  "files",
  "media",
  "images",
  "videos",
  "users",
  "members",
  "roles",
  "permissions",
  "security",
  "ssl",
  "oauth",
  "auth",
  "2fa",
  "mfa",
  "verification",
  "confirm",
  "reset",
  "recover",
  "backup",
  "restore",
  "import",
  "export",
  "webhooks",
  "developer",
  "console",
  "logs",
  "health",
  "maintenance",
  "changelog",
  "roadmap",
  "beta",
  "alpha",
  "test",
  "staging",
  "production",
  "www",
  "app",
  "web",
  "mobile",
  "desktop",
  "sitemap",
  "robots",
  "rss",
  "feed",
  "careers",
  "jobs"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
