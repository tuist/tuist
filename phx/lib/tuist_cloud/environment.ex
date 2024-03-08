defmodule TuistCloud.Environment do
  @moduledoc false
  @env Mix.env()

  def env, do: @env

  def truthy?(value) do
    ["1", "true", "TRUE", "yes", "YES"] |> Enum.member?(value)
  end

  def on_premise?() do
    truthy?(System.get_env("TUIST_CLOUD_SELF_HOSTED", "0"))
  end

  @spec s3_access_key_id() :: String.t() | nil
  def s3_access_key_id do
    get([:aws, :access_key_id]) || get([:s3, :access_key_id])
  end

  @spec s3_secret_access_key() :: String.t() | nil
  def s3_secret_access_key do
    get([:aws, :secret_access_key]) || get([:s3, :secret_access_key])
  end

  @spec s3_region() :: String.t() | nil
  def s3_region do
    get([:aws, :region]) || get([:s3, :region])
  end

  @spec s3_bucket_name() :: String.t() | nil
  def s3_bucket_name do
    get([:aws, :bucket_name]) || get([:s3, :bucket_name])
  end

  def s3_configured? do
    s3_access_key_id() != nil && s3_secret_access_key() != nil && s3_region() != nil &&
      (!on_premise?() || s3_bucket_name() != nil)
  end

  @spec get([String.t()]) :: String.t() | nil
  def get(keys) do
    env_variable =
      "TUIST_#{keys |> Enum.map(&Atom.to_string/1) |> Enum.map_join(&String.upcase/1, "_")}"

    if System.get_env(env_variable) do
      System.get_env(env_variable)
    else
      get_in(secrets(), keys)
    end
  end

  def secrets do
    Application.get_env(:tuist_cloud, :secrets)[rails_env()] || %{}
  end

  def rails_env do
    System.get_env("RAILS_ENV", "development") |> String.to_atom()
  end
end
