defmodule Tuist.Origin.Auth do
  @moduledoc """
  Origin app credentials and verification of Origin-signed receipts and deliveries.
  Signing keys stay on the server; installation tokens are minted just in time.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore

  @issuer "https://api.cursor.com/v1/origin"

  def app_jwt do
    case Environment.origin_app_credentials() do
      %{app_id: app_id, private_key: private_key} ->
        now = System.system_time(:second)

        {_, token} =
          private_key
          |> JOSE.JWK.from_pem()
          |> JOSE.JWT.sign(%{"alg" => "EdDSA", "kid" => app_id, "typ" => "JWT"}, %{
            "iss" => app_id,
            "aud" => "origin-apps",
            "iat" => now,
            "exp" => now + 300
          })
          |> JOSE.JWS.compact()

        {:ok, token}

      _ ->
        {:error, :not_configured}
    end
  end

  def verify_receipt(token) when is_binary(token) do
    verify_with_rotation(fn keys -> receipt_claims(token, keys) end)
  end

  def verify_receipt(_), do: {:error, :invalid_signature}

  def verify_webhook(body, headers) do
    with id when is_binary(id) and id != "" <- headers["webhook-id"],
         timestamp when is_binary(timestamp) <- headers["webhook-timestamp"],
         {seconds, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - seconds) <= 300,
         signature when is_binary(signature) <- headers["webhook-signature"],
         "v1ed," <> encoded <- Enum.find(String.split(signature), &String.starts_with?(&1, "v1ed,")),
         {:ok, signature} <- Base.decode64(encoded) do
      digest = :sha256 |> :crypto.hash("#{id}.#{timestamp}.#{body}") |> Base.encode16(case: :lower)

      verify_with_rotation(fn keys ->
        if Enum.any?(keys, &valid_webhook_key?(&1, digest, signature)),
          do: {:ok, id},
          else: {:error, :invalid_signature}
      end)
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_with_rotation(verify) do
    with {:ok, keys} <- signing_keys() do
      case verify.(keys) do
        {:error, :invalid_signature} ->
          with {:ok, fresh_keys} <- fetch_signing_keys(), do: verify.(fresh_keys)

        result ->
          result
      end
    end
  end

  defp signing_keys do
    case KeyValueStore.get([__MODULE__, :jwks]) do
      nil -> fetch_signing_keys()
      keys -> {:ok, keys}
    end
  end

  defp fetch_signing_keys do
    case Req.get(@issuer <> "/keys", retry: false, redirect: false, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        keys = Enum.filter(keys, &match?(%{"kty" => "OKP", "crv" => "Ed25519"}, &1))
        KeyValueStore.put([__MODULE__, :jwks], keys, ttl: to_timeout(minute: 10))
        {:ok, keys}

      _ ->
        {:error, :verification_unavailable}
    end
  end

  defp receipt_claims(token, keys) do
    with %{app_id: app_id} <- Environment.origin_app_credentials(),
         %JOSE.JWS{fields: %{"kid" => kid, "typ" => "origin-installation-receipt+jwt"}} <-
           JOSE.JWT.peek_protected(token),
         key when not is_nil(key) <- Enum.find(keys, &(&1["kid"] == kid)),
         {true, %JOSE.JWT{fields: claims}, _} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["EdDSA"], token),
         %{
           "iss" => @issuer,
           "aud" => ^app_id,
           "sub" => id,
           "namespace_id" => namespace_id,
           "exp" => exp,
           "iat" => iat,
           "jti" => jti
         } <- claims,
         true <- is_integer(exp) and exp > System.system_time(:second),
         true <- is_integer(iat) and iat <= System.system_time(:second) + 30,
         true <- is_binary(id) and is_binary(namespace_id) and is_binary(jti) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp valid_webhook_key?(%{"x" => x}, digest, signature) do
    case Base.url_decode64(x, padding: false) do
      {:ok, public_key} -> :crypto.verify(:eddsa, :none, digest, signature, [public_key, :ed25519])
      _ -> false
    end
  rescue
    _ -> false
  end
end
