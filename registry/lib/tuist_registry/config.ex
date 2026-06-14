defmodule TuistRegistry.Config do
  @moduledoc false

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

  def bool_env(name, default) when is_binary(name) do
    name
    |> System.get_env()
    |> parse_bool(default)
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

  def analytics_enabled? do
    api_key() != nil
  end

  def analytics_failure_threshold do
    Application.get_env(:tuist_registry, :analytics_failure_threshold, 3)
  end

  def analytics_cooldown_ms do
    Application.get_env(:tuist_registry, :analytics_cooldown_ms, 60_000)
  end

  def analytics_receive_timeout_ms do
    Application.get_env(:tuist_registry, :analytics_receive_timeout_ms, 2_000)
  end

  def analytics_pool_timeout_ms do
    Application.get_env(:tuist_registry, :analytics_pool_timeout_ms, 1_000)
  end

  def api_key do
    case Application.get_env(:tuist_registry, :api_key) do
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
    Application.get_env(:tuist_registry, :oban_web_basic_auth, [])
  end

  def registry_bucket, do: Application.get_env(:tuist_registry, :s3)[:registry_bucket]

  def registry_github_token do
    case Application.get_env(:tuist_registry, :registry_github_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  def registry_enabled?, do: registry_bucket() != nil and registry_github_token() != nil

  def registry_sync_enabled? do
    Application.get_env(:tuist_registry, :registry_sync_enabled, true)
  end

  def s3_protocols do
    case Application.get_env(:tuist_registry, :s3)[:protocols] do
      protocols when is_list(protocols) and protocols != [] -> protocols
      _ -> [:http2, :http1]
    end
  end

  def s3_ca_cert_pem(s3_config \\ Application.get_env(:tuist_registry, :s3, [])) do
    case Keyword.get(s3_config, :ca_cert_pem) do
      pem when is_binary(pem) and pem != "" -> pem
      _ -> nil
    end
  end

  def server_ca_cert_pem(value \\ Application.get_env(:tuist_registry, :server_ca_cert_pem)) do
    case value do
      pem when is_binary(pem) and pem != "" -> pem
      _ -> nil
    end
  end

  def s3_virtual_host do
    !!Application.get_env(:ex_aws, :s3)[:virtual_host]
  end

  def server_url, do: Application.get_env(:tuist_registry, :server_url)

  @default_orphan_scan_max_dirs 50
  def orphan_scan_max_dirs,
    do: Application.get_env(:tuist_registry, :orphan_scan_max_dirs, @default_orphan_scan_max_dirs)

  def repo_busy_timeout_ms(repo \\ TuistRegistry.Repo) do
    Application.get_env(:tuist_registry, repo)[:busy_timeout] || 30_000
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

  defp parse_bool(nil, default), do: default
  defp parse_bool("1", _default), do: true
  defp parse_bool("true", _default), do: true
  defp parse_bool("TRUE", _default), do: true
  defp parse_bool("yes", _default), do: true
  defp parse_bool("YES", _default), do: true
  defp parse_bool("0", _default), do: false
  defp parse_bool("false", _default), do: false
  defp parse_bool("FALSE", _default), do: false
  defp parse_bool("no", _default), do: false
  defp parse_bool("NO", _default), do: false
  defp parse_bool(_value, default), do: default
end
