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
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tuist start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tuist, TuistWeb.Endpoint, server: true
end

env = Tuist.Environment.env()
secrets = Tuist.Environment.decrypt_secrets()[env]
secret_key_base = Tuist.Environment.secret_key_base(secrets)

if env != :test do
  config :tuist, TuistWeb.Endpoint, secret_key_base: secret_key_base
end

if [:prod, :stag, :can] |> Enum.member?(env) do
  config :logger, level: Tuist.Environment.log_level()

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  parsed_url = URI.parse(database_url)
  [username, password] = parsed_url.userinfo |> String.split(":")
  maybe_ipv6 = if Tuist.Environment.use_ipv6?(secrets) in ~w(true 1), do: [:inet6], else: []

  database_options = [
    pool_size: Tuist.Environment.database_pool_size(secrets),
    database: parsed_url.path |> String.replace_prefix("/", ""),
    username: username,
    password: password,
    hostname: parsed_url.host,
    socket_options: maybe_ipv6
  ]

  database_options =
    if Tuist.Environment.use_ssl_for_database?() do
      database_options
      |> Keyword.put(:ssl, true)
      |> Keyword.put(:ssl_opts,
        # TODO: Add proper certificate verification
        server_name_indication: to_charlist(parsed_url.host),
        verify: :verify_none
      )
    else
      database_options
    end

  config :tuist, Tuist.Repo, database_options

  port = "8080"
  config :tuist, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  app_url = Tuist.Environment.app_url(secrets)
  %{host: app_url_host, port: app_url_port, scheme: app_url_scheme} = URI.parse(app_url)

  config :tuist, TuistWeb.Endpoint,
    url: [host: app_url_host, port: app_url_port, scheme: app_url_scheme],
    check_origin: [app_url],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
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
    active: [:prod, :stag, :can] |> Enum.member?(env),
    ignore_errors: [
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

if Tuist.Environment.s3_configured?(secrets) and not Tuist.Environment.on_premise?() do
  %{host: s3_endpoint_host} = Tuist.Environment.s3_endpoint(secrets) |> URI.parse()

  aws_opts = [
    access_key_id: [
      Tuist.Environment.s3_access_key_id(secrets),
      {:awscli, Tuist.Environment.aws_profile(secrets), 30}
    ],
    secret_access_key: [
      Tuist.Environment.s3_secret_access_key(secrets),
      {:awscli, Tuist.Environment.aws_profile(secrets), 30}
    ],
    s3: [
      # Cloudflare R2 requires HTTPS
      scheme: "https://",
      host: s3_endpoint_host
    ],
    # Cloudflare R2 does not require a region, but ExAws needs a value here
    region: Tuist.Environment.aws_region(secrets)
  ]

  aws_opts =
    if Tuist.Environment.aws_use_session_token?(secrets) do
      Keyword.put(aws_opts, :security_token, [
        Tuist.Environment.aws_session_token(secrets),
        {:awscli, Tuist.Environment.aws_profile(secrets), 30}
      ])
    else
      aws_opts
    end

  config :ex_aws, aws_opts
  config :ex_aws, http_client: ExAws.Request.Req

  config :ex_aws, :req_opts,
    # 30 seconds
    receive_timeout: 30_000,
    # 5 seconds
    pool_timeout: 5_000
end

# Stripe config
if Tuist.Environment.stripe_configured?(secrets) do
  config :stripity_stripe,
    api_key: Tuist.Environment.stripe_api_key(secrets),
    signing_secret: Tuist.Environment.stripe_endpoint_secret(secrets)
end

# Omniauth

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: Tuist.Environment.github_app_client_id(secrets),
  client_secret: Tuist.Environment.github_app_client_secret(secrets)

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: Tuist.Environment.google_oauth_client_id(secrets),
  client_secret: Tuist.Environment.google_oauth_client_secret(secrets)

config :ueberauth, Ueberauth.Strategy.Okta.OAuth,
  site: Tuist.Environment.okta_site(secrets),
  client_id: Tuist.Environment.okta_client_id(secrets),
  client_secret: Tuist.Environment.okta_client_secret(secrets)

# Mailgun configuration
if Tuist.Environment.mail_configured?(secrets) do
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
config :tuist, Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab:
       [
         {"@hourly", Tuist.CommandEvents.UpdateCacheEventCountWorker},
         {"@daily", Tuist.Billing.UpdateRemoteCacheHitWorker},
         {"@daily", Tuist.Accounts.Workers.UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker}
       ] ++
         if(not Tuist.Environment.on_premise?() and env == :prod,
           do: [{"0 10 * * 1-5", Tuist.Ops.DailySlackReportWorker}],
           else: []
         )}
  ]

# Prometheus
config :tuist, Tuist.PromEx,
  disabled: Tuist.Environment.env() == :test,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: [
    port: 9091,
    auth_strategy: :none
  ]

# Guardian
config :tuist, Tuist.Guardian,
  issuer: "tuist",
  secret_key: Tuist.Environment.secret_key_tokens(secrets)
