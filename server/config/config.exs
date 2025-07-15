# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :boruta, Boruta.Oauth,
  repo: Tuist.Repo,
  contexts: [
    resource_owners: Tuist.OAuth.ResourceOwners,
    clients: Tuist.OAuth.Clients,
    access_tokens: Tuist.OAuth.AccessTokens
  ],
  token_generator: Tuist.OAuth.TokenGenerator

config :ecto_ch,
  default_table_engine: "MergeTree"

# Error tracker
config :error_tracker,
  repo: Tuist.Repo,
  enabled: false,
  otp_app: :tuist,
  ignorer: Tuist.ErrorTracker.Ignorer,
  # 1 week
  plugins: [{ErrorTracker.Plugins.Pruner, max_age: to_timeout(week: 1)}]

# esbuild
config :esbuild,
  version: "0.25.2",
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
  ]

config :excellent_migrations, start_after: "20240926093919"

config :flop, repo: Tuist.Repo

# Flags
config :fun_with_flags, :cache, enabled: true, ttl: 600

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Tuist.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Tuist.Repo,
  ecto_table_name: "feature_flags",
  ecto_primary_key_type: :binary_id

config :guardian, Guardian.DB,
  repo: Tuist.Repo,
  schema_name: "guardian_tokens",
  token_types: ["refresh"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{
  "application/vnd.swift.registry.v1+json" => ["swift-registry-v1-json"],
  "application/vnd.swift.registry.v1+zip" => ["swift-registry-v1-zip"],
  "application/vnd.swift.registry.v1+swift" => ["swift-registry-v1-api"]
}

# Money
config :money,
  default_currency: :USD

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban
config :tuist, Oban,
  repo: Tuist.Repo,
  notifier: Oban.Notifiers.PG,
  queues: [default: 10]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tuist, Tuist.Mailer, adapter: Bamboo.LocalAdapter

config :tuist, TuistWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TuistWeb.ErrorHTML, json: TuistWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tuist.PubSub,
  live_view: [signing_salt: "laTbtzV8"]

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

config :tuist, :urls,
  production: "https://tuist.dev",
  contact: "mailto:contact@tuist.dev",
  grafana_dashboard: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9",
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
  feature_generated_projects: "https://docs.tuist.dev/en/guides/features/cache",
  feature_cache: "https://docs.tuist.dev/en/guides/features/cache",
  feature_previews: "https://docs.tuist.dev/en/guides/features/previews",
  feature_insights: "https://docs.tuist.dev/en/guides/features/insights",
  shop: "https://shop.tuist.dev"

config :ueberauth, Ueberauth,
  base_path: "/users/auth",
  providers: [
    github: {Ueberauth.Strategy.Github, []},
    google: {Ueberauth.Strategy.Google, []},
    apple: {Ueberauth.Strategy.Apple, [callback_methods: ["POST"], default_scope: "email"]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
