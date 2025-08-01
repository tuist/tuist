import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the TUIST_WEB=true when you start it:
#
#     TUIST_WEB=true bin/tuist start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if Tuist.Environment.web?() do
  config :tuist, TuistWeb.Endpoint, server: true
end

env = Tuist.Environment.env()
secrets = Tuist.Environment.decrypt_secrets()
secret_key_base = Tuist.Environment.secret_key_base(secrets)

if env != :test do
  config :tuist, TuistWeb.Endpoint, secret_key_base: secret_key_base
end

if Enum.member?([:prod, :stag, :can], env) do
  config :tuist,
    ecto_repos:
      [Tuist.Repo] ++
        if(Tuist.Environment.clickhouse_configured?(secrets),
          do: [Tuist.IngestRepo],
          else: []
        ),
    generators: [timestamp_type: :utc_datetime],
    api_pipeline_producer_module: OffBroadwayMemory.Producer,
    api_pipeline_producer_options: [buffer: :api_data_pipeline_in_memory_buffer]

  if Tuist.Environment.clickhouse_configured?(secrets) do
    config :tuist, Tuist.ClickHouseRepo,
      url: Tuist.Environment.clickhouse_url(secrets),
      pool_size: Tuist.Environment.clickhouse_pool_size(secrets),
      queue_target: Tuist.Environment.clickhouse_queue_target(secrets),
      queue_interval: Tuist.Environment.clickhouse_queue_interval(secrets)

    config :tuist, Tuist.IngestRepo,
      url: Tuist.Environment.clickhouse_url(secrets),
      pool_size: Tuist.Environment.clickhouse_pool_size(secrets),
      queue_target: Tuist.Environment.clickhouse_queue_target(secrets),
      queue_interval: Tuist.Environment.clickhouse_queue_interval(secrets)
  end

  database_url =
    Tuist.Environment.database_url(secrets) ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  parsed_url = URI.parse(database_url)
  [username, password] = String.split(parsed_url.userinfo, ":")

  socket_opts =
    if Tuist.Environment.use_ipv6?(secrets) in ~w(true 1),
      do: [:inet6, {:keepalive, true}],
      else: [{:keepalive, true}]

  database_options = [
    pool_size: Tuist.Environment.database_pool_size(secrets),
    queue_target: Tuist.Environment.database_queue_target(secrets),
    queue_interval: Tuist.Environment.database_queue_interval(secrets),
    database: String.replace_prefix(parsed_url.path, "/", ""),
    username: username,
    password: password,
    hostname: parsed_url.host,
    socket_options: socket_opts,
    parameters: [
      tcp_keepalives_idle: "60",
      tcp_keepalives_interval: "30",
      tcp_keepalives_count: "3"
    ]
  ]

  database_options =
    if Tuist.Environment.use_ssl_for_database?() do
      Keyword.put(database_options, :ssl,
        server_name_indication: to_charlist(parsed_url.host),
        verify: :verify_none
      )

      # TODO: Add proper certificate verification
    else
      database_options
    end

  port = "8080"
  app_url = Tuist.Environment.app_url([route_type: :app], secrets)
  %{host: app_url_host, port: app_url_port, scheme: app_url_scheme} = URI.parse(app_url)

  # We migrated from {...}.tuist.io to {...}.tuist.dev, so we need to make sure we include
  # the old origins for a while to avoid breaking the app for users that have the old origins
  checkable_origins =
    [app_url] ++
      case {Tuist.Environment.tuist_hosted?(), Tuist.Environment.env()} do
        {true, :stag} -> ["https://staging.tuist.io"]
        {true, :prod} -> ["https://cloud.tuist.io"]
        {true, :can} -> ["https://canary.tuist.io"]
        _ -> []
      end

  config :logger, level: Tuist.Environment.log_level()

  config :tuist, Tuist.Repo, database_options

  config :tuist, TuistWeb.Endpoint,
    url: [host: app_url_host, port: app_url_port, scheme: app_url_scheme],
    check_origin: checkable_origins,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ]

  config :tuist, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

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
  appsignal_name = "Tuist"

  config :appsignal, :config,
    otp_app: :tuist,
    name: appsignal_name,
    push_api_key: Tuist.Environment.app_signal_push_api_key(secrets),
    env: env,
    active: true,
    ignore_errors: [
      "TuistWeb.Errors.BadRequestError",
      "TuistWeb.Errors.NotFoundError",
      "TuistWeb.Errors.TooManyRequestsError",
      "TuistWeb.Errors.UnauthorizedError"
    ],
    request_headers: ~w(
      accept accept-charset accept-encoding accept-language cache-control
      connection content-length path-info range request-method
      request-uri server-name server-port server-protocol
      x-request-id
      x-tuist-cloud-cli-version x-tuist-cloud-cli-release-date
      x-tuist-cli-version x-tuist-cli-release-date
    )
end

# Ex.AWS
if Tuist.Environment.env() not in [:test] do
  %{host: s3_endpoint_host} = secrets |> Tuist.Environment.s3_endpoint() |> URI.parse()

  config :ex_aws, :req_opts,
    receive_timeout: to_timeout(second: Tuist.Environment.s3_request_timeout(secrets)),
    pool_timeout: to_timeout(second: Tuist.Environment.s3_pool_timeout(secrets))

  config :ex_aws, :s3,
    scheme: "https://",
    host: s3_endpoint_host

  config :ex_aws, :s3, virtual_host: Tuist.Environment.s3_virtual_host()

  config :ex_aws,
    http_client: Tuist.AWS.Client

  config :ex_aws,
    region: Tuist.Environment.s3_region(secrets)

  case Tuist.Environment.s3_authentication_method(secrets) do
    :env_access_key_id_and_secret_access_key ->
      config :ex_aws,
        secret_access_key: Tuist.Environment.s3_secret_access_key(secrets),
        access_key_id: Tuist.Environment.s3_access_key_id(secrets)

    :aws_web_identity_token_from_env_vars ->
      config :ex_aws,
        secret_access_key: [{:awscli, "profile_name", 30}],
        access_key_id: [{:awscli, "profile_name", 30}],
        awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter

    _ ->
      nil
      # Noop
  end
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
    domain: Tuist.Environment.smtp_domain(secrets),
    base_uri: base_uri
end

# Oban
oban_queues =
  if Tuist.Environment.web?() and !Tuist.Environment.worker?(), do: [], else: [default: 10]

oban_plugins =
  if Tuist.Environment.web?() and !Tuist.Environment.worker?(),
    do: [],
    else: [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
      {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
      {Oban.Plugins.Cron,
       crontab:
         if(Tuist.Environment.tuist_hosted?() and env == :prod,
           do: [
             {"0 10 * * 1-5", Tuist.Ops.DailySlackReportWorker},
             {"0 * * * 1-5", Tuist.Ops.HourlySlackReportWorker},
             {"@hourly", Tuist.Registry.Swift.Workers.UpdatePackagesWorker},
             {"@hourly", Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorker},
             {"@daily", Tuist.Billing.UpdateAllCustomersRemoteCacheHitsCountWorker},
             {"@daily", Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker},
             {"@daily", Tuist.Mautic.Workers.SyncCompaniesAndContactsWorker}
           ],
           else: []
         )}
    ]

config :tuist, Oban,
  queues: oban_queues,
  plugins: oban_plugins

# Guardian
config :tuist, Tuist.Guardian,
  issuer: "tuist",
  secret_key: Tuist.Environment.secret_key_tokens(secrets)

# Prometheus
config :tuist, Tuist.PromEx,
  disabled: Tuist.Environment.env() == :test,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  # Larger numbers might lead to internal tasks timing out.
  # By keeping it small we might loose some granularity of the data, but I think it's a good tradeoff.
  # Use default value to avoid over-compacting
  ets_flush_interval: 500,
  metrics_server: [
    port: 9091,
    auth_strategy: :none
  ]

# Error tracker
if not Tuist.Environment.tuist_hosted?() do
  config :error_tracker, enabled: true
end
