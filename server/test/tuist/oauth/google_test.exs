defmodule Tuist.OAuth.GoogleTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.OAuth.Google

  setup_all do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public_key} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{key: key, public_key: Map.put(public_key, "kid", "google-key")}
  end

  setup %{public_key: public_key} do
    stub(Environment, :google_oauth_client_id, fn -> "tuist-client" end)
    stub(KeyValueStore, :get, fn [Google, "public_keys"] -> [public_key] end)

    now = DateTime.to_unix(DateTime.utc_now())

    %{
      claims: %{
        "aud" => "tuist-client",
        "iss" => "https://accounts.google.com",
        "exp" => now + 3600,
        "iat" => now,
        "sub" => "google-user",
        "email" => "person@gmail.com",
        "email_verified" => true,
        "nonce" => "session-nonce"
      }
    }
  end

  test "verifies a signed Google identity bound to the browser session", %{key: key, claims: claims} do
    assert {:ok, ^claims} = Google.verify_identity_token(sign(key, claims), "session-nonce")
  end

  test "rejects invalid identity claims", %{key: key, claims: claims} do
    for {field, value, reason} <- [
          {"aud", "another-client", :invalid_audience},
          {"iss", "https://attacker.example", :invalid_issuer},
          {"exp", 0, :expired_token},
          {"exp", "9999999999", :expired_token},
          {"iat", claims["iat"] + 3600, :invalid_issued_at},
          {"nonce", "another-session", :invalid_nonce},
          {"sub", "", :missing_subject},
          {"email_verified", false, :unverified_email},
          {"email", nil, :unverified_email}
        ] do
      assert {:error, ^reason} = Google.verify_identity_token(sign(key, Map.put(claims, field, value)), "session-nonce")
    end
  end

  test "rejects an attacker signature", %{claims: claims} do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    assert {:error, :invalid_token} = Google.verify_identity_token(sign(key, claims), "session-nonce")
  end

  test "rejects symmetric signatures", %{claims: claims} do
    token =
      "attacker-secret"
      |> JOSE.JWK.from_oct()
      |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => "google-key"}, claims)
      |> JOSE.JWS.compact()
      |> elem(1)

    assert {:error, :invalid_token} = Google.verify_identity_token(token, "session-nonce")
  end

  test "rejects malformed credentials and absent nonces" do
    for token <- [nil, %{}, "", "not-a-token"] do
      assert {:error, :invalid_token} = Google.verify_identity_token(token, "session-nonce")
    end

    assert {:error, :invalid_token} = Google.verify_identity_token("token", nil)
  end

  test "fetches and caches public keys using Google's cache lifetime", %{key: key, public_key: public_key, claims: claims} do
    stub(KeyValueStore, :get, fn _ -> nil end)

    expect(Req, :get, fn "https://www.googleapis.com/oauth2/v3/certs", _ ->
      {:ok,
       Req.Response.new(status: 200, body: %{"keys" => [public_key]}, headers: [{"cache-control", "public, max-age=120"}])}
    end)

    expect(KeyValueStore, :put, fn [Google, "public_keys"], [^public_key], [ttl: 120_000] -> {:ok, true} end)

    assert {:ok, ^claims} = Google.verify_identity_token(sign(key, claims), "session-nonce")
  end

  test "fails closed when Google keys are unavailable", %{key: key, claims: claims} do
    stub(KeyValueStore, :get, fn _ -> nil end)
    stub(Req, :get, fn _, _ -> {:ok, %{status: 503}} end)
    assert {:error, :public_keys_unavailable} = Google.verify_identity_token(sign(key, claims), "session-nonce")
  end

  test "recognizes Google's authoritative email addresses", %{claims: claims} do
    assert Google.authoritative_email?(claims)
    assert Google.authoritative_email?(Map.merge(claims, %{"email" => "person@tuist.dev", "hd" => "tuist.dev"}))
    refute Google.authoritative_email?(Map.put(claims, "email", "person@example.com"))
  end

  defp sign(key, claims) do
    key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "google-key"}, claims) |> JOSE.JWS.compact() |> elem(1)
  end
end
