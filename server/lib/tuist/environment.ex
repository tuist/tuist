defmodule Tuist.Environment do
  @moduledoc false

  # Baked at compile time. Production images build with MIX_ENV=prod and
  # then pick a runtime deployment target via TUIST_DEPLOY_ENV (see env/0)
  # so one image can serve canary, staging, or production. Test/dev
  # builds ignore TUIST_DEPLOY_ENV so tests can't accidentally flip into
  # a prod-like mode.
  @compile_env Mix.env()
  @dev_all_locales Application.compile_env(:tuist, :dev_all_locales, false)

  @runtime_envs ~w(prod can stag)
  @agent_auth_default_trusted_providers [
    %{
      "issuer" => "https://auth0.openai.com/",
      "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json"
    }
  ]

  # Every supported pod role. `mode/0` raises on any other value of
  # TUIST_MODE so a deployment-manifest typo (`processsor`, `ingest`,
  # ...) fails the pod fast at boot rather than landing it in `:web`
  # silently — exactly the failure mode that previously masked the
  # xcresult-processor leader-election bug.
  @modes [:web, :processor, :xcresult_processor]

  @doc """
  All pod roles `mode/0` may return. Stable list — used by
  `Tuist.Oban.RuntimeConfig` tests to assert that no future role
  accidentally regains leader eligibility or the full crontab.
  """
  def modes, do: @modes

  def env do
    with :prod <- @compile_env,
         deploy_env when deploy_env in @runtime_envs <- System.get_env("TUIST_DEPLOY_ENV") do
      String.to_existing_atom(deploy_env)
    else
      _ -> @compile_env
    end
  end

  def server_version_identifier do
    System.get_env("TUIST_SERVER_VERSION_IDENTIFIER") ||
      if dev?() do
        case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"]) do
          {branch, 0} -> String.trim(branch)
          _ -> nil
        end
      end
  end

  @doc ~S"""
  Returns an list with all the supported environments.
  """
  def all_envs, do: [:dev, :test, :can, :stag, :prod]

  def test? do
    @compile_env == :test
  end

  def dev? do
    @compile_env == :dev
  end

  def stag? do
    env() == :stag
  end

  def can? do
    env() == :can
  end

  def prod? do
    env() == :prod
  end

  @doc """
  Worktree suffix from `TUIST_DEV_INSTANCE`, set by the mise
  `dev_instance_env.sh` hook. Used to scope ports, DB names, kind
  cluster names, and similar per-worktree resources so multiple
  worktrees can run side by side without colliding. Returns 0 when
  unset (CI, ad-hoc scripts) or when the value isn't a valid integer.
  """
  def dev_instance_suffix do
    case System.get_env("TUIST_DEV_INSTANCE") do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {n, ""} -> n
          _ -> 0
        end

      _ ->
        0
    end
  end

  def truthy?(value) do
    Enum.member?(["1", "true", "TRUE", "yes", "YES"], value)
  end

  @doc """
  Pod role. Controls which subsystems the BEAM brings up at boot:

    * `:web` (default) — full Phoenix endpoint, every Oban queue, every
      ingestion buffer. What the existing server pods run.
    * `:processor` — no Phoenix listener, narrowed Oban queue set to
      `:process_build`. Booted by processor-deployment.yaml.
    * `:xcresult_processor` — no Phoenix listener, Oban queue set
      narrowed to `:process_xcresult`. Runs inside a Tart VM on the
      macOS Mac mini fleet (the only place the macOS-only xcresult NIF
      can load). Booted by xcresult-processor-deployment.yaml.

  Read once from `TUIST_MODE`. Add new modes here when the supervision tree
  needs another shape (e.g. a future `:scheduler` or `:ingest`).
  """
  def mode, do: mode(System.get_env("TUIST_MODE"))

  @doc """
  Pure variant of `mode/0` that takes the raw `TUIST_MODE` value
  directly. Exposed so callers (tests, future config tooling) can
  exercise the parser without stubbing `System.get_env/1`.
  """
  def mode(nil), do: :web
  def mode(""), do: :web
  def mode("web"), do: :web
  def mode("processor"), do: :processor
  def mode("xcresult_processor"), do: :xcresult_processor

  def mode(other) do
    raise """
    Unknown TUIST_MODE=#{inspect(other)}.
    Expected one of #{inspect(@modes)}, or unset/empty for #{inspect(:web)}.
    """
  end

  def web?, do: mode() == :web

  def processor_mode?, do: mode() == :processor

  def xcresult_processor_mode?, do: mode() == :xcresult_processor

  def database_url(secrets \\ secrets()) do
    System.get_env("DATABASE_URL") || get([:database_url], secrets)
  end

  def migration_database_url do
    case System.get_env("TUIST_MIGRATION_DATABASE_URL") do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  def database_runtime_role do
    case System.get_env("TUIST_DATABASE_RUNTIME_ROLE") do
      role when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end

  def database_config_from_url(url) do
    parsed_url = URI.parse(url)

    [username, password] =
      parsed_url.userinfo
      |> String.split(":", parts: 2)
      |> Enum.map(&URI.decode/1)

    [
      database: String.replace_prefix(parsed_url.path, "/", ""),
      username: username,
      password: password,
      hostname: parsed_url.host,
      port: parsed_url.port || 5432
    ]
  end

  def ipv4_database_url(secrets \\ secrets()) do
    System.get_env("TUIST_IPV4_DATABASE_URL") || get([:ipv4_database_url], secrets)
  end

  def tuist_hosted? do
    truthy?(System.get_env("TUIST_CLOUD_HOSTED", "0")) or
      truthy?(System.get_env("TUIST_HOSTED", "0"))
  end

  def test_user_login_enabled? do
    dev?() or truthy?(System.get_env("TUIST_TEST_USER_LOGIN_ENABLED", "0"))
  end

  def dev_all_locales?, do: @dev_all_locales

  def dev_single_locale?, do: dev?() and not dev_all_locales?()

  def log_level do
    "TUIST_LOG_LEVEL" |> System.get_env("info") |> String.to_atom()
  end

  def use_ssl_for_database? do
    truthy?(System.get_env("TUIST_USE_SSL_FOR_DATABASE", "1"))
  end

  def dev_use_remote_storage? do
    not dev?() or truthy?(System.get_env("TUIST_DEV_USE_REMOTE_STORAGE", "0"))
  end

  def kura_available_region_ids do
    "TUIST_KURA_AVAILABLE_REGIONS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_dedicated_gateway_account_handles do
    "TUIST_KURA_DEDICATED_GATEWAY_ACCOUNTS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_runtime_image_tag(secrets \\ secrets()) do
    System.get_env("TUIST_KURA_RUNTIME_IMAGE_TAG") || get([:kura, :runtime_image_tag], secrets)
  end

  def kura_tuist_base_url do
    System.get_env("TUIST_KURA_TUIST_BASE_URL")
  end

  def prometheus_enabled? do
    prometheus_enabled = System.get_env("TUIST_PROMETHEUS_ENABLED")

    if is_nil(prometheus_enabled) do
      not dev?() and not test?()
    else
      truthy?(prometheus_enabled)
    end
  end

  def license_key(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_KEY") || get([:license], secrets) ||
      get([:license, :key], secrets)
  end

  def license_certificate_base64(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_CERTIFICATE_BASE64") ||
      get([:license, :certificate, :base64], secrets)
  end

  def use_ipv6?(secrets \\ secrets()) do
    get([:use_ipv6], secrets)
  end

  def redis_conn_name do
    :redis
  end

  def redis_url(secrets \\ secrets()) do
    get([:redis_url], secrets)
  end

  def agent_auth_default_trusted_providers, do: @agent_auth_default_trusted_providers

  def agent_auth_trusted_providers(secrets \\ secrets()) do
    case System.get_env("TUIST_AGENT_AUTH_TRUSTED_PROVIDERS_JSON") ||
           get([:agent_auth, :trusted_providers], secrets) do
      providers when is_list(providers) ->
        providers

      providers_json when is_binary(providers_json) and providers_json != "" ->
        case JSON.decode(providers_json) do
          {:ok, providers} when is_list(providers) -> providers
          _ -> []
        end

      _ ->
        agent_auth_default_trusted_providers()
    end
  end

  def cache_endpoints(secrets \\ secrets()) do
    case get([:cache, :endpoints], secrets) do
      endpoints when is_binary(endpoints) ->
        split_endpoints(endpoints)

      _ ->
        nil
    end
  end

  def kura_endpoints(secrets \\ secrets(), env_value \\ System.get_env("TUIST_KURA_ENDPOINTS")) do
    case endpoint_env_value(env_value) || get([:kura, :endpoints], secrets) do
      endpoints when is_binary(endpoints) ->
        split_endpoints(endpoints)

      _ ->
        nil
    end
  end

  def plain_authentication_secret(secrets \\ secrets()) do
    get([:plain, :authentication_secret], secrets)
  end

  def database_pool_size(secrets \\ secrets()) do
    case get([:database, :pool_size], secrets) do
      pool_size when is_binary(pool_size) -> String.to_integer(pool_size)
      _ -> 10
    end
  end

  def database_queue_target(secrets \\ secrets()) do
    case get([:database, :queue_target], secrets) do
      queue_target when is_binary(queue_target) -> String.to_integer(queue_target)
      _ -> 200
    end
  end

  def database_queue_interval(secrets \\ secrets()) do
    case get([:database, :queue_interval], secrets) do
      queue_interval when is_binary(queue_interval) -> String.to_integer(queue_interval)
      _ -> 2000
    end
  end

  def analytics_enabled?(secrets \\ secrets()) do
    not is_nil(posthog_api_key(secrets)) && not is_nil(posthog_url(secrets))
  end

  def error_tracking_enabled? do
    truthy?(System.get_env("TUIST_FORCE_ERROR_TRACKING")) ||
      (tuist_hosted?() and Enum.member?([:prod, :stag, :can], env()))
  end

  def version do
    case System.get_env("TUIST_VERSION") do
      nil -> to_string(Application.spec(:tuist)[:vsn])
      "" -> to_string(Application.spec(:tuist)[:vsn])
      version -> version
    end
  end

  @doc """
  Email domain whose confirmed members are Tuist operators. Used only
  as a routing heuristic (redirect a non-member operator to the ops
  reason form vs. 404 a regular customer); the real gates are
  ops.tuist.dev's Pomerium/Google-OIDC and the offline grant
  verification. Defaults to `tuist.dev`.
  """
  def operator_email_domain(secrets \\ secrets()) do
    get([:operator_email_domain], secrets, default_value: "tuist.dev")
  end

  @doc """
  PEM-encoded Ed25519 PUBLIC key used to verify operator access grant
  tokens minted by ops.tuist.dev. nil when unset, in which case grant
  verification fails closed (no operator grants are honoured).
  """
  def operator_grant_public_key(secrets \\ secrets()) do
    get([:operator_grant, :public_key], secrets)
  end

  @doc """
  The `aud` claim required on operator grant tokens. Pinned per
  environment so a token minted for a different env can't be replayed.
  Must match ops.tuist.dev's `OPERATOR_GRANT_AUDIENCE`.
  """
  def operator_grant_audience(secrets \\ secrets()) do
    get([:operator_grant, :audience], secrets, default_value: "tuist-server")
  end

  @doc """
  Maximum allowed lifetime (`exp - iat`, seconds) of an operator grant
  token. A token claiming a longer lifetime is rejected, so a
  compromised signer can't mint a long-lived grant. Defaults to 1h.
  """
  def operator_grant_max_ttl_seconds(secrets \\ secrets()) do
    case get([:operator_grant, :max_ttl_seconds], secrets, default_value: 3600) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc """
  Base URL of the ops.tuist.dev reason form a non-member operator is
  redirected to before they can access a customer project. nil by
  default: the redirect is opt-in per environment and stays off until
  ops.tuist.dev is Pomerium-fronted and routes `/grants` with a
  matching audience. Offline grant verification does not depend on this.
  """
  def ops_reason_form_url(secrets \\ secrets()) do
    get([:ops, :reason_form_url], secrets, default_value: nil)
  end

  def posthog_api_key(secrets \\ secrets()) do
    get([:posthog, :api_key], secrets)
  end

  def posthog_url(secrets \\ secrets()) do
    get([:posthog, :url], secrets)
  end

  def s3_authentication_method(secrets \\ secrets()) do
    case get([:s3, :authentication_method], secrets) do
      authentication_method when is_binary(authentication_method) ->
        String.to_atom(authentication_method)

      _ ->
        :env_access_key_id_and_secret_access_key
    end
  end

  def s3_connect_timeout(secrets \\ secrets()) do
    case get([:s3, :connect_timeout], secrets) do
      "infinity" ->
        :infinity

      connect_timeout when is_binary(connect_timeout) ->
        to_timeout(second: String.to_integer(connect_timeout))

      _ ->
        # Standard timeout for establishing connections
        to_timeout(second: 10)
    end
  end

  def s3_receive_timeout(secrets \\ secrets()) do
    case get([:s3, :receive_timeout], secrets) do
      "infinity" ->
        :infinity

      receive_timeout when is_binary(receive_timeout) ->
        to_timeout(second: String.to_integer(receive_timeout))

      _ ->
        # Generous receive timeout for large file downloads
        to_timeout(minute: 1)
    end
  end

  def s3_pool_timeout(secrets \\ secrets()) do
    case get([:s3, :pool_timeout], secrets) do
      "infinity" ->
        :infinity

      pool_timeout when is_binary(pool_timeout) ->
        to_timeout(second: String.to_integer(pool_timeout))

      _ ->
        # Standard pool timeout
        to_timeout(second: 5)
    end
  end

  def s3_pool_max_idle_time(secrets \\ secrets()) do
    case get([:s3, :pool_max_idle_time], secrets) do
      "infinity" ->
        :infinity

      pool_max_idle_time when is_binary(pool_max_idle_time) ->
        to_timeout(second: String.to_integer(pool_max_idle_time))

      _ ->
        # Keep the connections alive for reusability
        :infinity
    end
  end

  def s3_pool_size(secrets \\ secrets()) do
    case get([:s3, :pool_size], secrets) do
      pool_size when is_binary(pool_size) -> String.to_integer(pool_size)
      # Since we use http2, which allows multi-plexing, the size of the pool can be smaller
      _ -> 500
    end
  end

  def s3_pool_count(secrets \\ secrets()) do
    case get([:s3, :pool_count], secrets) do
      pool_count when is_binary(pool_count) -> String.to_integer(pool_count)
      _ -> System.schedulers_online()
    end
  end

  def s3_protocols(secrets \\ secrets()) do
    case get([:s3, :protocol], secrets) do
      protocol when is_binary(protocol) -> [String.to_atom(protocol)]
      _ -> [:http1]
    end
  end

  def s3_access_key_id(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_ACCESS_KEY_ID") ||
        System.get_env("AWS_ACCESS_KEY_ID") ||
        get([:s3, :access_key_id], secrets)
    else
      "minio"
    end
  end

  def s3_secret_access_key(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_SECRET_ACCESS_KEY") ||
        System.get_env("AWS_SECRET_ACCESS_KEY") ||
        get([:s3, :secret_access_key], secrets)
    else
      "minio1234"
    end
  end

  def s3_region(secrets \\ secrets()) do
    System.get_env("TUIST_S3_REGION") ||
      System.get_env("AWS_REGION") ||
      get([:s3, :region], secrets) ||
      "auto"
  end

  def s3_bucket_name(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_BUCKET_NAME") || get([:s3, :bucket_name], secrets)
    else
      "tuist-development"
    end
  end

  def cache_s3_bucket_name(secrets \\ secrets()) do
    System.get_env("TUIST_CACHE_S3_BUCKET_NAME") ||
      System.get_env("S3_BUCKET") ||
      get([:cache, :s3, :bucket], secrets)
  end

  def cache_xcode_s3_bucket_name(secrets \\ secrets()) do
    System.get_env("TUIST_CACHE_XCODE_S3_BUCKET_NAME") ||
      System.get_env("S3_XCODE_CACHE_BUCKET") ||
      get([:cache, :s3, :xcode_cache_bucket], secrets) ||
      cache_s3_bucket_name(secrets)
  end

  def s3_endpoint(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_ENDPOINT") || get([:s3, :endpoint], secrets)
    else
      System.get_env("TUIST_LOCAL_S3_ENDPOINT") ||
        case System.get_env("TUIST_MINIO_API_PORT") do
          port when is_binary(port) -> "http://localhost:#{port}"
          _ -> get([:local_s3_endpoint], secrets) || "http://localhost:9095"
        end
    end
  end

  def s3_virtual_host(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      case System.get_env("TUIST_S3_VIRTUAL_HOST") do
        nil -> [:s3, :virtual_host] |> get(secrets) |> truthy?()
        value -> truthy?(value)
      end
    else
      false
    end
  end

  def s3_bucket_as_host(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      case System.get_env("TUIST_S3_BUCKET_AS_HOST") do
        nil -> [:s3, :bucket_as_host] |> get(secrets) |> truthy?()
        value -> truthy?(value)
      end
    else
      false
    end
  end

  def s3_ca_cert_pem(secrets \\ secrets()) do
    System.get_env("TUIST_S3_CA_CERT_PEM") || get([:s3, :ca_cert_pem], secrets)
  end

  def slack_tuist_token(secrets \\ secrets()) do
    get([:slack, :tuist, :token], secrets)
  end

  def slack_client_id(secrets \\ secrets()) do
    get([:slack, :client_id], secrets)
  end

  def slack_client_secret(secrets \\ secrets()) do
    get([:slack, :client_secret], secrets)
  end

  def slack_configured?(secrets \\ secrets()) do
    slack_client_id(secrets) != nil and slack_client_secret(secrets) != nil
  end

  def stripe_api_key(secrets \\ secrets()) do
    get([:stripe, :secret_key], secrets)
  end

  def stripe_publishable_key(secrets \\ secrets()) do
    get([:stripe, :publishable_key], secrets)
  end

  def stripe_endpoint_secret(secrets \\ secrets()) do
    get([:stripe, :endpoint_secret], secrets)
  end

  def stripe_configured?(secrets \\ secrets()) do
    stripe_api_key(secrets) != nil and stripe_publishable_key(secrets) != nil and
      stripe_endpoint_secret(secrets) != nil
  end

  def stripe_prices(secrets \\ secrets()) do
    prices = get([:stripe, :prices], secrets)
    prices_base64_json = get([:stripe, :prices, :base64, :json], secrets)

    cond do
      is_map(prices) ->
        prices

      is_binary(prices_base64_json) ->
        prices_base64_json |> Base.decode64!() |> JSON.decode!()

      true ->
        nil
    end
  end

  def minio_console_port(secrets \\ secrets()) do
    case System.get_env("TUIST_MINIO_CONSOLE_PORT") do
      port when is_binary(port) -> String.to_integer(port)
      _ -> get([:minio, :console_port], secrets, default_value: 9098)
    end
  end

  def mautic_username(secrets \\ secrets()) do
    get([:mautic, :username], secrets)
  end

  def mautic_password(secrets \\ secrets()) do
    get([:mautic, :password], secrets)
  end

  def loops_api_key(secrets \\ secrets()) do
    get([:loops, :api_key], secrets)
  end

  def github_token_update_package_releases(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES") ||
      get([:github, :token, :update_package_releases], secrets)
  end

  def github_token_update_packages(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_TOKEN_UPDATE_PACKAGES") ||
      get([:github, :token, :update_packages], secrets)
  end

  def github_app_name(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_NAME") || get([:github, :app_name], secrets)
  end

  def github_app_id(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_ID") || get([:github, :app_id], secrets)
  end

  def github_app_client_id(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_CLIENT_ID") ||
      get([:github, :app_client_id], secrets) || get([:github, :oauth_id], secrets)
  end

  def github_app_client_secret(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_CLIENT_SECRET") ||
      get([:github, :app_client_secret], secrets) || get([:github, :oauth_secret], secrets)
  end

  def github_app_private_key(secrets \\ secrets()) do
    base_64_key =
      System.get_env("TUIST_GITHUB_APP_PRIVATE_KEY_BASE64") ||
        get([:github, :app_private_key_base64], secrets)

    cond do
      is_binary(base_64_key) -> Base.decode64!(base_64_key)
      env_key = System.get_env("TUIST_GITHUB_APP_PRIVATE_KEY") -> env_key
      true -> get([:github, :app_private_key], secrets)
    end
  end

  def github_app_webhook_secret(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_WEBHOOK_SECRET") ||
      get([:github, :app_webhook_secret], secrets)
  end

  def github_oauth_configured?(secrets \\ secrets()) do
    github_app_client_id(secrets) != nil and github_app_client_secret(secrets) != nil
  end

  # The GitHub App used for VCS integration shares its client id/secret with
  # GitHub sign-in, so configuring VCS otherwise forces GitHub onto the login
  # page. This lever lets a self-hosted operator keep the App while turning the
  # sign-in method off.
  def github_auth_enabled? do
    truthy?(System.get_env("TUIST_GITHUB_AUTH_ENABLED", "1"))
  end

  def github_app_configured?(secrets \\ secrets()) do
    github_app_name(secrets) != nil and github_oauth_configured?(secrets) and
      github_app_private_key(secrets) != nil
  end

  def google_oauth_client_id(secrets \\ secrets()) do
    get([:google, :oauth_client_id], secrets)
  end

  def google_oauth_client_secret(secrets \\ secrets()) do
    get([:google, :oauth_client_secret], secrets)
  end

  def google_oauth_configured?(secrets \\ secrets()) do
    google_oauth_client_id(secrets) != nil and google_oauth_client_secret(secrets) != nil
  end

  def okta_site(secrets \\ secrets()) do
    get([:okta, :site], secrets)
  end

  def okta_oauth_configured?(secrets \\ secrets()) do
    get([:okta], secrets) != nil or
      Enum.any?(System.get_env(), fn {key, _value} -> String.starts_with?(key, "TUIST_OKTA_") end)
  end

  def apple_service_client_id(secrets \\ secrets()) do
    get([:apple, :service_client_id], secrets)
  end

  def apple_app_client_id(secrets \\ secrets()) do
    get([:apple, :app_client_id], secrets)
  end

  def apple_team_id(secrets \\ secrets()) do
    get([:apple, :team_id], secrets)
  end

  def apple_private_key_id(secrets \\ secrets()) do
    get([:apple, :private_key_id], secrets)
  end

  def apple_private_key(secrets \\ secrets()) do
    get([:apple, :private_key], secrets)
  end

  def apple_oauth_configured?(secrets \\ secrets()) do
    apple_service_client_id(secrets) != nil and apple_team_id(secrets) != nil and
      apple_private_key_id(secrets) != nil and apple_private_key(secrets) != nil
  end

  def mailgun_api_key(secrets \\ secrets()) do
    get([:mailgun, :api_key], secrets)
  end

  def mailing_domain(secrets \\ secrets()) do
    get([:mailing, :domain], secrets) || get([:smtp_settings, :domain], secrets)
  end

  def mailing_from_address(secrets \\ secrets()) do
    get([:mailing, :from_address], secrets) || get([:smtp_settings, :user_name], secrets)
  end

  def mailing_reply_to_address(secrets \\ secrets()) do
    get([:mailing, :reply_to_address], secrets)
  end

  def smtp_domain(secrets \\ secrets()) do
    get([:smtp_settings, :domain], secrets)
  end

  def smtp_user_name(secrets \\ secrets()) do
    get([:smtp_settings, :user_name], secrets)
  end

  def mail_configured?(secrets \\ secrets()) do
    mailgun_api_key(secrets) != nil and mailing_domain(secrets) != nil and
      mailing_from_address(secrets) != nil
  end

  def skip_email_confirmation?(secrets \\ secrets()) do
    case get([:skip_email_confirmation], secrets) do
      skip when is_binary(skip) ->
        truthy?(skip)

      _ ->
        # Default to true if email is not configured (e.g., air-gapped environments)
        not mail_configured?(secrets)
    end
  end

  def loki_url(secrets \\ secrets()) do
    get([:loki, :url], secrets)
  end

  def clickhouse_url(secrets \\ secrets()) do
    get([:clickhouse, :url], secrets)
  end

  def clickhouse_pool_size(secrets \\ secrets()) do
    case get([:clickhouse, :pool_size], secrets) do
      pool_size when is_binary(pool_size) -> String.to_integer(pool_size)
      _ -> database_pool_size(secrets)
    end
  end

  def clickhouse_queue_interval(secrets \\ secrets()) do
    case get([:clickhouse, :queue_interval], secrets) do
      queue_interval when is_binary(queue_interval) -> String.to_integer(queue_interval)
      _ -> database_queue_interval(secrets)
    end
  end

  def clickhouse_queue_target(secrets \\ secrets()) do
    case get([:clickhouse, :queue_target], secrets) do
      queue_target when is_binary(queue_target) -> String.to_integer(queue_target)
      _ -> database_queue_target(secrets)
    end
  end

  def anthropic_api_key(secrets \\ secrets()) do
    get([:anthropic, :api_key], secrets)
  end

  def openai_api_key(secrets \\ secrets()) do
    get([:openai, :api_key], secrets)
  end

  def cache_api_key(secrets \\ secrets()) do
    get([:cache_api_key], secrets)
  end

  def delegate_process_build? do
    truthy?(System.get_env("TUIST_DELEGATE_PROCESS_BUILD", "0"))
  end

  @doc """
  Whether the configured DATABASE_URL points at a transaction-mode pooler
  (PgBouncer, PgCat, etc.) rather than a direct Postgres endpoint. Toggles
  `prepare: :unnamed` and drops `tcp_keepalives_*` startup parameters in
  `runtime.exs` — both required for transaction-mode poolers to work,
  both unnecessary cost on direct connections.
  """
  def database_pooled? do
    truthy?(System.get_env("TUIST_DATABASE_POOLED", "0"))
  end

  def process_build_queue_concurrency do
    case System.get_env("TUIST_PROCESS_BUILD_QUEUE_CONCURRENCY") do
      value when is_binary(value) and value != "" -> String.to_integer(value)
      _ -> if processor_mode?(), do: 5, else: 2
    end
  end

  @doc """
  Whether the in-cluster Linux server pod should drop `:process_xcresult`
  from its Oban queue list because dedicated macOS xcresult-processor pods
  are running.

  The chart sets this whenever `xcresultProcessor.enabled: true`. Without
  it, the server's local Oban worker would race the dedicated processors
  on SKIP LOCKED — and crash on `xcresulttool` not being available since
  Linux pods don't ship the macOS-only NIF.
  """
  def delegate_process_xcresult? do
    truthy?(System.get_env("TUIST_DELEGATE_PROCESS_XCRESULT", "0"))
  end

  def process_xcresult_queue_concurrency do
    case System.get_env("TUIST_PROCESS_XCRESULT_QUEUE_CONCURRENCY") do
      value when is_binary(value) and value != "" -> String.to_integer(value)
      _ -> if xcresult_processor_mode?(), do: 4, else: 2
    end
  end

  def clickhouse_flush_interval_ms(secrets \\ secrets()) do
    case get([:clickhouse, :flush_interval_ms], secrets) do
      flush_interval when is_binary(flush_interval) -> String.to_integer(flush_interval)
      _ -> 5000
    end
  end

  def clickhouse_max_buffer_size(secrets \\ secrets()) do
    case get([:clickhouse, :max_buffer_size], secrets) do
      max_buffer_size when is_binary(max_buffer_size) -> String.to_integer(max_buffer_size)
      _ -> 1_000_000
    end
  end

  def clickhouse_buffer_pool_size(secrets \\ secrets()) do
    case get([:clickhouse, :buffer_pool_size], secrets) do
      buffer_pool_size when is_binary(buffer_pool_size) -> String.to_integer(buffer_pool_size)
      _ -> 5
    end
  end

  def clickhouse_max_threads(secrets \\ secrets()) do
    case get([:clickhouse, :max_threads], secrets) do
      max_threads when is_binary(max_threads) -> String.to_integer(max_threads)
      _ -> 4
    end
  end

  @doc """
  Returns additional Finch pools from the TUIST_ADDITIONAL_FINCH_POOLS environment variable.

  The value should be a base64-encoded JSON object where keys are endpoint URLs
  and values are pool configuration options.

  Example JSON (before base64 encoding):
  {
    "https://s3.us-west-2.amazonaws.com": {"size": 500, "count": 4},
    "https://s3.us-east-1.amazonaws.com": {"size": 500}
  }

  Supported pool options:
  - size: Number of connections per pool (default: 100)
  - count: Number of pools (default: System.schedulers_online())
  """
  def additional_finch_pools(secrets \\ secrets()) do
    case get([:additional_finch_pools], secrets) do
      nil ->
        %{}

      base64_json ->
        case Base.decode64(base64_json) do
          {:ok, json} ->
            case JSON.decode(json) do
              {:ok, pools} when is_map(pools) -> pools
              _ -> %{}
            end

          :error ->
            %{}
        end
    end
  end

  @doc """
  Returns the bucket size for the authentication rate limiter.

  This configures the maximum number of authentication requests allowed
  in the rate limit window. The bucket size determines how many requests
  can be made before rate limiting kicks in.

  The default values are:
  - 100 requests for canary environments (to allow higher throughput testing)
  - 10 requests for other environments (production, staging, dev)

  This can be overridden via:
  - Environment variable: TUIST_AUTH_RATE_LIMIT_BUCKET_SIZE
  - Secrets configuration: auth_rate_limit.bucket_size
  """
  def auth_rate_limit_bucket_size(secrets \\ secrets()) do
    case get([:auth_rate_limit, :bucket_size], secrets) do
      bucket_size when is_binary(bucket_size) -> String.to_integer(bucket_size)
      _ -> if can?(), do: 100, else: 10
    end
  end

  @doc """
  Returns the bucket size for the MCP rate limiter.

  The default values are:
  - 600 requests for canary environments
  - 120 requests for other environments (production, staging, dev)
  """
  def mcp_rate_limit_bucket_size(secrets \\ secrets()) do
    case get([:mcp_rate_limit, :bucket_size], secrets) do
      bucket_size when is_binary(bucket_size) -> String.to_integer(bucket_size)
      _ -> if can?(), do: 600, else: 120
    end
  end

  def app_url(opts \\ [], secrets \\ secrets()) do
    path = opts |> Keyword.get(:path, "/") |> String.trim_trailing("/")

    route_info = get_route_info(path)

    default_route_type = Keyword.get(opts, :route_type)

    type =
      cond do
        not is_nil(default_route_type) -> default_route_type
        is_nil(route_info) -> :static_asset
        Map.get(route_info, :type) == :marketing -> :marketing
        true -> :app
      end

    if type == :marketing and not Tuist.Environment.tuist_hosted?() do
      # When it's a marketing URL available presented somewhere in an
      # on-premis instance, it should point to the production routes.
      URI.to_string(%{URI.parse(get_url(:production)) | path: path})
    else
      URI.to_string(%{URI.parse(app_base_url(secrets)) | path: path})
    end
  end

  defp app_base_url(secrets) do
    if dev?() do
      System.get_env("TUIST_SERVER_URL") || get([:app, :url], secrets) || "http://localhost:8080"
    else
      get([:app, :url], secrets) || "http://localhost:8080"
    end
  end

  defp get_route_info(path) do
    case Phoenix.Router.route_info(TuistWeb.Router, "GET", path, "") do
      :error -> nil
      route_info -> route_info
    end
  end

  def get_url(key) do
    :tuist |> Application.fetch_env!(:urls) |> Keyword.fetch!(key)
  end

  def email_icon_url do
    uri = URI.parse(app_url())
    URI.to_string(%{uri | path: "/images/tuist_email.png"})
  end

  def sentry_dsn(secrets \\ secrets()) do
    get([:sentry, :dsn], secrets)
  end

  def secret_key_base(secrets \\ secrets()) do
    get([:secret_key, :base], secrets)
  end

  def secret_key_password(secrets \\ secrets()) do
    get([:secret_key, :password], secrets, default_value: secret_key_base(secrets))
  end

  def secret_key_tokens(secrets \\ secrets()) do
    get([:secret_key, :tokens], secrets, default_value: secret_key_base(secrets))
  end

  def secret_key_encryption(secrets \\ secrets()) do
    get([:secret_key, :encryption], secrets, default_value: secret_key_base(secrets))
  end

  def oauth_client_id(secrets \\ secrets()) do
    get([:oauth, :client_id], secrets)
  end

  def oauth_client_secret(secrets \\ secrets()) do
    get([:oauth, :client_secret], secrets)
  end

  def oauth_client_name(secrets \\ secrets()) do
    get([:oauth, :client_name], secrets)
  end

  def oauth_jwt_public_key(secrets \\ secrets()) do
    get([:oauth, :jwt_public_key], secrets)
  end

  def oauth_private_key(secrets \\ secrets()) do
    get([:oauth, :private_key], secrets)
  end

  def oauth_configured?(secrets \\ secrets()) do
    oauth_client_id(secrets) != nil and
      oauth_client_secret(secrets) != nil and
      oauth_client_name(secrets) != nil and
      oauth_jwt_public_key(secrets) != nil and
      oauth_private_key(secrets) != nil
  end

  # Kura-side env vars stay unprefixed so the implementation in Kura
  # remains Tuist-agnostic. The encrypted `kura.*` secrets stay as a
  # compatibility fallback for existing deployments and dev secrets.
  def kura_control_plane_client_id(secrets \\ secrets()) do
    System.get_env("KURA_CONTROL_PLANE_CLIENT_ID") ||
      get([:kura, :control_plane_client_id], secrets) ||
      get([:kura, :introspection_client_id], secrets)
  end

  def kura_control_plane_client_secret(secrets \\ secrets()) do
    System.get_env("KURA_CONTROL_PLANE_CLIENT_SECRET") ||
      get([:kura, :control_plane_client_secret], secrets) ||
      get([:kura, :introspection_client_secret], secrets)
  end

  def kura_control_plane_configured?(secrets \\ secrets()) do
    kura_control_plane_client_id(secrets) != nil and
      kura_control_plane_client_secret(secrets) != nil
  end

  def kura_introspection_client_id(secrets \\ secrets()), do: kura_control_plane_client_id(secrets)

  def kura_introspection_client_secret(secrets \\ secrets()), do: kura_control_plane_client_secret(secrets)

  def kura_introspection_configured?(secrets \\ secrets()), do: kura_control_plane_configured?(secrets)

  @doc """
  Returns the Namespace SSH private key used to establish secure SSH connections between the server and the Namespace runner.
  """
  def namespace_ssh_private_key(secrets \\ secrets()) do
    get([:namespace, :ssh_private_key], secrets)
  end

  @doc """
  Returns the Namespace SSH public key used to establish secure SSH connections between the server and the Namespace runner.
  """
  def namespace_ssh_public_key(secrets \\ secrets()) do
    get([:namespace, :ssh_public_key], secrets)
  end

  @doc """
  Returns the Namespace partner ID that identifies this Tuist instance
  as an authorized partner in the Namespace ecosystem. This ID is used
  when issuing Namespace tenant tokens.
  """
  def namespace_partner_id(secrets \\ secrets()) do
    get([:namespace, :partner_id], secrets)
  end

  @doc """
  Returns the Namespace JWT private key used for signing authentication tokens
  that are exchanged between Tuist and Namespace services when issuing Namespace tenant tokens.
  """
  def namespace_jwt_private_key(secrets \\ secrets()) do
    case get([:namespace, :jwt_private_key], secrets) do
      nil -> nil
      base64_key -> Base.decode64!(base64_key)
    end
  end

  def namespace_enabled?(secrets \\ secrets()) do
    namespace_partner_id(secrets) != nil and namespace_jwt_private_key(secrets) != nil
  end

  def typesense_host do
    get([:typesense, :host], secrets(), default_value: "https://search.tuist.dev")
  end

  @doc """
  Kubernetes namespace customer runner Pods live in. The
  webhook handler writes RunnerAssignment CRs into this
  namespace; the runners-controller reconciles them into Pods.
  Defaults to `tuist-runners` (matches the chart's
  `runnersFleet.namespace`).
  """
  def runners_namespace do
    System.get_env("TUIST_RUNNERS_NAMESPACE", "tuist-runners")
  end

  @doc """
  Prefix the dispatch path prepends to a shape key when addressing a
  Linux shape pool's `RunnerPool` CR (`<prefix>-<vcpus>vcpu-<gb>gb`).

  Helm injects this from the same `tuist.componentName` helper that
  names the CRs (`runner-pool.yaml`), so the server always resolves to
  a pool a Pod actually polls regardless of the release name. The
  default matches a chart whose fullname collapses to `tuist`; local
  dev and tests (no real cluster) don't dispatch against it.
  """
  def runners_linux_pool_name_prefix do
    System.get_env("TUIST_RUNNERS_LINUX_POOL_NAME_PREFIX", "tuist-runner-pool-linux")
  end

  @doc """
  Same role as `runners_linux_pool_name_prefix/0`, for the macOS fleet.
  Helm renders the prefix into the `RunnerPool` CR names and injects it
  here so the server's enqueue target stays identical to the rendered CR
  name regardless of helm release. Default mirrors the Linux side, with
  `-macos` substituted for `-linux`.
  """
  def runners_macos_pool_name_prefix do
    System.get_env("TUIST_RUNNERS_MACOS_POOL_NAME_PREFIX", "tuist-runner-pool-macos")
  end

  @doc """
  Runner platforms whose fleets can resolve and reach the cluster's
  internal Service network (`*.svc.cluster.local`) — the per-environment
  input behind `Tuist.Runners.Catalog.fleet_on_cluster_network?/1`.

  Comma-separated platform names in
  `TUIST_RUNNERS_CLUSTER_NETWORK_PLATFORMS`. The default is `linux`
  (kata Pods always ride the CNI). An environment adds `macos` only once
  its Mac mini fleet has the tailnet route into the cluster
  (subnet-router Connector advertising the Service CIDR, host
  `--accept-routes`, and the VM egress firewall carve-out — see
  `infra/helm/tailscale-operator` and `infra/macos-host-bootstrap`).
  Unknown tokens are ignored so a typo degrades to "no cache routing for
  that platform" rather than crashing dispatch.
  """
  def runners_cluster_network_platforms do
    "TUIST_RUNNERS_CLUSTER_NETWORK_PLATFORMS"
    |> System.get_env("linux")
    |> String.split(",")
    |> Enum.flat_map(fn token ->
      case String.trim(token) do
        "linux" -> [:linux]
        "macos" -> [:macos]
        _ -> []
      end
    end)
  end

  @doc """
  Namespace where the CNPG `Cluster` and its `Backup` / `ScheduledBackup`
  CRs live — the chart sets it to the release namespace when CNPG is
  enabled. `nil` when unset (dev, or CNPG not provisioned), which makes
  the `/ops/db` Backups tab skip the Kubernetes API lookup.
  """
  def cnpg_namespace do
    System.get_env("TUIST_CNPG_NAMESPACE")
  end

  @doc """
  Namespace where the runners-controller's ServiceAccount lives —
  used to gate `POST /api/internal/runners/pods/stopped` so only
  the controller can close billing sessions. Defaults to `tuist`
  (the typical chart release namespace); helm sets it explicitly
  to `.Release.Namespace`.
  """
  def runners_controller_namespace do
    System.get_env("TUIST_RUNNERS_CONTROLLER_NAMESPACE", "tuist")
  end

  @doc """
  Name of the runners-controller's ServiceAccount. Pairs with
  `runners_controller_namespace/0` to identify the only principal
  authorised to call the pod-lifecycle endpoints. Defaults to
  `tuist-runners-controller` (chart-rendered name); helm overrides
  via env when the release name differs.
  """
  def runners_controller_sa_name do
    System.get_env("TUIST_RUNNERS_CONTROLLER_SA_NAME", "tuist-runners-controller")
  end

  @doc """
  Cross-cluster trust policy for Atlas workload tokens.
  """
  def atlas_workload_identity_policy do
    %{
      audience: atlas_token_audience(),
      issuer: atlas_token_issuer(),
      jwks: atlas_token_jwks(),
      max_token_ttl_seconds: atlas_token_max_ttl_seconds(),
      namespace: atlas_namespace(),
      service_account_name: atlas_service_account_name()
    }
  end

  @doc """
  Namespace where Atlas' ServiceAccount lives. Atlas calls internal Tuist
  endpoints with a projected ServiceAccount token, so the server verifies both
  the token subject and this expected principal.
  """
  def atlas_namespace do
    System.get_env("TUIST_ATLAS_NAMESPACE", "atlas-production")
  end

  @doc """
  Name of the Atlas ServiceAccount allowed to call Atlas internal read models.
  """
  def atlas_service_account_name do
    System.get_env("TUIST_ATLAS_SERVICE_ACCOUNT_NAME", "atlas")
  end

  @doc """
  Issuer expected in Atlas' projected ServiceAccount tokens.
  """
  def atlas_token_issuer do
    System.get_env("TUIST_ATLAS_TOKEN_ISSUER") ||
      get([:atlas, :token_issuer], secrets(), default_value: "https://kubernetes.default.svc.cluster.local")
  end

  @doc """
  Audience Atlas must request on its projected ServiceAccount token.
  """
  def atlas_token_audience do
    System.get_env("TUIST_ATLAS_TOKEN_AUDIENCE") ||
      get([:atlas, :token_audience], secrets(), default_value: "tuist-server")
  end

  @doc """
  Pinned Atlas Kubernetes JWKS used to verify projected ServiceAccount tokens.
  """
  def atlas_token_jwks do
    System.get_env("TUIST_ATLAS_TOKEN_JWKS") || get([:atlas, :token_jwks], secrets())
  end

  @doc """
  Maximum accepted lifetime for Atlas projected ServiceAccount tokens.
  """
  def atlas_token_max_ttl_seconds do
    case get([:atlas, :token_max_ttl_seconds], secrets(), default_value: "3600") do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc """
  Returns the bucket size for Atlas internal API rate limiting.
  """
  def atlas_rate_limit_bucket_size(secrets \\ secrets()) do
    case get([:atlas, :rate_limit_bucket_size], secrets, default_value: "600") do
      bucket_size when is_integer(bucket_size) -> bucket_size
      bucket_size when is_binary(bucket_size) -> String.to_integer(bucket_size)
    end
  end

  def typesense_search_api_key do
    get([:typesense, :search_api_key], secrets(), default_value: "RgIpKytJBtSQf9CoYKxIfVxh8ma5kzs6")
  end

  def get(keys, secrets \\ secrets(), opts \\ []) do
    env_variable =
      "TUIST_#{keys |> Enum.map(&to_string/1) |> Enum.map_join("_", &String.upcase/1)}"

    default_value = Keyword.get(opts, :default_value)

    # Convert atom keys to string keys for secrets lookup
    string_keys = Enum.map(keys, &to_string/1)

    value =
      if System.get_env(env_variable) do
        System.get_env(env_variable)
      else
        safe_get_in(secrets, string_keys)
      end

    if is_nil(value) do
      default_value
    else
      value
    end
  end

  defp safe_get_in(data, []), do: data

  defp safe_get_in(data, [key | rest]) when is_map(data) do
    case Map.get(data, key) do
      nil -> nil
      value -> safe_get_in(value, rest)
    end
  end

  defp safe_get_in(_data, _keys), do: nil

  defp split_endpoints(endpoints) do
    endpoints
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp endpoint_env_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp endpoint_env_value(_), do: nil

  def secrets do
    Application.get_env(:tuist, :secrets) || %{}
  end

  def put_application_secrets(secrets) do
    Application.put_env(:tuist, :secrets, secrets)
    :ok
  end

  @doc ~s"""
  It decrypts the secrets and returns them.
  """
  def decrypt_secrets do
    if @compile_env == :test do
      {:ok, secrets_map} =
        "priv/secrets/test.yml"
        |> File.read!()
        |> YamlElixir.read_from_string()

      to_string_map(secrets_map)
    else
      master_key_path = Path.join("priv/secrets", "#{Atom.to_string(env())}.key")
      master_key_env_variable = "MASTER_KEY"

      secrets_path =
        case System.get_env("SECRETS_DIRECTORY") do
          env_directory when is_binary(env_directory) ->
            Path.join(env_directory, "#{Atom.to_string(env())}.yml.enc")

          _ ->
            Path.join("priv/secrets", "#{Atom.to_string(env())}.yml.enc")
        end

      if System.get_env(master_key_env_variable) || File.exists?(master_key_path) do
        key = System.get_env(master_key_env_variable) || File.read!(master_key_path)

        key |> EncryptedSecrets.read!(secrets_path) |> to_string_map()
      else
        %{}
      end
    end
  end

  defp to_string_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_string_map(v)} end)
  end

  defp to_string_map(value) do
    value
  end
end
