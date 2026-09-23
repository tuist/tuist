# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

alias Atlas.Accounts.Workers.ScheduleOverviewSummaries
alias Atlas.Accounts.Workers.ScheduleServiceLevelExtractions
alias Atlas.Accounts.Workers.ScheduleStripeInvoiceReconciliations
alias Atlas.Briefs.Workers.ScheduleBriefs
alias Atlas.Documents.Workers.EnsureDocumentClassifications
alias Atlas.Documents.Workers.ExpirePendingUploads
alias Atlas.Engineering.Errors.SummaryWorker, as: ErrorsSummaryWorker
alias Atlas.FeatureUsage.Workers.ScheduleFeatureUsage
alias Atlas.Finance.Workers.BackfillQontoInvoices
alias Atlas.Finance.Workers.CategorizeTransactions
alias Atlas.Finance.Workers.ScheduleSourceSyncs
alias Atlas.Granola.Workers.SyncNotes
alias Atlas.GTM.Workers.ResumeStalledDeliveries
alias Atlas.Licenses.RateLimiter
alias Atlas.Licenses.Workers.NotifyExpiringLicenses
alias Atlas.MCP.Workers.RefreshOAuthSessions
alias Atlas.Memory.Workers.RefreshBulletin, as: RefreshMemoryBulletin
alias Atlas.Nudges.Workers.EvaluateSignals, as: EvaluateNudgeSignals
alias Atlas.Nudges.Workers.ExpireStaleNudges
alias Atlas.Nudges.Workers.ReconcileDeliveryOutcomes, as: ReconcileNudgeDeliveryOutcomes
alias Atlas.Nudges.Workers.RefreshAnalyticsSnapshots, as: RefreshNudgeAnalyticsSnapshots
alias Atlas.Nudges.Workers.RefreshFeatureFirstSeen, as: RefreshNudgeFeatureFirstSeen
alias Atlas.OAuth.AccessTokens
alias Atlas.OAuth.Clients
alias Atlas.OAuth.ResourceOwners
alias Atlas.OAuth.TokenGenerator
alias Atlas.Outreach.Workers.DiscoverCandidates
alias Atlas.Outreach.Workers.ScheduleRecommendations
alias Cloak.Ciphers.AES.GCM
alias Swoosh.Adapters.Local
alias Ueberauth.Strategy.Google

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
llm_receive_timeout = :timer.minutes(5)

# Configure esbuild (the version is required)
noora_static_path = Path.expand("../../noora/priv/static", __DIR__)

# Configure Cloak encryption vault (dev/test key, overridden in runtime.exs for prod)
config :atlas, Atlas.ClickHouseRepo, read_only: true

# Default to reading contract templates from the on-disk placeholder stubs
# shipped in `priv/contracts/templates/`. Prod runtime.exs flips this to `:s3`
# once the shared object storage bucket is configured.
config :atlas, Atlas.Contracts, source: :disk
config :atlas, Atlas.Mailer, adapter: Local

config :atlas, Atlas.Vault,
  ciphers: [
    default: {
      GCM,
      tag: "AES.GCM.V1", key: Base.decode64!("1oSOxarFdN433lR9b6TJDJD8I390ipHPFiSm1ykSYpQ=")
    }
  ]

# Configure the endpoint
config :atlas, AtlasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AtlasWeb.ErrorHTML, json: AtlasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Atlas.PubSub,
  live_view: [signing_salt: "N0g/8D6v"]

# Configure Oban
config :atlas, Oban,
  repo: Atlas.Repo,
  notifier: Oban.Notifiers.PG,
  queues: [default: 10, briefs: 2, mailing: 5],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", ScheduleOverviewSummaries},
       {"15 3 * * *", RefreshNudgeAnalyticsSnapshots},
       {"45 3 * * *", RefreshNudgeFeatureFirstSeen},
       {"20 4 * * *", EvaluateNudgeSignals},
       {"30 4 * * *", ExpireStaleNudges},
       {"* * * * *", ReconcileNudgeDeliveryOutcomes},
       {"15 3 * * *", ScheduleStripeInvoiceReconciliations},
       {"5 * * * *", SyncNotes, args: %{mode: "incremental"}},
       {"45 3 * * *", SyncNotes, args: %{mode: "backfill"}},
       {"35 */6 * * *", EnsureDocumentClassifications},
       {"*/10 * * * *", RefreshOAuthSessions},
       {"*/30 * * * *", ScheduleSourceSyncs},
       {"20 4 * * *", CategorizeTransactions},
       {"40 4 * * *", BackfillQontoInvoices},
       {"0 6 * * *", DiscoverCandidates},
       {"*/30 * * * *", ScheduleRecommendations},
       {"0 9 * * 1", ScheduleBriefs, args: %{"cadence" => "weekly"}},
       {"0 17 * * *", ScheduleBriefs, args: %{"cadence" => "monthly"}},
       {"30 4 * * *", ScheduleServiceLevelExtractions},
       {"45 4 * * *", RefreshMemoryBulletin, args: %{"scope" => "global"}},
       {"30 5 * * *", ScheduleFeatureUsage},
       {"15 9 * * *", NotifyExpiringLicenses},
       # Picks email delivery back up when a run was discarded mid-audience.
       {"*/15 * * * *", ResumeStalledDeliveries},
       # Deletes document rows and reserved storage objects for uploads the
       # client never finalized.
       {"*/15 * * * *", ExpirePendingUploads},
       # Reconciles the engineering error summary. The worker no-ops when
       # `Atlas.Engineering.Errors.enabled?/0` is false, so it is safe to
       # schedule in every environment.
       {"* * * * *", ErrorsSummaryWorker}
     ]},
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]

config :atlas, RateLimiter,
  max_attempts: 60,
  window_milliseconds: :timer.minutes(1),
  max_buckets: 10_000

config :atlas, :allowed_email_domain, "tuist.dev"
config :atlas, :brave_search, api_key: nil
config :atlas, :briefs, leadership_slack_channel_id: nil

config :atlas, :documents,
  storage_client: Atlas.ObjectStorage,
  embedding_model: "text-embedding-3-small",
  embedding_receive_timeout: :timer.seconds(60)

config :atlas, :env, config_env()
config :atlas, :feature_usage, alert_slack_channel_id: nil

config :atlas, :gtm_email,
  from_name: "Tuist",
  # Bulk email is sent as the company, not as one person, so both the sender
  # and the replies survive somebody being away or moving on.
  from_email: "contact@tuist.dev",
  reply_to_email: "contact@tuist.dev",
  delivery_concurrency: 5

# Bearer token the PostHog destination presents to the Loops-compatible contact
# endpoint. Nil keeps the endpoint closed until it is configured.
config :atlas, :gtm_ingest, token: nil

config :atlas, :gtm_outreach,
  apollo_api_key: nil,
  candidate_slack_channel_id: "C072A0Z53B7",
  slack_channel_id: "C0AGV3YU8ET",
  high_score_threshold: 70,
  query_cooldown_seconds: 86_400

config :atlas, :http,
  pool_timeout: 10_000,
  finch_pools: %{
    default: [
      protocols: [:http1],
      size: 100,
      count: 1,
      pool_max_idle_time: :timer.minutes(5),
      start_pool_metrics?: true
    ]
  }

config :atlas, :licenses, signing_private_key: nil, expiration_slack_channel_id: nil
config :atlas, :llm, receive_timeout: llm_receive_timeout

config :atlas, :pingen,
  client_id: nil,
  client_secret: nil,
  organisation_id: nil,
  webhook_signing_key: nil,
  staging: false,
  delivery_product: "fast",
  print_mode: "simplex",
  print_spectrum: "color",
  receive_timeout: 15_000

config :atlas, :support,
  from_name: "Tuist Support",
  from_email: "contact@tuist.dev"

config :atlas,
  ecto_repos: [Atlas.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id_type: :binary_id]

config :boruta, Boruta.Oauth,
  repo: Atlas.Repo,
  contexts: [
    resource_owners: ResourceOwners,
    clients: Clients,
    access_tokens: AccessTokens
  ],
  token_generator: TokenGenerator

config :esbuild,
  version: "0.25.4",
  atlas: [
    args: [
      "js/app.js",
      "--bundle",
      "--target=es2022",
      "--outdir=../priv/static/assets/js",
      "--external:/fonts/*",
      "--external:/images/*",
      "--alias:@=.",
      "--alias:noora=#{noora_static_path}/noora.js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :flop, repo: Atlas.Repo

config :guardian, Guardian.DB,
  repo: Atlas.Repo,
  schema_name: "guardian_tokens",
  token_types: ["refresh"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :domain]

config :mdex_native, syntax_highlighter: :lumis

# An operator grant is a live bearer that arrives as a query parameter on the
# redirect back from ops. Phoenix logs request and LiveView event parameters,
# so name it here rather than rely on the log level being high enough.
config :phoenix, :filter_parameters, ["password", "token", "secret", "key", "operator_grant"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :req_llm, receive_timeout: llm_receive_timeout

# tzdata 1.1.3 ships 2025a data, but its runtime updater crashes on IANA
# 2026b under OTP 29 because it passes 24:00 transitions to :calendar.
config :tzdata, :autoupdate, :disabled

# Sign-in is restricted to the `tuist.dev` Google Workspace. The `hd`
# parameter scopes Google's account picker to that hosted domain, but
# it's only a hint — the callback re-validates the email domain server-side.
config :ueberauth, Ueberauth,
  providers: [
    google: {Google, [default_scope: "email profile", hd: "tuist.dev"]}
  ]

import_config "#{config_env()}.exs"
