defmodule Tuist.Kura.VolumeKeys.TuistRootShareProvider do
  @moduledoc """
  Share provider backed by Tuist's root keys (`Tuist.Environment.kura_volume_root_keys/0`).

  A share is wrapped with AES-256-GCM under the active root key and stored as
  `%{"provider" => "tuist_root", "key_id" => id, "ciphertext" => base64(nonce || ciphertext || tag)}`
  with a random 12-byte nonce and a 16-byte tag. Any configured root key can
  unwrap, selected by `key_id`.
  """
  @behaviour Tuist.Kura.VolumeKeys.ShareProvider

  alias Tuist.Environment

  @provider "tuist_root"
  @nonce_bytes 12
  @tag_bytes 16

  @impl true
  def provider, do: @provider

  @impl true
  def wrap(plaintext, aad) when is_binary(plaintext) and is_binary(aad) do
    case Environment.kura_volume_root_keys() do
      [{key_id, key} | _] ->
        nonce = :crypto.strong_rand_bytes(@nonce_bytes)
        {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, aad, @tag_bytes, true)

        {:ok,
         %{
           "provider" => @provider,
           "key_id" => key_id,
           "ciphertext" => Base.encode64(nonce <> ciphertext <> tag)
         }}

      [] ->
        {:error, :root_keys_unavailable}
    end
  end

  @impl true
  def unwrap(%{"provider" => @provider, "key_id" => key_id, "ciphertext" => encoded}, aad)
      when is_binary(key_id) and is_binary(encoded) and is_binary(aad) do
    with {:ok, key} <- root_key(key_id),
         {:ok, <<nonce::binary-size(@nonce_bytes), sealed::binary>>} when byte_size(sealed) >= @tag_bytes <-
           Base.decode64(encoded) do
      ciphertext = binary_part(sealed, 0, byte_size(sealed) - @tag_bytes)
      tag = binary_part(sealed, byte_size(sealed), -@tag_bytes)

      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, aad, tag, false) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    else
      {:error, :unknown_root_key} = error -> error
      _ -> {:error, :malformed_share}
    end
  end

  def unwrap(_share, _aad), do: {:error, :malformed_share}

  defp root_key(key_id) do
    case List.keyfind(Environment.kura_volume_root_keys(), key_id, 0) do
      {^key_id, key} -> {:ok, key}
      nil -> {:error, :unknown_root_key}
    end
  end
end
