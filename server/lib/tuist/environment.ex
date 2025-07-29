defmodule Tuist.Environment do
  @moduledoc false
  @env Mix.env()

  def env do
    @env
  end

  @doc ~S"""
  Returns an list with all the supported environments.
  """
  def all_envs, do: [:dev, :test, :can, :stag, :prod]

  def test? do
    @env == :test
  end

  def dev? do
    @env == :dev
  end

  def stag? do
    @env == :stag
  end

  def can? do
    @env == :can
  end

  def prod? do
    @env == :prod
  end

  defmacro run_if_error_tracking_enabled(block) do
    enabled = error_tracking_enabled?()

    if enabled do
      block
    else
      quote do
        :ok
      end
    end
  end

  def truthy?(value) do
    Enum.member?(["1", "true", "TRUE", "yes", "YES"], value)
  end

  def worker? do
    "TUIST_WORKER" |> System.get_env("1") |> truthy?()
  end

  def web? do
    "TUIST_WEB" |> System.get_env("1") |> truthy?()
  end

  def database_url(secrets \\ secrets()) do
    System.get_env("DATABASE_URL") || get([:database_url], secrets)
  end

  def ipv4_database_url(secrets \\ secrets()) do
    System.get_env("TUIST_IPV4_DATABASE_URL") || get([:ipv4_database_url], secrets)
  end

  def tuist_hosted? do
    truthy?(System.get_env("TUIST_CLOUD_HOSTED", "0")) or
      truthy?(System.get_env("TUIST_HOSTED", "0"))
  end

  def log_level do
    "TUIST_LOG_LEVEL" |> System.get_env("info") |> String.to_atom()
  end

  def use_ssl_for_database? do
    truthy?(System.get_env("TUIST_USE_SSL_FOR_DATABASE", "1"))
  end

  def get_license_key(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_KEY") ||
      get([:license], secrets)
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

  def analytics_enabled? do
    tuist_hosted?() and @env == :prod
  end

  def error_tracking_enabled? do
    truthy?(System.get_env("TUIST_FORCE_ERROR_TRACKING")) ||
      (tuist_hosted?() and Enum.member?([:prod, :stag, :can], env()))
  end

  def version do
    case Version.parse(get([:version]) || "0.1.0") do
      :error -> nil
      {:ok, version} -> version
    end
  end

  def ops_user_handles(secrets \\ secrets()) do
    case get([:ops_user_handles], secrets) do
      user_handles when is_binary(user_handles) ->
        user_handles |> String.split(",") |> Enum.map(&String.trim(&1))

      _ ->
        []
    end
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

  def s3_request_timeout(secrets \\ secrets()) do
    case get([:s3, :request_timeout], secrets) do
      request_timeout when is_binary(request_timeout) -> String.to_integer(request_timeout)
      _ -> 30
    end
  end

  def s3_pool_timeout(secrets \\ secrets()) do
    case get([:s3, :pool_timeout], secrets) do
      pool_timeout when is_binary(pool_timeout) -> String.to_integer(pool_timeout)
      _ -> 5
    end
  end

  def s3_access_key_id(secrets \\ secrets()) do
    System.get_env("AWS_ACCESS_KEY_ID") || get([:aws, :access_key_id], secrets) ||
      get([:s3, :access_key_id], secrets)
  end

  def s3_secret_access_key(secrets \\ secrets()) do
    System.get_env("AWS_SECRET_ACCESS_KEY") || get([:aws, :secret_access_key], secrets) ||
      get([:s3, :secret_access_key], secrets)
  end

  def s3_region(secrets \\ secrets()) do
    System.get_env("AWS_REGION") || get([:aws, :region], secrets) || get([:s3, :region], secrets) ||
      "auto"
  end

  def s3_bucket_name(secrets \\ secrets()) do
    get([:aws, :bucket_name], secrets) || get([:s3, :bucket_name], secrets)
  end

  def s3_endpoint(secrets \\ secrets()) do
    get([:aws, :endpoint], secrets) || get([:s3, :endpoint], secrets)
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
      _ -> 1
    end
  end

  def s3_protocols(secrets \\ secrets()) do
    case get([:s3, :protocol], secrets) do
      protocol when is_binary(protocol) -> [String.to_atom(protocol)]
      _ -> [:http2, :http1]
    end
  end

  def s3_virtual_host(secrets \\ secrets()) do
    [:s3, :virtual_host] |> get(secrets) |> truthy?()
  end

  def slack_tuist_token(secrets \\ secrets()) do
    get([:slack, :tuist, :token], secrets)
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
        prices_base64_json |> Base.decode64!() |> Jason.decode!(keys: :atoms)

      true ->
        nil
    end
  end

  def mautic_username(secrets \\ secrets()) do
    get([:mautic, :username], secrets)
  end

  def mautic_password(secrets \\ secrets()) do
    get([:mautic, :password], secrets)
  end

  def github_token_update_packages(secrets \\ secrets()) do
    get([:github, :token, :update_packages], secrets)
  end

  def github_token_update_package_releases(secrets \\ secrets()) do
    get([:github, :token, :update_package_releases], secrets)
  end

  def github_app_client_id(secrets \\ secrets()) do
    get([:github, :app_client_id], secrets) || get([:github, :oauth_id], secrets)
  end

  def github_app_client_secret(secrets \\ secrets()) do
    get([:github, :app_client_secret], secrets) || get([:github, :oauth_secret], secrets)
  end

  def github_app_private_key(secrets \\ secrets()) do
    get([:github, :app_private_key], secrets)
  end

  def github_oauth_configured?(secrets \\ secrets()) do
    github_app_client_id(secrets) != nil and github_app_client_secret(secrets) != nil
  end

  def github_app_configured?(secrets \\ secrets()) do
    github_oauth_configured?(secrets) and github_app_private_key(secrets) != nil
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

  def smtp_domain(secrets \\ secrets()) do
    get([:smtp_settings, :domain], secrets)
  end

  def smtp_user_name(secrets \\ secrets()) do
    get([:smtp_settings, :user_name], secrets)
  end

  def mail_configured?(secrets \\ secrets()) do
    mailgun_api_key(secrets) != nil and smtp_domain(secrets) != nil and
      smtp_user_name(secrets) != nil
  end

  def clickhouse_configured?(secrets \\ secrets()) do
    clickhouse_url(secrets) != nil
  end

  def clickhouse_url(secrets \\ secrets()) do
    get([:clickhouse, :url], secrets)
  end

  def clickhouse_pool_size(secrets \\ secrets()) do
    get([:clickhouse, :pool_size], secrets) || database_pool_size(secrets)
  end

  def clickhouse_queue_interval(secrets \\ secrets()) do
    get([:clickhouse, :queue_interval], secrets) || database_queue_interval(secrets)
  end

  def clickhouse_queue_target(secrets \\ secrets()) do
    get([:clickhouse, :queue_target], secrets) || database_queue_target(secrets)
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
      url = get([:app, :url], secrets) || "http://localhost:8080"
      URI.to_string(%{URI.parse(url) | path: path})
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

  def app_signal_push_api_key(secrets \\ secrets()) do
    get([:app_signal, :push_api_key], secrets)
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
        get_in(secrets, string_keys)
      end

    if is_nil(value) do
      default_value
    else
      value
    end
  end

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
    if @env == :test do
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
