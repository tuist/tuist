import Config

alias Atlas.Config.DevInstance
alias Atlas.TestSupport.Documents.Embedding
alias Atlas.TestSupport.Documents.Storage
alias Atlas.TestSupport.ExchangeRatesClient
alias Atlas.TestSupport.ScreenshotNoteAgent
alias Atlas.TestSupport.StripeClient
alias Swoosh.Adapters.Test

Code.require_file("dev_instance.exs", __DIR__)

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used

# In test we don't send emails
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :atlas, Atlas.Mailer, adapter: Test

config :atlas, Atlas.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    DevInstance.database_name(
      "atlas_test",
      partition: System.get_env("MIX_TEST_PARTITION")
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  # We don't run a server during test. If one is required,
  # you can enable the server option below.
  pool_size: System.schedulers_online() * 2

config :atlas, AtlasWeb.AccountLive, screenshot_note_agent: ScreenshotNoteAgent

config :atlas, AtlasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: DevInstance.port(4002)],
  secret_key_base: "9Ah9MVoOBxg/6RQuJPFXTjmN+WR2RI2HNmTIprRciWAqP3r56IX+YSua+GmI2nC9",
  server: false

config :atlas, AtlasWeb.OutreachContactsLive, screenshot_note_agent: ScreenshotNoteAgent

# Oban testing mode
config :atlas, Oban, testing: :manual

config :atlas, :accounts,
  exchange_rates_client: ExchangeRatesClient,
  stripe_client: StripeClient

config :atlas, :disable_external_clients, true

config :atlas, :documents,
  storage_client: Storage,
  embedding_client: Embedding,
  embedding_model: "test-embedding"

config :atlas, :licenses, signing_private_key: "ceVGk4YZk7sbZwxHUUlONbFr+rmJ1V9KlTWUdkHjyMI="

config :atlas, :tax_certificate_profile,
  sender_name: "Configured Sender GmbH",
  sender_street: "Example street 27a",
  sender_postal_code: "10247",
  sender_city: "Berlin",
  sender_country: "DE",
  tax_id: "30/123/45678",
  vat_id: "DE123456789",
  signatory_title: "Geschäftsführer",
  foundation_date: "2023-11-08",
  legal_form: "GmbH",
  signing_location: "Berlin",
  tax_office_name: "Finanzamt für Körperschaften III",
  tax_office_street: "Volkmarstr. 13",
  tax_office_postal_code: "12099",
  tax_office_city: "Berlin"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable Sentry in tests
config :sentry, dsn: nil

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Pages subdomain plug uses this host suffix. Tests hit `<slug>.atlas.tuist.dev`.
config :atlas, AtlasWeb.Plugs.PagesSubdomain, host_suffix: "atlas.tuist.dev"
