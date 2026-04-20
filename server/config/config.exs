# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# esbuild
noora_static_path = Path.expand("../../noora/priv/static", __DIR__)
node_modules_path = Path.expand("../node_modules", __DIR__)

config :bonny,
  operator_name: "tuist-runners",
  group: "tuist.dev",
  service_account_name: "tuist-runners",
  labels: %{"app.kubernetes.io/name" => "tuist-runners"},
  get_conn: {Tuist.Operator, :k8s_conn, []}

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

config :esbuild,
  version: "0.25.2",
  app: [
    args: [
      "app.js",
      "--bundle",
      "--target=es2017",
      "--outfile=../../priv/static/app/assets/bundle.js",
      "--external:/fonts/*",
      "--external:/images/*",
      "--alias:noora=#{noora_static_path}/noora.js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets/app", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  marketing: [
    args: [
      "marketing.js",
      "--bundle",
      "--loader:.svg=dataurl",
      "--loader:.jpg=dataurl",
      "--loader:.png=dataurl",
      "--loader:.webp=dataurl",
      "--target=es2017",
      "--outfile=../../priv/static/marketing/assets/bundle.js",
      "--external:/fonts/*",
      "--external:/images/*",
      "--alias:noora=#{noora_static_path}/noora.js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets/marketing", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  docs: [
    args: [
      "docs.js",
      "--bundle",
      "--loader:.svg=dataurl",
      "--loader:.jpg=dataurl",
      "--loader:.png=dataurl",
      "--loader:.webp=dataurl",
      "--target=es2017",
      "--outfile=../../priv/static/docs/assets/bundle.js",
      "--external:/fonts/*",
      "--external:/images/*",
      "--alias:noora=#{noora_static_path}/noora.js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets/docs", __DIR__),
    env: %{"NODE_PATH" => "#{Path.expand("../deps", __DIR__)}:#{node_modules_path}"}
  ],
  apidocs: [
    args: [
      "apidocs.js",
      "--bundle",
      "--target=es2017",
      "--outfile=../../priv/static/apidocs/assets/bundle.js",
      "--external:/fonts/*",
      "--external:/images/*"
    ],
    cd: Path.expand("../assets/apidocs", __DIR__),
    env: %{"NODE_PATH" => "#{Path.expand("../deps", __DIR__)}:#{node_modules_path}"}
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
  metadata: [
    :request_id,
    :auth_account_handle,
    :selected_account_handle,
    :selected_project_handle
  ]

# Money
config :money,
  default_currency: :USD

config :peep, :bucket_calculator, Tuist.PromEx.Buckets

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Using the default ETS storage leads to [lock contention](https://github.com/akoutmos/prom_ex/issues/248#issuecomment-2709045234)
# and causes the CPU clogging with cascading effects (e.g. connections dropping).
# This configures prom_ex to use a different storage using [this](https://github.com/plausible/analytics/pull/5130/)
# as a reference
config :prom_ex, :storage_adapter, Tuist.PromEx.StripedPeep

# Oban
config :tuist, Oban,
  repo: Tuist.Repo,
  notifier: Oban.Notifiers.PG

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tuist, Tuist.Mailer, adapter: Bamboo.LocalAdapter
config :tuist, Tuist.Vault, key: {Tuist.Environment, :secret_key_encryption, []}

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
  get_started: "https://tuist.dev/en/docs",
  forum: "https://community.tuist.dev",
  documentation: "https://tuist.dev/en/docs",
  # Import environment specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  feature_generated_projects: "https://tuist.dev/en/docs/guides/features/projects",
  feature_cache: "https://tuist.dev/en/docs/guides/features/cache",
  feature_previews: "https://tuist.dev/en/docs/guides/features/previews",
  feature_insights: "https://tuist.dev/en/docs/guides/features/build-insights",
  shop: "https://shop.tuist.dev"

config :tuist_common, finch_name: Tuist.Finch

config :ueberauth, Ueberauth,
  base_path: "/users/auth",
  providers: [
    github: {Ueberauth.Strategy.Github, []},
    google: {Ueberauth.Strategy.Google, []},
    apple: {Ueberauth.Strategy.Apple, [callback_methods: ["POST"], default_scope: "email"]}
  ]

import_config "#{config_env()}.exs"
