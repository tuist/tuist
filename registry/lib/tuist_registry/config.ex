defmodule TuistRegistry.Config do
  @moduledoc false

  def registry_bucket, do: Application.get_env(:tuist_registry, :s3)[:registry_bucket]

  def registry_enabled?, do: registry_bucket() != nil

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

  def s3_config do
    Application.fetch_env(:ex_aws, :s3)
  end
end
