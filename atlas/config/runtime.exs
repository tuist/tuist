import Config

alias Atlas.Config.DevInstance
alias Cloak.Ciphers.AES.GCM
alias Swoosh.Adapters.Mailgun
alias Ueberauth.Strategy.Google.OAuth

# dev_instance.exs is only shipped in non-prod (it isn't copied into the
# release tarball), so guard the require to keep prod boots clean.
if config_env() != :prod do
  Code.require_file("dev_instance.exs", __DIR__)
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/atlas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :atlas, AtlasWeb.Endpoint, server: true
end

default_port =
  case config_env() do
    :dev -> DevInstance.port(3030)
    :test -> DevInstance.port(4002)
    _ -> 4000
  end

port =
  "PORT"
  |> System.get_env(Integer.to_string(default_port))
  |> String.to_integer()

endpoint_config =
  case config_env() do
    :dev ->
      [
        url: [host: "localhost", port: port, scheme: "http"],
        http: [port: port]
      ]

    _ ->
      [http: [port: port]]
  end

positive_integer_env = fn name, default ->
  case System.get_env(name) do
    nil ->
      default

    "" ->
      default

    value ->
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> raise "environment variable #{name} must be a positive integer"
      end
  end
end

optional_positive_integer_env = fn name ->
  case System.get_env(name) do
    nil ->
      nil

    "" ->
      nil

    value ->
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> raise "environment variable #{name} must be a positive integer when set"
      end
  end
end

present_env = fn names ->
  Enum.find_value(names, fn name ->
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _missing_or_blank -> nil
    end
  end)
end

boolean_env = fn name, default ->
  case System.get_env(name) do
    nil ->
      default

    "" ->
      default

    value when value in ["1", "true", "TRUE", "yes", "YES"] ->
      true

    value when value in ["0", "false", "FALSE", "no", "NO"] ->
      false

    _other ->
      raise "environment variable #{name} must be a boolean value"
  end
end

support_chat_parent_origins =
  case System.get_env("ATLAS_SUPPORT_CHAT_PARENT_ORIGINS") do
    value when is_binary(value) and value != "" ->
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    _ ->
      # In development, allow the local endpoint so the embedded chat's
      # postMessage handshake (resize, close, session) works without configuring origins.
      if config_env() == :dev do
        ["http://localhost:#{port}", "https://tuist.dev"]
      else
        ["https://tuist.dev"]
      end
  end

config :atlas, AtlasWeb.Endpoint, endpoint_config

config :atlas, :gtm_email,
  from_name: System.get_env("ATLAS_GTM_EMAIL_FROM_NAME", "Tuist"),
  from_email: System.get_env("ATLAS_GTM_EMAIL_FROM_EMAIL", "contact@tuist.dev"),
  reply_to_email: System.get_env("ATLAS_GTM_EMAIL_REPLY_TO", "contact@tuist.dev"),
  delivery_concurrency: positive_integer_env.("ATLAS_GTM_EMAIL_CONCURRENCY", 5)

# Bank-transfer footer printed at the bottom of every Stripe invoice. Kept
# out of source so real IBAN/BIC/beneficiary details are never checked in.
config :atlas, :invoice_footer, System.get_env("ATLAS_INVOICE_FOOTER", "")

config :atlas, :support,
  from_name: System.get_env("ATLAS_SUPPORT_FROM_NAME", "Tuist Support"),
  from_email: System.get_env("ATLAS_SUPPORT_FROM_EMAIL", "contact@tuist.dev"),
  slack_channel_id: System.get_env("ATLAS_SUPPORT_SLACK_CHANNEL_ID")

config :atlas, :support_chat, parent_origins: support_chat_parent_origins

if gtm_ingest_token = System.get_env("ATLAS_GTM_INGEST_TOKEN") do
  config :atlas, :gtm_ingest, token: gtm_ingest_token
end

# Mailgun is the company's email provider: tuist.dev is already verified there
# and has a sending history, which a second provider would not inherit. The
# account is in Mailgun's EU region, so the base URL is not the default one.
if mailgun_api_key = System.get_env("MAILGUN_API_KEY") do
  config :atlas, Atlas.Mailer,
    adapter: Mailgun,
    api_key: mailgun_api_key,
    domain: System.get_env("ATLAS_MAILGUN_DOMAIN", "mail.tuist.dev"),
    base_url: System.get_env("ATLAS_MAILGUN_BASE_URL", "https://api.eu.mailgun.net/v3")
end

# Atlas uses a dedicated Finch pool for all Req traffic so production can tune
# connection checkout behaviour independently of Req's shared defaults.
config :atlas, :http,
  pool_timeout: positive_integer_env.("ATLAS_HTTP_POOL_TIMEOUT", 10_000),
  finch_pools: %{
    default: [
      protocols: [:http1],
      size: positive_integer_env.("ATLAS_HTTP_POOL_SIZE", 100),
      count: positive_integer_env.("ATLAS_HTTP_POOL_COUNT", 1),
      pool_max_idle_time: positive_integer_env.("ATLAS_HTTP_POOL_MAX_IDLE_TIME", :timer.minutes(5)),
      start_pool_metrics?: true
    ]
  }

# Configure Google OAuth if env vars are set
if google_client_id = System.get_env("GOOGLE_CLIENT_ID") do
  config :ueberauth, OAuth,
    client_id: google_client_id,
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
end

# ## Admin Dashboard
#
# Set SUPER_ADMIN_PASSWORD to enable the admin dashboards (Oban, LiveDashboard)
# at /admin/oban and /admin/dashboard. Uses HTTP Basic Auth with username "admin".
if admin_password = System.get_env("SUPER_ADMIN_PASSWORD") do
  config :atlas, admin_password: admin_password
end

# Stripe API key drives the background invoice reconciliation job.
# Optional in dev/test; the job is disabled when unset.
if stripe_api_key = System.get_env("STRIPE_API_KEY") do
  config :atlas, :stripe, api_key: stripe_api_key
end

qonto_source =
  cond do
    access_token = System.get_env("QONTO_ACCESS_TOKEN") ->
      %{
        atlas_account_key: System.get_env("QONTO_ATLAS_ACCOUNT_KEY"),
        atlas_account_name: System.get_env("QONTO_ATLAS_ACCOUNT_NAME"),
        provider: :qonto,
        key: System.get_env("QONTO_SOURCE_KEY") || "qonto",
        name: System.get_env("QONTO_SOURCE_NAME") || "Qonto",
        access_token: access_token,
        base_url: System.get_env("QONTO_API_BASE_URL"),
        staging_token: System.get_env("QONTO_STAGING_TOKEN"),
        include_external_accounts: boolean_env.("QONTO_INCLUDE_EXTERNAL_ACCOUNTS", false)
      }

    sign_in = System.get_env("QONTO_SIGN_IN") ->
      %{
        atlas_account_key: System.get_env("QONTO_ATLAS_ACCOUNT_KEY"),
        atlas_account_name: System.get_env("QONTO_ATLAS_ACCOUNT_NAME"),
        provider: :qonto,
        key: System.get_env("QONTO_SOURCE_KEY") || "qonto",
        name: System.get_env("QONTO_SOURCE_NAME") || "Qonto",
        sign_in: sign_in,
        secret_key:
          System.get_env("QONTO_SECRET_KEY") ||
            raise("environment variable QONTO_SECRET_KEY is required when QONTO_SIGN_IN is set"),
        base_url: System.get_env("QONTO_API_BASE_URL"),
        staging_token: System.get_env("QONTO_STAGING_TOKEN"),
        include_external_accounts: boolean_env.("QONTO_INCLUDE_EXTERNAL_ACCOUNTS", false)
      }

    true ->
      nil
  end

mercury_source =
  case System.get_env("MERCURY_API_TOKEN") do
    nil ->
      nil

    "" ->
      nil

    api_token ->
      %{
        atlas_account_key: System.get_env("MERCURY_ATLAS_ACCOUNT_KEY"),
        atlas_account_name: System.get_env("MERCURY_ATLAS_ACCOUNT_NAME"),
        provider: :mercury,
        key: System.get_env("MERCURY_SOURCE_KEY") || "mercury",
        name: System.get_env("MERCURY_SOURCE_NAME") || "Mercury",
        api_token: api_token,
        base_url: System.get_env("MERCURY_API_BASE_URL")
      }
  end

# Cloudflare Email Worker webhook secret. The Worker signs raw RFC822 email
# payloads sent to /api/inbox/emails with this shared secret.
inbox_allowed_sender_domains =
  System.get_env("ATLAS_INBOX_ALLOWED_SENDER_DOMAINS", "tuist.dev")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

# Our own legal entities. Transfers between them (which providers don't always
# tag as transfers) must be excluded from runway/burn so they don't read as
# operating revenue/expense.
finance_internal_entity_names =
  System.get_env("ATLAS_FINANCE_INTERNAL_ENTITY_NAMES", "Tuist GmbH,Tuist Inc.")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

object_storage_bucket = System.get_env("ATLAS_OBJECT_STORAGE_BUCKET")

gtm_outreach_slack_channel_id =
  case System.get_env("GTM_OUTREACH_SLACK_CHANNEL_ID") do
    value when value in [nil, ""] -> "C0AGV3YU8ET"
    value -> value
  end

leadership_slack_channel_id =
  present_env.([
    "ATLAS_BRIEFS_LEADERSHIP_SLACK_CHANNEL_ID",
    "ATLAS_FINANCE_WEEKLY_SUMMARY_SLACK_CHANNEL_ID",
    "ATLAS_FINANCE_COST_DIGEST_SLACK_CHANNEL_ID"
  ])

language_model_api_key = present_env.(["LLM_API_KEY"])

# Documents reuse the shared Hetzner object storage (`:object_storage`, below)
# via Atlas.ObjectStorage, so they need no dedicated bucket credentials. Only
# the embedding provider is configured here.
config :atlas, :brave_search, api_key: System.get_env("BRAVE_SEARCH_API_KEY")

if license_signing_private_key = System.get_env("ATLAS_LICENSE_SIGNING_PRIVATE_KEY") do
  config :atlas, :licenses, signing_private_key: license_signing_private_key
end

config :atlas, :licenses,
  expiration_slack_channel_id:
    System.get_env("ATLAS_LICENSES_EXPIRATION_SLACK_CHANNEL_ID") ||
      System.get_env("ATLAS_FINANCE_SALES_SLACK_CHANNEL_ID")

# Headless-browser pool for the `browse_url` MCP tool. Off by default; set
# CHROME_PATH (typically baked into the Docker image) to enable.
if chrome_path = System.get_env("CHROME_PATH") do
  config :browse_chrome,
    default_pool: Atlas.BrowserPool,
    pools: [
      {Atlas.BrowserPool, [pool_size: positive_integer_env.("ATLAS_BROWSER_POOL_SIZE", 2), chrome_path: chrome_path]}
    ]
end

tax_certificate_profile = Application.get_env(:atlas, :tax_certificate_profile, [])

tax_certificate_profile_value = fn environment_variable, field ->
  System.get_env(environment_variable) || Keyword.get(tax_certificate_profile, field)
end

config :atlas, :briefs, leadership_slack_channel_id: leadership_slack_channel_id

config :atlas, :documents,
  embedding_api_key: present_env.(["ATLAS_DOCUMENT_EMBEDDING_API_KEY"]) || language_model_api_key,
  embedding_base_url:
    present_env.(["ATLAS_DOCUMENT_EMBEDDING_BASE_URL", "LLM_BASE_URL"]) || "https://api.openai.com/v1",
  embedding_model: System.get_env("ATLAS_DOCUMENT_EMBEDDING_MODEL") || "text-embedding-3-small",
  embedding_receive_timeout: positive_integer_env.("ATLAS_DOCUMENT_EMBEDDING_RECEIVE_TIMEOUT", :timer.seconds(60))

config :atlas, :feature_usage,
  alert_slack_channel_id: System.get_env("ATLAS_FEATURE_USAGE_ALERT_SLACK_CHANNEL_ID", "C072A0Z53B7")

config :atlas, :finance,
  report_currency: System.get_env("ATLAS_FINANCE_REPORT_CURRENCY", "EUR"),
  runway_window_days: positive_integer_env.("ATLAS_FINANCE_RUNWAY_WINDOW_DAYS", 180),
  initial_lookback_days: positive_integer_env.("ATLAS_FINANCE_INITIAL_LOOKBACK_DAYS", 365),
  sync_overlap_minutes: positive_integer_env.("ATLAS_FINANCE_SYNC_OVERLAP_MINUTES", 5),
  sales_slack_channel_id: System.get_env("ATLAS_FINANCE_SALES_SLACK_CHANNEL_ID", "C072A0Z53B7"),
  cost_digest_slack_channel_id:
    System.get_env("ATLAS_FINANCE_COST_DIGEST_SLACK_CHANNEL_ID") ||
      System.get_env("ATLAS_FINANCE_WEEKLY_SUMMARY_SLACK_CHANNEL_ID"),
  weekly_summary_slack_channel_id: System.get_env("ATLAS_FINANCE_WEEKLY_SUMMARY_SLACK_CHANNEL_ID"),
  internal_entity_names: finance_internal_entity_names,
  sources: Enum.reject([qonto_source, mercury_source], &is_nil/1)

# The feature-usage collector reads successful Model Context Protocol requests
# from Grafana Cloud Loki with a dedicated read-only access-policy token.
config :atlas, :grafana_loki,
  base_url: System.get_env("ATLAS_GRAFANA_LOKI_URL"),
  username: System.get_env("ATLAS_GRAFANA_LOKI_USERNAME"),
  token: System.get_env("ATLAS_GRAFANA_LOKI_TOKEN")

config :atlas, :granola,
  api_key: System.get_env("GRANOLA_API_KEY"),
  base_url: System.get_env("GRANOLA_API_BASE_URL")

config :atlas, :gtm_outreach,
  apollo_api_key: System.get_env("APOLLO_API_KEY"),
  candidate_slack_channel_id: System.get_env("GTM_OUTREACH_CANDIDATE_SLACK_CHANNEL_ID", "C072A0Z53B7"),
  slack_channel_id: gtm_outreach_slack_channel_id,
  high_score_threshold: positive_integer_env.("GTM_OUTREACH_HIGH_SCORE_THRESHOLD", 70),
  query_cooldown_seconds: positive_integer_env.("GTM_OUTREACH_QUERY_COOLDOWN_SECONDS", 86_400)

config :atlas, :inbox,
  webhook_secret: System.get_env("ATLAS_INBOX_WEBHOOK_SECRET"),
  allowed_sender_domains: inbox_allowed_sender_domains

# Paperless-ngx import source. Used by Atlas.Documents.Paperless (run via
# `bin/atlas eval 'Atlas.Documents.Paperless.import(limit: 1)'`).
config :atlas, :paperless,
  base_url: System.get_env("PAPERLESS_URL"),
  token: System.get_env("PAPERLESS_TOKEN")

config :atlas, :pingen,
  client_id: System.get_env("ATLAS_PINGEN_CLIENT_ID"),
  client_secret: System.get_env("ATLAS_PINGEN_CLIENT_SECRET"),
  organisation_id: System.get_env("ATLAS_PINGEN_ORGANISATION_ID"),
  webhook_signing_key: System.get_env("ATLAS_PINGEN_WEBHOOK_SIGNING_KEY"),
  staging: System.get_env("ATLAS_PINGEN_STAGING") == "true",
  api_base_url: System.get_env("ATLAS_PINGEN_API_BASE_URL"),
  identity_base_url: System.get_env("ATLAS_PINGEN_IDENTITY_BASE_URL"),
  delivery_product: System.get_env("ATLAS_PINGEN_DELIVERY_PRODUCT", "fast"),
  print_mode: System.get_env("ATLAS_PINGEN_PRINT_MODE", "simplex"),
  print_spectrum: System.get_env("ATLAS_PINGEN_PRINT_SPECTRUM", "color")

config :atlas, :tax_certificate_profile,
  sender_name: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SENDER_NAME", :sender_name),
  sender_street: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SENDER_STREET", :sender_street),
  sender_postal_code: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SENDER_POSTAL_CODE", :sender_postal_code),
  sender_city: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SENDER_CITY", :sender_city),
  sender_country: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SENDER_COUNTRY", :sender_country),
  tax_id: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_TAX_ID", :tax_id),
  vat_id: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_VAT_ID", :vat_id),
  signatory_title: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SIGNATORY_TITLE", :signatory_title),
  foundation_date: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_FOUNDATION_DATE", :foundation_date),
  legal_form: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_LEGAL_FORM", :legal_form),
  signing_location: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_SIGNING_LOCATION", :signing_location),
  tax_office_name: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_TAX_OFFICE_NAME", :tax_office_name),
  tax_office_street: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_TAX_OFFICE_STREET", :tax_office_street),
  tax_office_postal_code:
    tax_certificate_profile_value.(
      "ATLAS_TAX_CERTIFICATE_TAX_OFFICE_POSTAL_CODE",
      :tax_office_postal_code
    ),
  tax_office_city: tax_certificate_profile_value.("ATLAS_TAX_CERTIFICATE_TAX_OFFICE_CITY", :tax_office_city)

if vector_url = System.get_env("ATLAS_VECTOR_URL") do
  config :atlas, :vector, base_url: vector_url
end

if object_storage_bucket not in [nil, ""] do
  object_storage_access_key_id =
    System.get_env("ATLAS_OBJECT_STORAGE_ACCESS_KEY_ID") ||
      raise "environment variable ATLAS_OBJECT_STORAGE_ACCESS_KEY_ID is required when ATLAS_OBJECT_STORAGE_BUCKET is set"

  object_storage_secret_access_key =
    System.get_env("ATLAS_OBJECT_STORAGE_SECRET_ACCESS_KEY") ||
      raise "environment variable ATLAS_OBJECT_STORAGE_SECRET_ACCESS_KEY is required when ATLAS_OBJECT_STORAGE_BUCKET is set"

  config :atlas, :object_storage,
    endpoint_url: System.get_env("ATLAS_OBJECT_STORAGE_ENDPOINT_URL", "https://fsn1.your-objectstorage.com"),
    region: System.get_env("ATLAS_OBJECT_STORAGE_REGION", "fsn1"),
    bucket: object_storage_bucket,
    access_key_id: object_storage_access_key_id,
    secret_access_key: object_storage_secret_access_key,
    public_base_url: System.get_env("ATLAS_OBJECT_STORAGE_PUBLIC_BASE_URL")
end

if github_app_id = System.get_env("ATLAS_GITHUB_APP_ID") do
  config :atlas, :github_app,
    name: System.get_env("ATLAS_GITHUB_APP_NAME") || "tuist-atlas",
    app_id: github_app_id,
    client_id: System.get_env("ATLAS_GITHUB_APP_CLIENT_ID"),
    private_key: System.get_env("ATLAS_GITHUB_APP_PRIVATE_KEY"),
    webhook_secret: System.get_env("ATLAS_GITHUB_APP_WEBHOOK_SECRET"),
    installation_id: System.get_env("ATLAS_GITHUB_APP_INSTALLATION_ID"),
    owner: System.get_env("ATLAS_GITHUB_APP_OWNER") || "tuist",
    repo: System.get_env("ATLAS_GITHUB_APP_REPO") || "tuist"
end

# Optional upstream MCP servers that Atlas hoists through its own authenticated
# MCP endpoint. The JSON value is a list of server objects with name, url,
# optional headers, bearer_token or OAuth fields, and receive_timeout.
case System.get_env("MCP_PROXY_SERVERS") do
  value when value in [nil, ""] ->
    if config_env() in [:dev, :prod] do
      grafana_headers =
        case System.get_env("GRAFANA_MCP_STACK_URL") do
          value when value in [nil, ""] -> []
          stack_url -> %{"X-Grafana-URL" => stack_url}
        end

      # The Tuist server is itself an MCP server, and it is the only place the
      # customer artifacts behind a support escalation can be reached: the
      # `.xcresult` bundle of a failed test run, an `.ips` crash report, the
      # archive holding a build's `.xcactivitylog`. Proxying it per user rather
      # than holding a service credential means each person sees exactly what
      # their own Tuist account can read, and the operator-grant flow still
      # governs anything beyond their memberships.
      tuist_mcp_base_url = System.get_env("TUIST_MCP_BASE_URL") || "https://tuist.dev"

      config :atlas, :mcp_proxy,
        servers: [
          %{
            name: "tuist",
            url: "#{tuist_mcp_base_url}/mcp",
            auth_type: "oauth2",
            authorization_url: "#{tuist_mcp_base_url}/oauth2/authorize",
            token_url: "#{tuist_mcp_base_url}/oauth2/token",
            registration_url: "#{tuist_mcp_base_url}/oauth2/register",
            scopes: ["mcp"],
            # The Tuist tool registry includes project and organization
            # creation, membership changes and test-case updates. Atlas proxies
            # this upstream to investigate production, so it takes only the
            # tools that declare themselves read-only. That declaration is
            # required of every Tuist tool at compile time, so a write tool
            # cannot reach here by saying nothing — which is what lets this
            # stand on its own without also enumerating the tools by name.
            read_only: true,
            # Operator grants are minted per human at ops.tuist.dev and elevate
            # a session past the user's own memberships, so they travel per
            # request from each user's stored grant rather than from config.
            # Only read-tier grants are forwarded, so the credential — not this
            # list of tools — is what bounds the request upstream.
            operator_grant_header: "x-tuist-operator-grant"
          },
          %{
            name: "grafana",
            url: "https://mcp.grafana.com/mcp",
            auth_type: "oauth2",
            authorization_url: "https://mcp.grafana.com/mcp/oauth/authorize",
            token_url: "https://mcp.grafana.com/mcp/oauth/token",
            registration_url: "https://mcp.grafana.com/mcp/oauth/register",
            scopes: ["grafana:read", "grafana:write"],
            headers: grafana_headers
          },
          %{
            name: "sentry",
            url: System.get_env("SENTRY_MCP_URL") || "https://mcp.sentry.dev/mcp",
            auth_type:
              if(System.get_env("SENTRY_MCP_BEARER_TOKEN") in [nil, ""],
                do: "oauth2",
                else: "bearer_token"
              ),
            authorization_url: "https://mcp.sentry.dev/oauth/authorize",
            token_url: "https://mcp.sentry.dev/oauth/token",
            registration_url: "https://mcp.sentry.dev/oauth/register",
            scopes: ["org:read", "project:write", "team:write", "event:write"],
            shared_oauth: true,
            shared_oauth_user_email: System.get_env("SENTRY_MCP_SHARED_USER_EMAIL"),
            bearer_token: System.get_env("SENTRY_MCP_BEARER_TOKEN")
          }
        ]
    end

  value ->
    case JSON.decode(value) do
      {:ok, servers} when is_list(servers) ->
        config :atlas, :mcp_proxy, servers: servers

      _ ->
        raise "environment variable MCP_PROXY_SERVERS must be a JSON array"
    end
end

slack_agent_channel_policies =
  case System.get_env("ATLAS_SLACK_AGENT_CHANNEL_POLICIES") do
    value when value in [nil, ""] ->
      []

    value ->
      case JSON.decode(value) do
        {:ok, policies} when is_list(policies) ->
          policies

        _ ->
          raise "environment variable ATLAS_SLACK_AGENT_CHANNEL_POLICIES must be a JSON array"
      end
  end

slack_agent_identities =
  case System.get_env("ATLAS_SLACK_AGENT_IDENTITIES") do
    value when value in [nil, ""] ->
      []

    value ->
      case JSON.decode(value) do
        {:ok, identities} when is_list(identities) ->
          identities

        _ ->
          raise "environment variable ATLAS_SLACK_AGENT_IDENTITIES must be a JSON array"
      end
  end

# Slack app credentials. Atlas keeps one company Slack app. The signing
# secret is app-wide; the bot token can be captured through the install
# flow and persisted in `slack_installations`.
config :atlas, :slack,
  client_id: System.get_env("ATLAS_SLACK_CLIENT_ID"),
  client_secret: System.get_env("ATLAS_SLACK_CLIENT_SECRET"),
  signing_secret: System.get_env("ATLAS_SLACK_SIGNING_SECRET") || System.get_env("SLACK_COMPANY_SIGNING_SECRET"),
  scopes: System.get_env("ATLAS_SLACK_BOT_SCOPES"),
  allowed_team_ids: System.get_env("ATLAS_SLACK_ALLOWED_TEAM_IDS"),
  bot_token: System.get_env("SLACK_COMPANY_BOT_TOKEN"),
  bot_name: System.get_env("ATLAS_SLACK_BOT_NAME") || System.get_env("SLACK_COMPANY_BOT_NAME")

config :atlas, :slack_agent,
  mcp_user_email: System.get_env("ATLAS_SLACK_AGENT_MCP_USER_EMAIL") || "pedro@tuist.dev",
  identities: slack_agent_identities,
  channel_policies: slack_agent_channel_policies

# Sentry error reporting. Only configured when SENTRY_DSN is set so dev
# and self-hosted boots don't try to ship events. SENTRY_RELEASE is
# populated by rel/env.sh.eex from the deploy SHA; falls back to the
# compiled app version for local boots.
if sentry_dsn = System.get_env("SENTRY_DSN") do
  config :sentry,
    dsn: sentry_dsn,
    environment_name: System.get_env("SENTRY_ENVIRONMENT", to_string(config_env())),
    release: System.get_env("SENTRY_RELEASE") || to_string(Application.spec(:atlas, :vsn)),
    enable_source_code_context: true,
    root_source_code_paths: [File.cwd!()],
    before_send: {Atlas.SentryEventFilter, :before_send}
end

# Single language model provider used by all AI features. LLM_MODEL takes a
# ReqLLM "provider:model_id" string. Two modes are supported:
#
#   Remote — an OpenAI-compatible upstream is called over HTTPS:
#     LLM_API_KEY=<bearer token>
#     LLM_MODEL=openai:gpt-4o-mini
#     LLM_BASE_URL=https://api.openai.com/v1     # optional for OpenAI itself
#
#   Local — atlas hosts the inference relay itself. ReqLLM's HTTP calls
#   are routed in-process through Atlas.LLMs.LocalTransport, which
#   dispatches to Atlas.Inference.relay_request/3. No API key needed —
#   the atlas-role token on the profile marked atlas_inference: true is
#   used automatically.
#     LLM_MODE=local
#     LLM_MODEL=openai:Balanced
llm_mode = present_env.(["LLM_MODE"])
llm_config = Application.get_env(:atlas, :llm, [])

cond do
  llm_mode == "local" ->
    model =
      present_env.(["LLM_MODEL"]) ||
        raise "environment variable LLM_MODEL is required when LLM_MODE=local"

    config :atlas, :llm,
      mode: :local,
      model: model,
      receive_timeout: Keyword.get(llm_config, :receive_timeout)

  language_model_api_key != nil ->
    model =
      present_env.(["LLM_MODEL"]) ||
        raise "environment variable LLM_MODEL is required when LLM_API_KEY is set"

    config :atlas, :llm,
      mode: :remote,
      api_key: language_model_api_key,
      model: model,
      base_url: present_env.(["LLM_BASE_URL"]),
      receive_timeout: Keyword.get(llm_config, :receive_timeout)

  true ->
    :ok
end

if config_env() == :prod do
  encryption_key =
    System.get_env("ENCRYPTION_KEY") ||
      raise """
      environment variable ENCRYPTION_KEY is missing.
      Generate one with: elixir -e "IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))"
      """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  database_ssl_opts =
    if System.get_env("DATABASE_SSL") in ~w(true 1) do
      [ssl: true, ssl_opts: [verify: :verify_none]]
    else
      []
    end

  config :atlas, Atlas.Guardian,
    issuer: "atlas",
    secret_key:
      System.get_env("GUARDIAN_SECRET_KEY") ||
        raise("environment variable GUARDIAN_SECRET_KEY is missing")

  config :atlas,
         Atlas.Repo,
         [
           url: database_url,
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ database_ssl_opts

  config :atlas, Atlas.Vault,
    ciphers: [
      default: {
        GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(encryption_key)
      }
    ]

  config :atlas, AtlasWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :atlas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end

if config_env() in [:dev, :test] do
  config :atlas, Atlas.Guardian,
    issuer: "atlas",
    secret_key: "dev-only-guardian-secret-do-not-use-in-prod-aaaaaaaaaaaaaaaa"
end

# Internal Tuist server API, used by the `*_tuist_postgres*` MCP tools for
# read-only database access. Atlas authenticates with a projected ServiceAccount
# token (audience `tuist-server`) read from `token_path`; the file is absent in
# dev/test, so the tools report the database as unreachable there.
# Where operators justify access to a customer account. Atlas sends them here
# with a return destination that receives the minted grant.
config :atlas, :ops, reason_form_url: System.get_env("ATLAS_OPS_REASON_FORM_URL") || "https://ops.tuist.dev/grants/new"

config :atlas, :tuist_server,
  base_url: System.get_env("TUIST_SERVER_INTERNAL_URL") || "https://tuist.dev",
  token_path: System.get_env("TUIST_SERVER_TOKEN_PATH") || "/var/run/secrets/tuist/token"
