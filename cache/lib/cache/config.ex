defmodule Cache.Config do
  @moduledoc false

  alias Cache.DistributedKV.Repo

  def float_env(name, default) when is_binary(name) do
    name
    |> System.get_env()
    |> parse_float(default)
  end

  def int_env(name, default) when is_binary(name) do
    name
    |> System.get_env()
    |> parse_int(default)
  end

  def list_env(name) when is_binary(name) do
    case System.get_env(name) do
      nil ->
        nil

      value ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  @doc """
  Returns true if analytics/usage reporting is enabled (API key is configured).
  """
  def analytics_enabled? do
    api_key() != nil
  end

  @doc """
  Returns the API key for server communication, or nil if not configured.
  """
  def api_key do
    case Application.get_env(:cache, :api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  @doc """
  Returns true if Guardian JWT verification is configured.
  """
  def guardian_configured? do
    guardian_secret_key() != nil
  end

  @doc """
  Returns the Guardian secret key, or nil if not configured.
  """
  def guardian_secret_key do
    case :cache |> Application.get_env(Cache.Guardian, []) |> Keyword.get(:secret_key) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  def oban_dashboard_enabled? do
    case oban_web_credentials() do
      [username: u, password: p] when is_binary(u) and u != "" and is_binary(p) and p != "" ->
        true

      _ ->
        false
    end
  end

  def oban_web_credentials do
    Application.get_env(:cache, :oban_web_basic_auth, [])
  end

  @doc """
  Returns the bucket for cache artifacts (module and Gradle).
  """
  def cache_bucket, do: Application.get_env(:cache, :s3)[:bucket]

  @doc """
  Returns the dedicated bucket for Xcode cache artifacts, or nil if not configured.

  When nil, Xcode cache artifacts use the shared cache bucket (`cache_bucket/0`).
  """
  def xcode_cache_bucket, do: Application.get_env(:cache, :s3)[:xcode_cache_bucket]

  @doc """
  Returns the bucket for registry artifacts, or nil if not configured.
  """
  def registry_bucket, do: Application.get_env(:cache, :s3)[:registry_bucket]

  @doc """
  Returns the GitHub token for registry sync, or nil if not configured.
  """
  def registry_github_token do
    case Application.get_env(:cache, :registry_github_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  Returns true if registry is fully configured (bucket and GitHub token).
  """
  def registry_enabled?, do: registry_bucket() != nil and registry_github_token() != nil

  def s3_protocols do
    case Application.get_env(:cache, :s3)[:protocols] do
      protocols when is_list(protocols) and protocols != [] -> protocols
      _ -> [:http2, :http1]
    end
  end

  def s3_virtual_host do
    !!Application.get_env(:ex_aws, :s3)[:virtual_host]
  end

  def server_url, do: Application.get_env(:cache, :server_url)

  @default_orphan_scan_max_dirs 50
  def orphan_scan_max_dirs, do: Application.get_env(:cache, :orphan_scan_max_dirs, @default_orphan_scan_max_dirs)

  def repo_busy_timeout_ms(repo \\ Cache.Repo) do
    Application.get_env(:cache, repo)[:busy_timeout] || 30_000
  end

  def key_value_eviction_max_duration_ms do
    Application.get_env(:cache, :key_value_eviction_max_duration_ms, 300_000)
  end

  def key_value_mode do
    Application.get_env(:cache, :key_value_mode, :local)
  end

  def distributed_kv_enabled? do
    key_value_mode() == :distributed
  end

  def distributed_kv_database_url do
    Application.get_env(:cache, Repo)[:url]
  end

  def distributed_kv_ssl_opts(database_url) when is_binary(database_url) do
    hostname = distributed_kv_database_hostname(database_url)

    [
      verify: :verify_peer,
      cacertfile: CAStore.file_path(),
      server_name_indication: String.to_charlist(hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  def distributed_kv_pool_size do
    Application.get_env(:cache, Repo)[:pool_size] || 5
  end

  def distributed_kv_database_timeout_ms do
    Application.fetch_env!(:cache, :distributed_kv_database_timeout_ms)
  end

  def distributed_kv_sync_interval_ms do
    Application.fetch_env!(:cache, :distributed_kv_sync_interval_ms)
  end

  def distributed_kv_poll_lag_ms do
    Application.fetch_env!(:cache, :distributed_kv_poll_lag_ms)
  end

  def distributed_kv_ship_interval_ms do
    Application.fetch_env!(:cache, :distributed_kv_ship_interval_ms)
  end

  def distributed_kv_ship_batch_size do
    Application.fetch_env!(:cache, :distributed_kv_ship_batch_size)
  end

  def distributed_kv_access_throttle_ms do
    Application.fetch_env!(:cache, :distributed_kv_access_throttle_ms)
  end

  def distributed_kv_tombstone_retention_days do
    Application.fetch_env!(:cache, :distributed_kv_tombstone_retention_days)
  end

  def distributed_kv_cleanup_lease_ms do
    Application.fetch_env!(:cache, :distributed_kv_cleanup_lease_ms)
  end

  def distributed_kv_cleanup_discovery_interval_ms do
    Application.fetch_env!(:cache, :distributed_kv_cleanup_discovery_interval_ms)
  end

  def distributed_kv_node_name do
    Application.get_env(:cache, :distributed_kv_node_name) ||
      System.get_env("DISTRIBUTED_KV_NODE_NAME") ||
      System.get_env("HOSTNAME") ||
      cache_endpoint()
  end

  def key_value_read_busy_timeout_ms do
    Application.get_env(:cache, :key_value_read_busy_timeout_ms, 2_000)
  end

  def key_value_maintenance_busy_timeout_ms do
    Application.get_env(:cache, :key_value_maintenance_busy_timeout_ms, 50)
  end

  def s3_config do
    Application.fetch_env(:ex_aws, :s3)
  end

  def cache_endpoint do
    node()
    |> to_string()
    |> String.split("@")
    |> List.last()
  end

  defp distributed_kv_database_hostname(database_url) do
    case URI.parse(database_url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> raise ArgumentError, "DISTRIBUTED_KV_DATABASE_URL must include a hostname"
    end
  end

  defp parse_float(nil, default), do: default

  defp parse_float(value, default) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) do
    case Integer.parse(value) do
      {integer, _} -> integer
      :error -> default
    end
  end
end
