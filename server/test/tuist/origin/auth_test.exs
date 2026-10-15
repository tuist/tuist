defmodule Tuist.Origin.AuthTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Origin.Auth

  setup do
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, pem} = JOSE.JWK.to_pem(key)
    {_, public} = JOSE.JWK.to_public_map(key)
    public = Map.put(public, "kid", "origin-key")
    stub(Environment, :origin_app_credentials, fn -> %{app_id: "app-tuist", private_key: pem} end)
    stub(KeyValueStore, :get, fn _ -> [public] end)
    %{key: key, public: public}
  end

  test "app JWT is an Ed25519 credential for the configured app", %{key: key} do
    assert {:ok, token} = Auth.app_jwt()
    assert {true, %{fields: claims}, %{fields: header}} = JOSE.JWT.verify_strict(key, ["EdDSA"], token)
    assert header["kid"] == "app-tuist"
    assert claims["iss"] == "app-tuist"
    assert claims["aud"] == "origin-apps"
    assert claims["exp"] - claims["iat"] == 300
  end

  test "receipts require the correct app, issuer, type, signature and expiry", %{key: key} do
    now = System.system_time(:second)

    claims = %{
      "iss" => "https://api.cursor.com/v1/origin",
      "aud" => "app-tuist",
      "sub" => "inst-1",
      "namespace_id" => "ns-1",
      "iat" => now,
      "exp" => now + 300,
      "jti" => "unique",
      "state" => "nonce"
    }

    header = %{"alg" => "EdDSA", "kid" => "origin-key", "typ" => "origin-installation-receipt+jwt"}
    assert {:ok, ^claims} = Auth.verify_receipt(sign(key, header, claims))

    stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: %{"keys" => []}}} end)
    stub(KeyValueStore, :put, fn _, _, _ -> :ok end)

    for bad_claims <- [
          Map.put(claims, "aud", "another-app"),
          Map.put(claims, "iss", "another-issuer"),
          Map.put(claims, "exp", now - 1),
          Map.put(claims, "iat", now + 100),
          Map.delete(claims, "namespace_id")
        ] do
      assert {:error, :invalid_signature} = Auth.verify_receipt(sign(key, header, bad_claims))
    end

    assert {:error, :invalid_signature} = Auth.verify_receipt(sign(key, Map.put(header, "typ", "JWT"), claims))
    assert {:error, :invalid_signature} = Auth.verify_receipt("malformed")
  end

  test "webhooks sign the raw-body digest, reject tampering and old deliveries, and refresh rotated keys", %{
    key: key,
    public: public
  } do
    body = ~s({"deliveryId":"delivery-1","event":{"type":"ping"}})
    timestamp = to_string(System.system_time(:second))
    input = "delivery-1.#{timestamp}.#{body}"
    digest = Base.encode16(:crypto.hash(:sha256, input), case: :lower)
    {_, key_map} = JOSE.JWK.to_map(key)
    {:ok, private} = Base.url_decode64(key_map["d"], padding: false)
    signature = Base.encode64(:crypto.sign(:eddsa, :none, digest, [private, :ed25519]))

    headers = %{
      "webhook-id" => "delivery-1",
      "webhook-timestamp" => timestamp,
      "webhook-signature" => "v1ed,#{signature}"
    }

    assert {:ok, "delivery-1"} = Auth.verify_webhook(body, headers)

    stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: %{"keys" => [public]}}} end)
    stub(KeyValueStore, :put, fn _, _, _ -> :ok end)
    assert {:error, :invalid_signature} = Auth.verify_webhook(body <> " ", headers)
    assert {:error, :invalid_signature} = Auth.verify_webhook(body, Map.put(headers, "webhook-timestamp", "0"))
    direct = Base.encode64(:crypto.sign(:eddsa, :none, input, [private, :ed25519]))

    assert {:error, :invalid_signature} =
             Auth.verify_webhook(body, Map.put(headers, "webhook-signature", "v1ed,#{direct}"))

    stub(KeyValueStore, :get, fn _ -> [] end)
    assert {:ok, "delivery-1"} = Auth.verify_webhook(body, headers)
  end

  defp sign(key, header, claims) do
    {_, token} = key |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()
    token
  end
end
