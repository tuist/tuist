# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# esbuild
config :esbuild,
  version: "0.17.11",
  app: [
    args:
      ~w(app.js --bundle --target=es2017 --outfile=../../priv/static/app/assets/bundle.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets/app", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  marketing: [
    args:
      ~w(marketing.js --bundle --target=es2017 --outfile=../../priv/static/marketing/assets/bundle.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets/marketing", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  apidocs: [
    args:
      ~w(apidocs.js --bundle --target=es2017 --outfile=../../priv/static/apidocs/assets/bundle.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets/apidocs", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  storybook: [
    args:
      ~w(storybook.js --bundle --target=es2017 --outfile=../../priv/static/storybook/assets/bundle.js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets/storybook", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tuist,
  ecto_repos: [Tuist.Repo],
  generators: [timestamp_type: :utc_datetime]

config :tuist, TuistWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TuistWeb.ErrorHTML, json: TuistWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tuist.PubSub,
  live_view: [signing_salt: "laTbtzV8"]

config :tuist, :urls,
  production: "https://tuist.dev",
  contact: "mailto:contact@tuist.dev",
  grafana_dashboard:
    "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9",
  slack: "https://slack.tuist.dev",
  bluesky: "https://bsky.app/profile/tuist.dev",
  github: "https://github.com/tuist",
  github_issues: "https://github.com/tuist/tuist/issues",
  mastodon: "https://fosstodon.org/@tuist",
  linkedin: "https://www.linkedin.com/company/tuistio",
  newsletter: "https://lists.tuist.dev/subscription/form",
  podcast: "https://podcast.tuist.dev",
  peertube: "https://videos.tuist.dev",
  status: "https://status.tuist.dev",
  get_started: "https://docs.tuist.dev",
  forum: "https://community.tuist.dev",
  documentation: "https://docs.tuist.dev",
  app_lifecycle_phase_start: "https://docs.tuist.dev/guides/start/new-project",
  app_lifecycle_phase_develop: "https://docs.tuist.dev/guides/develop/projects",
  app_lifecycle_phase_share: "https://docs.tuist.dev/guides/share/previews",
  app_lifecycle_phase_measure: "https://docs.tuist.dev/server/introduction/why-a-server",
  shop: "https://shop.tuist.dev"

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tuist, Tuist.Mailer, adapter: Bamboo.LocalAdapter

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban

# Tuist.Slack.InternalDailyReportWorker

config :tuist, Oban,
  repo: Tuist.Repo,
  notifier: Oban.Notifiers.PG,
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

config :flop, repo: Tuist.Repo

config :guardian, Guardian.DB,
  repo: Tuist.Repo,
  schema_name: "tokens",
  token_types: ["refresh"]

config :tuist, :blocked_handles, [
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

config :tuist, Tuist.Cache,
  # Max 1 million entries in cache
  max_size: 1_000_000,
  # Max 2 GB of memory
  allocated_memory: 2_000_000_000,
  # GC min timeout: 10 sec
  gc_cleanup_min_timeout: :timer.seconds(10),
  # GC max timeout: 10 min
  gc_cleanup_max_timeout: :timer.minutes(10)

config :excellent_migrations, start_after: "20240926093919"

# Error tracker
config :error_tracker,
  repo: Tuist.Repo,
  enabled: false,
  otp_app: :tuist,
  ignorer: Tuist.ErrorTracker.Ignorer,
  # 1 week
  plugins: [{ErrorTracker.Plugins.Pruner, max_age: :timer.hours(24 * 7)}]

config :mime, :types, %{
  "application/vnd.swift.registry.v1+json" => ["swift-registry-v1-json"],
  "application/vnd.swift.registry.v1+zip" => ["swift-registry-v1-zip"],
  "application/vnd.swift.registry.v1+swift" => ["swift-registry-v1-api"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Money
config :money,
  default_currency: :USD

# Flags
config :fun_with_flags, :cache, enabled: true, ttl: 600

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Tuist.Repo,
  ecto_table_name: "feature_flags",
  ecto_primary_key_type: :binary_id

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Tuist.PubSub
