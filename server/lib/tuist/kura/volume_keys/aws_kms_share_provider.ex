defmodule Tuist.Kura.VolumeKeys.AWSKMSShareProvider do
  @moduledoc """
  Tuist-managed, non-exportable AWS KMS wrapping key. Authentication uses a
  dedicated projected OIDC token and role; S3 credentials are never inherited.
  KMS encryption context binds the share to the same AAD as the legacy provider.
  Full key ARNs are pinned and allowlisted, including old keys during migration.
  """
  @behaviour Tuist.Kura.VolumeKeys.ShareProvider

  alias ExAws.STS.Parsers
  alias Tuist.Environment
  alias Tuist.Kura.VolumeKeys.KMSHTTP

  @provider "aws_kms"

  @impl true
  def provider, do: @provider

  @impl true
  def wrap(<<_::256>> = plaintext, aad) do
    with {:ok, config} <- Environment.kura_volume_kms(),
         {:ok, %{"KeyId" => key_id, "CiphertextBlob" => ciphertext}} <-
           request("Encrypt", config.key_id, %{"Plaintext" => Base.encode64(plaintext)}, aad, config),
         true <- key_id == config.key_id,
         {:ok, bytes} when byte_size(bytes) > 0 <- Base.decode64(ciphertext) do
      {:ok, %{"provider" => @provider, "key_id" => key_id, "ciphertext" => ciphertext}}
    else
      _ -> {:error, :kms_unavailable}
    end
  end

  @impl true
  def unwrap(%{"provider" => @provider, "key_id" => key_id, "ciphertext" => ciphertext}, aad)
      when is_binary(key_id) and is_binary(ciphertext) do
    with {:ok, config} <- Environment.kura_volume_kms(),
         true <- key_id in config.decrypt_key_ids,
         {:ok, %{"KeyId" => ^key_id, "Plaintext" => encoded}} <-
           request("Decrypt", key_id, %{"CiphertextBlob" => ciphertext}, aad, config),
         {:ok, <<_::256>> = plaintext} <- Base.decode64(encoded) do
      {:ok, plaintext}
    else
      _ -> {:error, :kms_unavailable}
    end
  end

  def unwrap(_, _), do: {:error, :malformed_share}

  defp request(operation, key_id, data, aad, config) do
    with {:ok, credentials} <- credentials(config) do
      url = "https://kms.#{config.region}.amazonaws.com/"

      body =
        JSON.encode!(
          Map.merge(data, %{"KeyId" => key_id, "EncryptionContext" => %{"purpose" => "kura-volume-share", "aad" => aad}})
        )

      headers = [{"x-amz-target", "TrentService.#{operation}"}, {"content-type", "application/x-amz-json-1.1"}]

      with {:ok, headers} <-
             ExAws.Auth.headers(:post, url, :kms, Map.put(credentials, :region, config.region), headers, body),
           {:ok, response} <- KMSHTTP.post(url, headers, "application/x-amz-json-1.1", body) do
        JSON.decode(response)
      end
    end
  rescue
    _ -> {:error, :kms_unavailable}
  end

  defp credentials(config) do
    with {:ok, token} <- File.read(config.token_file),
         body =
           URI.encode_query(%{
             "Action" => "AssumeRoleWithWebIdentity",
             "Version" => "2011-06-15",
             "RoleArn" => config.role_arn,
             "RoleSessionName" => "kura-volume-keys",
             "DurationSeconds" => "900",
             "WebIdentityToken" => String.trim(token)
           }),
         {:ok, response} <-
           KMSHTTP.post("https://sts.#{config.region}.amazonaws.com/", [], "application/x-www-form-urlencoded", body),
         {:ok, %{body: credentials}} <- Parsers.parse({:ok, %{body: response}}, :assume_role_with_web_identity),
         true <-
           Enum.all?(
             [credentials.access_key_id, credentials.secret_access_key, credentials.session_token],
             &(is_binary(&1) and &1 != "")
           ) do
      {:ok,
       %{
         access_key_id: credentials.access_key_id,
         secret_access_key: credentials.secret_access_key,
         security_token: credentials.session_token
       }}
    else
      _ -> {:error, :kms_unavailable}
    end
  end
end
