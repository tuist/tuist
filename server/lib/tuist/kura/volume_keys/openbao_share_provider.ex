defmodule Tuist.Kura.VolumeKeys.OpenBaoShareProvider do
  @moduledoc """
  OpenBao Transit wrapping with a dedicated Kubernetes workload identity.
  The endpoint, mount and key name form the pinned share identifier. Both
  derivation context and authenticated data bind tenant, version and position.
  Workload tokens and plaintext are never cached or sent to shared telemetry.
  """
  @behaviour Tuist.Kura.VolumeKeys.ShareProvider

  alias Tuist.Environment
  alias Tuist.Kura.VolumeKeys.KeyServiceHTTP

  @provider "openbao"

  @impl true
  def provider, do: @provider

  @impl true
  def wrap(<<_::256>> = plaintext, aad) do
    with {:ok, config} <- Environment.kura_volume_openbao(),
         {:ok, %{"data" => %{"ciphertext" => ciphertext}}} <-
           request("encrypt", config.key_name, %{"plaintext" => Base.encode64(plaintext)}, aad, config),
         true <- valid_ciphertext?(ciphertext) do
      {:ok, %{"provider" => @provider, "key_id" => config.key_id, "ciphertext" => ciphertext}}
    else
      _ -> {:error, :key_service_unavailable}
    end
  end

  @impl true
  def unwrap(%{"provider" => @provider, "key_id" => key_id, "ciphertext" => ciphertext}, aad)
      when is_binary(key_id) and is_binary(ciphertext) do
    with {:ok, config} <- Environment.kura_volume_openbao(),
         {:ok, key_name} <- Map.fetch(config.decrypt_keys, key_id),
         true <- valid_ciphertext?(ciphertext),
         {:ok, %{"data" => %{"plaintext" => encoded}}} when is_binary(encoded) <-
           request("decrypt", key_name, %{"ciphertext" => ciphertext}, aad, config),
         {:ok, <<_::256>> = plaintext} <- Base.decode64(encoded) do
      {:ok, plaintext}
    else
      _ -> {:error, :key_service_unavailable}
    end
  end

  def unwrap(_, _), do: {:error, :malformed_share}

  defp request(operation, key_name, data, aad, config) do
    with {:ok, token} <- login(config) do
      context = Base.encode64(aad)
      body = Map.merge(data, %{"context" => context, "associated_data" => context})
      post(config, "#{config.transit_mount}/#{operation}/#{key_name}", [{"X-Vault-Token", token}], body)
    end
  rescue
    _ -> {:error, :key_service_unavailable}
  end

  defp login(config) do
    with {:ok, jwt} <- File.read(config.token_file),
         jwt when jwt != "" <- String.trim(jwt),
         {:ok, %{"auth" => %{"client_token" => token}}} when is_binary(token) and token != "" <-
           post(config, "auth/#{config.auth_mount}/login", [], %{"role" => config.role, "jwt" => jwt}) do
      {:ok, token}
    else
      _ -> {:error, :key_service_unavailable}
    end
  end

  defp post(config, path, headers, data) do
    with {:ok, response} <-
           KeyServiceHTTP.post(
             "#{config.address}/v1/#{path}",
             headers,
             "application/json",
             JSON.encode!(data),
             config.ca_cert_file
           ) do
      JSON.decode(response)
    end
  end

  defp valid_ciphertext?(ciphertext) when is_binary(ciphertext) do
    case String.split(ciphertext, ":", parts: 3) do
      ["vault", "v" <> version, encoded] ->
        with {version, ""} when version > 0 <- Integer.parse(version),
             {:ok, bytes} when byte_size(bytes) > 0 <- Base.decode64(encoded) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp valid_ciphertext?(_), do: false
end
