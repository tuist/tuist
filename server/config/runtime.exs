import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Pod role
#
# The release boots into one of two modes selected by `TUIST_MODE`:
#
#   * unset / `TUIST_MODE=web` — Phoenix endpoint binds, every Oban queue
#     and ingestion buffer runs. Default for `bin/tuist start`.
#   * `TUIST_MODE=processor` — no Phoenix listener; Oban runs only the
#     `:process_build` queue.
#
# See `Tuist.Environment.mode/0` for the full list.
alias Tuist.Oban.RuntimeConfig

# Runner Profiles shape catalog. Helm injects the same
# `runnersFleetLinux.shapes` list it renders the shape-keyed RunnerPool
# CRs from, so in a managed deploy the server's catalog and the
# cluster's pools share one source of truth and can't drift.
#
# Absent (local dev / tests / CI) → the `config/config.exs` default
# applies. Present but unparseable → raise: the value is Helm-rendered
# via `toJson`, so a malformed one is a chart bug, and silently falling
# back to the default would run a catalog that doesn't match the pools
# that actually exist — reintroducing the drift this injection removes.
# A boot failure here is caught in the canary stage before production.
alias Tuist.Runners.Catalog

case System.get_env("TUIST_RUNNER_LINUX_SHAPES") do
  nil ->
    :ok

  json ->
    case Catalog.parse_shapes_json(json) do
      :error ->
        raise "TUIST_RUNNER_LINUX_SHAPES is set but is not a valid JSON array of shapes " <>
                "(Helm renders it from runnersFleetLinux.shapes via toJson). Got: #{inspect(json)}"

      shapes ->
        config :tuist, :runner_linux_shapes, shapes
    end
end

case System.get_env("TUIST_RUNNER_MACOS_SHAPES") do
  nil ->
    :ok

  "" ->
    :ok

  json ->
    case Catalog.parse_shapes_json(json) do
      :error ->
        raise "TUIST_RUNNER_MACOS_SHAPES is set but is not a valid JSON array of shapes " <>
                "(Helm renders it from runnersFleet.shapes via toJson). Got: #{inspect(json)}"

      shapes ->
        config :tuist, :runner_macos_shapes, shapes
    end
end

case System.get_env("TUIST_RUNNER_MACOS_XCODE_VERSIONS") do
  nil ->
    :ok

  "" ->
    :ok

  json ->
    case Catalog.parse_xcode_versions_json(json) do
      :error ->
        raise "TUIST_RUNNER_MACOS_XCODE_VERSIONS is set but is not a valid JSON array " <>
                "(Helm renders it from runnersFleet.xcodeVersions via toJson). Got: #{inspect(json)}"

      xcodes ->
        config :tuist, :runner_macos_xcode_versions, xcodes
    end
end

if Tuist.Environment.web?() do
  config :tuist, TuistWeb.Endpoint, server: true
end

env = Tuist.Environment.env()
secrets = Tuist.Environment.decrypt_secrets()
secret_key_base = Tuist.Environment.secret_key_base(secrets)

if env != :test do
  config :tuist, TuistWeb.Endpoint, secret_key_base: secret_key_base
end

if Enum.member?([:prod, :stag, :can, :preview], env) do
  database_url =
    Tuist.Environment.database_url(secrets) ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  database_config = Tuist.Environment.database_config_from_url(database_url)
  database_hostname = Keyword.fetch!(database_config, :hostname)
  database_schema = Tuist.Environment.database_schema()

  # `{:keepalive, true}` enables SO_KEEPALIVE but inherits the OS default
  # `tcp_keepalive_time` (7200s on Linux), so the pool keeps handing out
  # half-dead sockets long after a cloud-egress NAT drops the idle TCP
  # connection — surfaced as `DBConnection.ConnectionError: ssl recv
  # (idle): closed`, fired ~14k times from `Oban.Met.Reporter` once NAT
  # hops sat on the Postgres egress path. Postgres-side
  # `tcp_keepalives_idle: "60"` only helps when those probes actually
  # reach the client across the path; mirror the same 60s/15s/4-probe
  # cadence on the client socket so dead idles get reaped within ~2 min,
  # well under any cloud NAT timeout.
  # Postgrex hands `socket_options` straight to `:gen_tcp` / `:ssl`,
  # so the `{:raw, _, _, _}` 4-tuples work here (unlike Mint, whose
  # `Keyword.merge/2` normalization rejects them — see commit d803ae28cd).
  tcp_keepalive_raw_opts =
    case :os.type() do
      {:unix, :linux} ->
        [
          {:raw, 6, 4, <<60::native-32>>},
          {:raw, 6, 5, <<15::native-32>>},
          {:raw, 6, 6, <<4::native-32>>}
        ]

      _ ->
        []
    end

  socket_opts =
    if Tuist.Environment.use_ipv6?(secrets) in ~w(true 1),
      do: [:inet6, {:keepalive, true}] ++ tcp_keepalive_raw_opts,
      else: [{:keepalive, true}] ++ tcp_keepalive_raw_opts

  # Picks the connection shape based on `TUIST_DATABASE_POOLED` (set by the
  # chart on processor pods, unset on server pods). Direct Postgres keeps
  # `:named` prepares + tcp_keepalives_* startup parameters; transaction-
  # mode poolers (PgBouncer, PgCat, etc.) drop both — they reject
  # non-standard startup parameters with `protocol_violation` and can't
  # reuse named prepares across transactions that land on different
  # backend connections.
  pooled? = Tuist.Environment.database_pooled?()

  postgres_parameters =
    if pooled?,
      do: [],
      else: [
        tcp_keepalives_idle: "60",
        tcp_keepalives_interval: "30",
        tcp_keepalives_count: "3"
      ]

  postgres_parameters =
    if Tuist.Environment.default_database_schema?(database_schema) do
      postgres_parameters
    else
      Keyword.put(
        postgres_parameters,
        :search_path,
        Tuist.Environment.quote_postgres_identifier(database_schema)
      )
    end

  database_options =
    [
      pool_size: Tuist.Environment.database_pool_size(secrets),
      queue_target: Tuist.Environment.database_queue_target(secrets),
      queue_interval: Tuist.Environment.database_queue_interval(secrets),
      socket_options: socket_opts,
      parameters: postgres_parameters,
      prepare: if(pooled?, do: :unnamed, else: :named)
    ] ++ database_config

  # The `search_path` connection parameter above is a startup-packet
  # parameter, which poolers and managed-Postgres proxies routinely drop —
  # leaving the session on the default `public` path. Issue an explicit
  # `SET search_path` on every connection (migrator included) so a custom
  # schema resolves even when the startup parameter doesn't survive.
  database_options =
    if Tuist.Environment.default_database_schema?(database_schema) do
      database_options
    else
      Keyword.put(
        database_options,
        :after_connect,
        {Postgrex, :query!, ["SET search_path TO #{Tuist.Environment.quote_postgres_identifier(database_schema)}", []]}
      )
    end

  database_options =
    if Tuist.Environment.use_ssl_for_database?() do
      Keyword.put(database_options, :ssl,
        server_name_indication: to_charlist(database_hostname),
        verify: :verify_none
      )

      # TODO: Add proper certificate verification
    else
      database_options
    end

  # Cluster formation via headless Service DNS. TUIST_CLUSTER_DNS_SERVICE
  # must point at a headless Service whose endpoints resolve to the pod IPs;
  # TUIST_CLUSTER_APP_NAME is the Erlang long-name prefix used for the node
  # (e.g. "tuist"). Both are set by the Helm chart when
  # `server.cluster.enabled=true`.
  dns_name = System.get_env("TUIST_CLUSTER_DNS_SERVICE")
  app_name = System.get_env("TUIST_CLUSTER_APP_NAME")

  config :libcluster,
    topologies: [
      k8s: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: dns_name,
          application_name: app_name
        ]
      ]
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :tuist, TuistWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :tuist, TuistWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
  config :logger, level: Tuist.Environment.log_level()

  config :tuist, Tuist.ClickHouseRepo,
    url: Tuist.Environment.clickhouse_url(secrets),
    pool_size: Tuist.Environment.clickhouse_pool_size(secrets),
    queue_target: Tuist.Environment.clickhouse_queue_target(secrets),
    queue_interval: Tuist.Environment.clickhouse_queue_interval(secrets),
    settings: [
      readonly: 1,
      max_threads: Tuist.Environment.clickhouse_max_threads(secrets),
      # Specifies the join algorithms to use in order of preference: direct (fastest for small tables),
      # parallel_hash (good for medium tables), and hash (fallback for large tables)
      join_algorithm: "direct,parallel_hash,hash"
    ],
    transport_opts: [
      keepalive: true,
      show_econnreset: true,
      inet6: Tuist.Environment.use_ipv6?(secrets)
    ]

  config :tuist, Tuist.IngestRepo,
    url: Tuist.Environment.clickhouse_url(secrets),
    pool_size: Tuist.Environment.clickhouse_pool_size(secrets),
    queue_target: Tuist.Environment.clickhouse_queue_target(secrets),
    queue_interval: Tuist.Environment.clickhouse_queue_interval(secrets),
    flush_interval_ms: Tuist.Environment.clickhouse_flush_interval_ms(secrets),
    max_buffer_size: Tuist.Environment.clickhouse_max_buffer_size(secrets),
    pool_size: Tuist.Environment.clickhouse_buffer_pool_size(secrets),
    settings: [
      max_threads: Tuist.Environment.clickhouse_max_threads(secrets)
    ],
    transport_opts: [
      keepalive: true,
      show_econnreset: true,
      inet6: Tuist.Environment.use_ipv6?(secrets)
    ]

  config :tuist, Tuist.Repo, database_options

  config :tuist,
    ecto_repos: [Tuist.Repo, Tuist.IngestRepo],
    generators: [timestamp_type: :utc_datetime],
    api_pipeline_producer_module: OffBroadwayMemory.Producer,
    api_pipeline_producer_options: [buffer: :api_data_pipeline_in_memory_buffer]
end

if env == :dev do
  clickhouse_http_port =
    String.to_integer(System.get_env("TUIST_SERVER_CLICKHOUSE_HTTP_PORT") || "8123")

  dev_db_config =
    for {env_var, key} <- [
          {"DATABASE_USERNAME", :username},
          {"DATABASE_PASSWORD", :password},
          {"DATABASE_HOST", :hostname},
          {"TUIST_SERVER_POSTGRES_DB", :database}
        ],
        value = System.get_env(env_var),
        do: {key, value}

  clickhouse_dev_config = [
    hostname: "127.0.0.1",
    port: clickhouse_http_port,
    database: System.get_env("TUIST_SERVER_CLICKHOUSE_DB") || "tuist_development"
  ]

  config :tuist, Tuist.ClickHouseRepo, clickhouse_dev_config
  config :tuist, Tuist.IngestRepo, clickhouse_dev_config
  config :tuist, Tuist.Repo, Keyword.put_new(dev_db_config, :database, "tuist_development")
end

if env == :test do
  test_postgres_db =
    System.get_env("TUIST_SERVER_TEST_POSTGRES_DB") ||
      "tuist_test#{System.get_env("MIX_TEST_PARTITION")}"

  test_clickhouse_db =
    System.get_env("TUIST_SERVER_TEST_CLICKHOUSE_DB") ||
      "tuist_test#{System.get_env("MIX_TEST_PARTITION")}"

  test_port = String.to_integer(System.get_env("TUIST_SERVER_TEST_PORT") || "4002")

  clickhouse_http_port =
    String.to_integer(System.get_env("TUIST_SERVER_CLICKHOUSE_HTTP_PORT") || "8123")

  config :tuist, Tuist.ClickHouseRepo,
    hostname: "127.0.0.1",
    port: clickhouse_http_port,
    database: test_clickhouse_db

  config :tuist, Tuist.IngestRepo,
    hostname: "127.0.0.1",
    port: clickhouse_http_port,
    database: test_clickhouse_db

  config :tuist, Tuist.Repo, database: test_postgres_db
  config :tuist, TuistWeb.Endpoint, http: [ip: {127, 0, 0, 1}, port: test_port]
end

if Enum.member?([:prod, :stag, :can, :preview, :dev], env) do
  port =
    if env == :dev do
      String.to_integer(System.get_env("TUIST_SERVER_PORT") || "8080")
    else
      8080
    end

  app_url = Tuist.Environment.app_url([route_type: :app], secrets)
  %{host: app_url_host, port: app_url_port, scheme: app_url_scheme} = URI.parse(app_url)

  http_ip =
    case {env, app_url_host} do
      {:dev, "localhost"} -> {127, 0, 0, 1}
      {:dev, _host} -> {0, 0, 0, 0}
      # Enable IPv6 and bind on all interfaces.
      {_env, _host} -> {0, 0, 0, 0, 0, 0, 0, 0}
    end

  check_origin = if env == :dev, do: false, else: [app_url]

  config :tuist, TuistWeb.Endpoint,
    url: [host: app_url_host, port: app_url_port, scheme: app_url_scheme],
    check_origin: check_origin,
    http: [
      ip: http_ip,
      port: port,
      http_options: [
        log_protocol_errors: :verbose
      ],
      thousand_island_options: [
        read_timeout: to_timeout(second: 15)
      ]
    ]

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :tuist, Tuist.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

if Tuist.Environment.error_tracking_enabled?() do
  config :sentry,
    client: TuistCommon.SentryHTTPClient,
    dsn: Tuist.Environment.sentry_dsn(secrets),
    environment_name: env,
    release: Tuist.Environment.version(),
    enable_source_code_context: true,
    root_source_code_paths: [File.cwd!()],
    before_send: {Tuist.SentryEventFilter, :before_send}
end

# Ex.AWS
if Tuist.Environment.env() not in [:test] do
  s3_endpoint =
    if Tuist.Environment.swift_registry_sync_mode?() do
      case {System.get_env("S3_ENDPOINT"), System.get_env("S3_HOST")} do
        {endpoint, _host} when endpoint not in [nil, ""] -> endpoint
        {_endpoint, host} when host not in [nil, ""] -> "https://#{host}"
        _ -> nil
      end
    else
      Tuist.Environment.s3_endpoint(secrets)
    end

  if s3_endpoint in [nil, ""] do
    raise "S3 endpoint is required; set TUIST_S3_ENDPOINT, S3_ENDPOINT, or S3_HOST"
  end

  %{host: s3_endpoint_host, scheme: s3_scheme, port: s3_port} =
    URI.parse(s3_endpoint)

  s3_config =
    then(
      [
        scheme: "#{s3_scheme}://",
        host: s3_endpoint_host,
        region: Tuist.Environment.s3_region(secrets),
        virtual_host: Tuist.Environment.s3_virtual_host(secrets),
        bucket_as_host: Tuist.Environment.s3_bucket_as_host(secrets)
      ],
      &if(is_nil(s3_port), do: &1, else: Keyword.put(&1, :port, s3_port))
    )

  config :ex_aws, :req_opts,
    # Note: connect_options cannot be used with Finch
    # Connection timeout is handled at the Finch pool level

    # Maximum time (in ms) that an idle connection can remain in the pool
    # before being closed. Helps prevent stale connections.
    # Set to :infinity to keep connections alive indefinitely
    pool_max_idle_time: Tuist.Environment.s3_pool_max_idle_time(secrets),

    # Maximum time (in ms) to wait for data after the connection is established
    # This timeout resets each time data is received, so large files can still
    # be downloaded as long as data keeps flowing
    receive_timeout: Tuist.Environment.s3_receive_timeout(secrets),

    # Maximum time (in ms) to wait when checking out a connection from the pool
    # If all connections are busy, this is how long it will wait for one to
    # become available before timing out
    pool_timeout: Tuist.Environment.s3_pool_timeout(secrets)

  config :ex_aws, :s3, s3_config

  config :ex_aws,
         Tuist.AWS.S3AuthenticationConfig.ex_aws_config(
           Tuist.Environment.s3_authentication_method(secrets),
           secrets
         )

  config :ex_aws,
    http_client: TuistCommon.AWS.Client

  config :tuist_common, finch_name: Tuist.Finch
end

# Stripe config
if Tuist.Environment.stripe_configured?(secrets) do
  config :stripity_stripe,
    api_key: Tuist.Environment.stripe_api_key(secrets),
    signing_secret: Tuist.Environment.stripe_endpoint_secret(secrets)
end

config :ueberauth, Ueberauth.Strategy.Apple.OAuth,
  client_id: Tuist.Environment.apple_service_client_id(secrets),
  client_secret: {Tuist.OAuth.Apple, :client_secret}

# Omniauth
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: Tuist.Environment.github_app_client_id(secrets),
  client_secret: Tuist.Environment.github_app_client_secret(secrets)

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: Tuist.Environment.google_oauth_client_id(secrets),
  client_secret: Tuist.Environment.google_oauth_client_secret(secrets)

# Mailgun configuration
if Tuist.Environment.mail_configured?(secrets) and Tuist.Environment.env() in [:prod, :can, :stag] do
  base_uri =
    cond do
      env in [:prod, :can, :stag] -> "https://api.eu.mailgun.net/v3"
      env in [:dev] -> "https://api.mailgun.net/v3"
    end

  config :tuist, Tuist.Mailer,
    adapter: Bamboo.MailgunAdapter,
    api_key: Tuist.Environment.mailgun_api_key(secrets),
    domain: Tuist.Environment.mailing_domain(secrets),
    base_uri: base_uri
end

otel_endpoint = Tuist.Environment.get([:otel, :exporter, :otlp, :endpoint])

# Oban.
#
# Four queue-list shapes derived from the same base. Pod role is set
# via TUIST_MODE; delegate flags let the web tier hand off specific
# queues to dedicated fleets without changing pod role.
#
#   * Web/server (default): every queue. Self-hosted installs without
#     dedicated processors stay on this shape.
#   * Build processor (TUIST_MODE=processor): only :process_build. CPU-
#     heavy xcactivitylog parse, runs in-cluster on Linux.
#   * Xcresult processor (TUIST_MODE=xcresult_processor): only
#     :process_xcresult. Runs on macOS (Scaleway Mac mini) inside a
#     Tart VM because xcresulttool is Xcode-only.
#   * Server pods with TUIST_DELEGATE_PROCESS_BUILD=1 /
#     TUIST_DELEGATE_PROCESS_XCRESULT=1 skip the matching queue so
#     jobs land exclusively on the dedicated fleet — without those
#     flags the server would race the processors on SKIP LOCKED, and
#     on Linux the xcresult parse would crash because the macOS-only
#     NIF isn't loaded.
# Webhook deliveries get their own queue so a slow or down upstream
# can't starve unrelated work — each job can block for up to 10s and
# retries six times, and a single `test_case.created` event fans out
# to one job per subscribed endpoint.
base_queues = [default: 10, vcs_comments: 20, webhooks: 20, storage_retention: 1]
process_build_queue = {:process_build, Tuist.Environment.process_build_queue_concurrency()}
process_xcresult_queue = {:process_xcresult, Tuist.Environment.process_xcresult_queue_concurrency()}
# Swift registry sync queues. Consumed only by
# `TUIST_MODE=swift_registry_sync` pods so the web tier doesn't
# accidentally pull catalog-sync work and starve request-path workers;
# the web tier still ENQUEUES via the leader-only cron entry registered
# in `Tuist.Oban.RuntimeConfig.@hosted_only_crons`. Future ecosystems
# get their own mode + queues (e.g. `:maven_registry_sync`).
swift_registry_sync_queues = [swift_registry_sync: 1, swift_registry_release: 5]

oban_queues =
  cond do
    Tuist.Environment.processor_mode?() ->
      [process_build_queue]

    Tuist.Environment.xcresult_processor_mode?() ->
      [process_xcresult_queue]

    Tuist.Environment.swift_registry_sync_mode?() ->
      swift_registry_sync_queues

    true ->
      base = base_queues
      base = if Tuist.Environment.delegate_process_build?(), do: base, else: base ++ [process_build_queue]
      if Tuist.Environment.delegate_process_xcresult?(), do: base, else: base ++ [process_xcresult_queue]
  end

# Leader-only Oban work (Cron, Pruner, Lifeline, Oban.Met.Reporter) runs
# on whichever node wins the peer election. Web pods are the only leader-
# eligible nodes; every other role gets `peer: false` (Oban normalises
# that to the Isolated peer with `leader?: false`, so leader-only plugins
# start there but stay idle). The crontab and the peer rule are derived
# by `Tuist.Oban.RuntimeConfig`, which is unit-tested against every value
# of `Tuist.Environment.modes/0` so a future denylist regression — like
# the one where `:xcresult_processor` shipped leader-eligible with an
# empty crontab and silently halted every cron job — fails CI before it
# lands in prod.
mode = Tuist.Environment.mode()

crontab = RuntimeConfig.crontab(mode, env, Tuist.Environment.tuist_hosted?())

config :tuist, Oban,
  queues: oban_queues,
  plugins: [
    # Retain completed jobs just long enough to outlive the
    # AutomationScheduler per-alert dedup window: it skips re-enqueuing an
    # evaluation that ran within the alert's `cadence`, which is validated
    # to <= 1h (Tuist.Automations.Alerts.Alert). 2h keeps a 2x margin over
    # that cap while holding oban_jobs at tens of thousands of rows. `limit`
    # lets one pass clear the steady churn (the :default queue alone
    # produces millions/week).
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 2, limit: 50_000},
    {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
    {Oban.Plugins.Cron, crontab: crontab}
  ]

if !RuntimeConfig.peer_eligible?(mode) do
  config :tuist, Oban, peer: false
end

# Registry config.
#
# The bucket name is shared across ecosystems (one Tigris bucket).
# `swift_*` keys are scoped to the Swift Package Registry sync workers.
# `Tuist.Registry.Swift.SyncWorker` is cron-fired by the :web leader
# and inserts jobs into the `:swift_registry_sync` queue. The
# swift-registry-sync pod (`TUIST_MODE=swift_registry_sync`) consumes
# them plus the `:swift_registry_release` jobs each SyncWorker enqueues
# per missing tag. Reads from the bucket happen on the standalone
# `registry` Phoenix app, not here.
swift_registry_sync_allowlist =
  case System.get_env("SWIFT_REGISTRY_SYNC_ALLOWLIST") do
    nil -> nil
    "" -> nil
    value -> value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

swift_registry_sync_limit =
  case System.get_env("SWIFT_REGISTRY_SYNC_LIMIT") do
    nil -> 1_000
    value -> String.to_integer(value)
  end

config :tuist, :registry,
  bucket: System.get_env("S3_REGISTRY_BUCKET"),
  swift_github_token: System.get_env("SWIFT_REGISTRY_GITHUB_TOKEN"),
  swift_sync_enabled:
    "SWIFT_REGISTRY_SYNC_ENABLED" |> System.get_env("true") |> String.downcase() |> Kernel.in(["1", "true"]),
  swift_sync_allowlist: swift_registry_sync_allowlist,
  swift_sync_limit: swift_registry_sync_limit

# In swift-registry-sync mode the BEAM only talks to the registry S3
# bucket, so override ex_aws to the registry's Tigris key set. No other
# queue runs in this pod, so the override never reaches a Storage call.
# We fail fast if any required env is blank: silently falling back to the
# account-storage credentials would write to the registry bucket with the
# wrong principal and 403 every upload while the cursor still advances.
if Tuist.Environment.swift_registry_sync_mode?() do
  registry_s3_endpoint = System.get_env("S3_ENDPOINT")

  {registry_s3_scheme, registry_s3_host, registry_s3_port} =
    case registry_s3_endpoint do
      endpoint when endpoint in [nil, ""] ->
        {"https://", System.get_env("S3_HOST"), nil}

      endpoint ->
        uri = URI.parse(endpoint)

        {host, port} =
          case {uri.host, uri.port} do
            {nil, _} -> {System.get_env("S3_HOST"), nil}
            {host, nil} -> {host, nil}
            {host, port} -> {host, port}
          end

        scheme = (uri.scheme || "https") <> "://"
        {scheme, host, port}
    end

  registry_s3_region = System.get_env("S3_REGION") || "auto"
  registry_s3_access_key_id = System.get_env("S3_ACCESS_KEY_ID")
  registry_s3_secret_access_key = System.get_env("S3_SECRET_ACCESS_KEY")
  registry_bucket = System.get_env("S3_REGISTRY_BUCKET")

  missing =
    Enum.filter(
      [
        {"S3_REGISTRY_BUCKET", registry_bucket},
        {"S3_ENDPOINT or S3_HOST", registry_s3_host},
        {"S3_ACCESS_KEY_ID", registry_s3_access_key_id},
        {"S3_SECRET_ACCESS_KEY", registry_s3_secret_access_key}
      ],
      fn {_name, value} -> value in [nil, ""] end
    )

  if missing != [] do
    names = Enum.map_join(missing, ", ", fn {name, _} -> name end)
    raise "TUIST_MODE=swift_registry_sync requires #{names} to be set; refusing to boot"
  end

  registry_s3_config =
    then(
      [
        scheme: registry_s3_scheme,
        host: registry_s3_host,
        region: registry_s3_region,
        virtual_host: false
      ],
      fn config ->
        if is_nil(registry_s3_port), do: config, else: Keyword.put(config, :port, registry_s3_port)
      end
    )

  config :ex_aws, :s3, registry_s3_config

  config :ex_aws,
    access_key_id: registry_s3_access_key_id,
    secret_access_key: registry_s3_secret_access_key,
    region: registry_s3_region
end

# Kura controller rollout assets. Each env is enumerated explicitly so a
# new one fails loudly rather than silently picking the wrong hook path.
kura_hook_path =
  case env do
    e when e in [:prod, :stag, :can, :preview] -> Application.app_dir(:tuist, "priv/kura/hooks/tuist.lua")
    e when e in [:dev, :test] -> Path.expand("../kura/ops/helm/kura/hooks/tuist.lua", File.cwd!())
    other -> raise "unknown env #{inspect(other)} for :kura_hook_path; add it to runtime.exs"
  end

# Guardian
config :tuist, Tuist.Guardian,
  issuer: "tuist",
  secret_key: Tuist.Environment.secret_key_tokens(secrets)

# Prometheus
config :tuist, Tuist.PromEx,
  disabled: not Tuist.Environment.prometheus_enabled?(),
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  ets_flush_interval: 20_000,
  metrics_server: [
    port: 9091,
    auth_strategy: :none
  ]

config :tuist, :kura_hook_path, kura_hook_path

if otel_endpoint do
  config :opentelemetry,
    span_processor: :batch,
    resource: [
      service: [
        name: "tuist-server",
        namespace: "tuist",
        version: to_string(Tuist.Environment.version())
      ],
      deployment: [environment: to_string(env)]
    ]

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: otel_endpoint
else
  config :opentelemetry,
    traces_exporter: :none
end

if Tuist.Environment.analytics_enabled?(secrets) do
  config :posthog,
    api_url: Tuist.Environment.posthog_url(secrets),
    api_key: Tuist.Environment.posthog_api_key(secrets)

  config :posthog,
    json_library: Jason,
    enabled_capture: true,
    http_client: Tuist.PostHog.HTTPClient,
    http_client_opts: [
      timeout: 5_000,
      retries: 3,
      retry_delay: 1_000
    ]
end
