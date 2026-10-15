defmodule Tuist.Origin.Signatures do
  @moduledoc """
  Verifies installation receipts and webhook deliveries using Cursor's signing
  keys, never the Tuist app's private key.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Origin.Client

  @issuer "https://api.cursor.com/v1/origin"

  def verify_receipt(token, expected_state) when is_binary(token) and is_binary(expected_state) do
    with [_payload, _claims, _signature] <- String.split(token, "."),
         [header | _] = String.split(token, "."),
         {:ok, header} <- Base.url_decode64(header, padding: false),
         {:ok, %{"alg" => "EdDSA", "typ" => "origin-installation-receipt+jwt", "kid" => kid}} <-
           JSON.decode(header),
         {:ok, keys} <- keys(),
         {:ok, key} <- receipt_key(keys, kid),
         {true, %{fields: claims}, _} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["EdDSA"], token),
         true <- valid_claims?(claims, expected_state) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_origin_receipt}
    end
  rescue
    _ -> {:error, :invalid_origin_receipt}
  end

  def verify_receipt(_, _), do: {:error, :invalid_origin_receipt}

  def verify_webhook(body, headers) do
    with id when is_binary(id) <- headers["webhook-id"],
         timestamp when is_binary(timestamp) <- headers["webhook-timestamp"],
         {time, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - time) <= 300,
         signatures when is_binary(signatures) <- headers["webhook-signature"],
         {:ok, keys} <- keys() do
      digest =
        :sha256 |> :crypto.hash("#{id}.#{timestamp}.#{body}") |> Base.encode16(case: :lower)

      valid? =
        signatures
        |> String.split()
        |> Enum.any?(fn
          "v1ed," <> signature ->
            case Base.decode64(signature) do
              {:ok, signature} -> Enum.any?(keys, &verify_ed25519(&1, digest, signature))
              _ -> false
            end

          _ ->
            false
        end)

      if valid?, do: :ok, else: {:error, :invalid_origin_signature}
    else
      {:error, :origin_keys_unavailable} = error -> error
      _ -> {:error, :invalid_origin_signature}
    end
  end

  defp valid_claims?(claims, state) do
    claims["iss"] == @issuer and claims["aud"] == Environment.origin_app_id() and
      claims["state"] == state and valid_timestamps?(claims) and
      is_binary(claims["sub"]) and claims["sub"] != "" and is_binary(claims["namespace_id"])
  end

  defp valid_timestamps?(claims) do
    now = System.system_time(:second)

    is_integer(claims["exp"]) and claims["exp"] > now and
      is_integer(claims["iat"]) and claims["iat"] <= now + 60
  end

  defp keys do
    KeyValueStore.get_or_update(
      :origin_signing_keys,
      [ttl: to_timeout(minute: 1)],
      &Client.signing_keys/0
    )
  end

  defp receipt_key(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid and &1["kty"] == "OKP" and &1["crv"] == "Ed25519")) do
      nil ->
        with {:ok, fresh_keys} <- Client.signing_keys(),
             key when is_map(key) <-
               Enum.find(
                 fresh_keys,
                 &(&1["kid"] == kid and &1["kty"] == "OKP" and &1["crv"] == "Ed25519")
               ) do
          {:ok, key}
        else
          _ -> {:error, :unknown_origin_key}
        end

      key ->
        {:ok, key}
    end
  end

  defp verify_ed25519(%{"kty" => "OKP", "crv" => "Ed25519", "x" => x}, digest, signature) do
    case Base.url_decode64(x, padding: false) do
      {:ok, key} -> :crypto.verify(:eddsa, :none, digest, signature, [key, :ed25519])
      _ -> false
    end
  rescue
    _ -> false
  end

  defp verify_ed25519(_, _, _), do: false
end
