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
#     PHX_SERVER=true bin/tuist_cloud start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tuist_cloud, TuistCloudWeb.Endpoint, server: true
end

env = TuistCloud.Environment.env()
secrets = TuistCloud.Environment.decrypt_secrets()[env]
secret_key_base = TuistCloud.Environment.secret_key_base(secrets)

if env != :test do
  config :tuist_cloud, TuistCloudWeb.Endpoint, secret_key_base: secret_key_base
end

if [:prod, :stag, :can] |> Enum.member?(env) do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  parsed_url = URI.parse(database_url)
  [username, password] = parsed_url.userinfo |> String.split(":")
  maybe_ipv6 = if TuistCloud.Environment.use_ipv6?(secrets) in ~w(true 1), do: [:inet6], else: []

  database_options = [
    pool_size: TuistCloud.Environment.database_pool_size(secrets),
    database: parsed_url.path |> String.replace_prefix("/", ""),
    username: username,
    password: password,
    hostname: parsed_url.host,
    socket_options: maybe_ipv6
  ]

  database_options =
    if TuistCloud.Environment.use_ssl_for_database?() do
      database_options
      |> Keyword.put(:ssl, true)
      |> Keyword.put(:ssl_opts,
        # TODO: Add proper certificate verification
        server_name_indication: to_char_list(parsed_url.host),
        verify: :verify_none
      )
    else
      database_options
    end

  config :tuist_cloud, TuistCloud.Repo, database_options

  port = "8080"
  config :tuist_cloud, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  app_url = TuistCloud.Environment.app_url(secrets)
  %{host: app_url_host, port: app_url_port, scheme: app_url_scheme} = URI.parse(app_url)

  config :tuist_cloud, TuistCloudWeb.Endpoint,
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
  #     config :tuist_cloud, TuistCloudWeb.Endpoint,
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
  #     config :tuist_cloud, TuistCloudWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :tuist_cloud, TuistCloud.Mailer,
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

appsignal_name = "Tuist Cloud Phoenix"

if !TuistCloud.Environment.on_premise?() do
  config :appsignal, :config,
    otp_app: :tuist_cloud,
    name: appsignal_name,
    push_api_key: TuistCloud.Environment.app_signal_push_api_key(secrets),
    env: env,
    active: [:prod, :stag, :can] |> Enum.member?(env),
    request_headers: ~w(
      accept accept-charset accept-encoding accept-language cache-control
      connection content-length path-info range request-method
      request-uri server-name server-port server-protocol
      x-request-id
      x-tuist-cloud-cli-version x-tuist-cloud-cli-release-date
    )
else
  config :appsignal, :config,
    otp_app: :tuist_cloud,
    name: appsignal_name,
    env: env,
    active: false
end

# Stripe config
if TuistCloud.Environment.stripe_configured?(secrets) do
  config :stripity_stripe,
    api_key: TuistCloud.Environment.stripe_api_key(secrets),
    signing_secret: TuistCloud.Environment.stripe_endpoint_secret(secrets)
end

# License
if TuistCloud.Environment.on_premise?() do
  with {:license, {:ok, license}} <- {:license, TuistCloud.Native.license()},
       {:expired, false} <- {:expired, TuistCloud.Native.License.expired?(license)} do
    config :tuist_cloud, :license, license
  else
    {:license, {:error, error}} ->
      raise """
      We couldn't boot up the server because we couldn't load the license due to the following error: #{error}
      """

    {:expired, true} ->
      raise """
      The license has expired. Please contact contact@tuist.io to renew it.
      """
  end
end

# Omniauth

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: TuistCloud.Environment.github_oauth_id(secrets),
  client_secret: TuistCloud.Environment.github_oauth_secret(secrets)

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: TuistCloud.Environment.google_oauth_client_id(secrets),
  client_secret: TuistCloud.Environment.google_oauth_client_secret(secrets)

# Mailgun configuration
if TuistCloud.Environment.mail_configured?(secrets) do
  base_uri =
    cond do
      env in [:prod, :can, :stag] -> "https://api.eu.mailgun.net/v3"
      env in [:dev] -> "https://api.mailgun.net/v3"
    end

  config :tuist_cloud, TuistCloud.Mailer,
    adapter: Bamboo.MailgunAdapter,
    api_key: TuistCloud.Environment.mailgun_api_key(secrets),
    domain: TuistCloud.Environment.smtp_domain(secrets),
    base_uri: base_uri
end

# Oban
config :tuist_cloud, Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab:
       [
         {"@hourly", TuistCloud.CommandEvents.UpdateCacheEventCountWorker}
       ] ++
         if(not TuistCloud.Environment.on_premise?() and env == :prod,
           do: [{"0 10 * * 1-5", TuistCloud.Ops.DailySlackReportWorker}],
           else: []
         )}
  ]
