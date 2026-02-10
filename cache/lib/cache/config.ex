defmodule Cache.Config do
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
  Returns the bucket for cache artifacts (CAS and module).
  """
  def cache_bucket, do: Application.get_env(:cache, :s3)[:bucket]

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
