defmodule Tuist.Origin.SignaturesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Origin.Signatures

  setup do
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    public = Map.put(public, "kid", "cursor_key")
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)

    stub(KeyValueStore, :get_or_update, fn :origin_signing_keys, _options, _loader ->
      {:ok, [public]}
    end)

    now = System.system_time(:second)

    claims = %{
      "iss" => "https://api.cursor.com/v1/origin",
      "aud" => "app_tuist",
      "sub" => "i_test",
      "namespace_id" => "ns_test",
      "state" => "browser_state",
      "iat" => now,
      "exp" => now + 300
    }

    %{key: key, claims: claims}
  end

  test "verifies a Cursor-signed receipt and exact browser state", %{key: key, claims: claims} do
    assert {:ok, ^claims} = Signatures.verify_receipt(receipt(key, claims), "browser_state")
  end

  test "rejects wrong state, audience, issuer, and expired receipts", %{key: key, claims: claims} do
    assert {:error, :invalid_origin_receipt} =
             Signatures.verify_receipt(receipt(key, claims), "other_browser")

    for {field, value} <- [{"aud", "app_other"}, {"iss", "https://attacker.test"}, {"exp", 0}] do
      assert {:error, :invalid_origin_receipt} =
               Signatures.verify_receipt(
                 receipt(key, Map.put(claims, field, value)),
                 "browser_state"
               )
    end
  end

  test "rejects missing, non-integer, and future receipt timestamps", %{key: key, claims: claims} do
    for {field, value} <- [
          {"exp", nil},
          {"exp", to_string(claims["exp"])},
          {"iat", nil},
          {"iat", to_string(claims["iat"])},
          {"iat", claims["iat"] + 120}
        ] do
      assert {:error, :invalid_origin_receipt} =
               Signatures.verify_receipt(receipt(key, Map.put(claims, field, value)), "browser_state")
    end
  end

  test "rejects signatures from the app's key instead of Cursor's key", %{claims: claims} do
    app_key = JOSE.JWK.generate_key({:okp, :Ed25519})

    assert {:error, :invalid_origin_receipt} =
             Signatures.verify_receipt(receipt(app_key, claims), "browser_state")
  end

  test "rejects malformed and missing receipts" do
    assert {:error, :invalid_origin_receipt} =
             Signatures.verify_receipt("not.jwt", "browser_state")

    assert {:error, :invalid_origin_receipt} = Signatures.verify_receipt(nil, nil)
  end

  test "verifies the hex SHA256 digest, not the raw Standard Webhooks content", %{key: key} do
    body = ~s({"deliveryId":"whd_test"})
    headers = webhook_headers(key, body, System.system_time(:second))
    assert :ok = Signatures.verify_webhook(body, headers)
    assert {:error, :invalid_origin_signature} = Signatures.verify_webhook(body <> " ", headers)

    assert {:error, :invalid_origin_signature} =
             Signatures.verify_webhook(body, Map.put(headers, "webhook-id", "whd_other"))
  end

  test "rejects replay-window violations and missing signatures", %{key: key} do
    body = "{}"
    headers = webhook_headers(key, body, System.system_time(:second) - 301)
    assert {:error, :invalid_origin_signature} = Signatures.verify_webhook(body, headers)
    assert {:error, :invalid_origin_signature} = Signatures.verify_webhook(body, %{})
  end

  defp receipt(key, claims) do
    {_, token} =
      key
      |> JOSE.JWT.sign(
        %{"alg" => "EdDSA", "kid" => "cursor_key", "typ" => "origin-installation-receipt+jwt"},
        claims
      )
      |> JOSE.JWS.compact()

    token
  end

  defp webhook_headers(key, body, timestamp) do
    {_, private} = JOSE.JWK.to_map(key)
    seed = Base.url_decode64!(private["d"], padding: false)

    digest =
      :sha256 |> :crypto.hash("whd_test.#{timestamp}.#{body}") |> Base.encode16(case: :lower)

    signature = :crypto.sign(:eddsa, :none, digest, [seed, :ed25519])

    %{
      "webhook-id" => "whd_test",
      "webhook-timestamp" => to_string(timestamp),
      "webhook-signature" => "v1ed," <> Base.encode64(signature)
    }
  end
end
