defmodule Atlas.LLMs.ChatGPTTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.ChatGPT.Config

  test "requests a device code without borrowing a third-party client identity" do
    expect(Config, :client_id, fn -> {:ok, "atlas-owned-client"} end)

    expect(Req, :post, fn opts ->
      assert opts[:url] == "https://auth.openai.com/api/accounts/deviceauth/usercode"
      assert opts[:json] == %{client_id: "atlas-owned-client"}
      assert opts[:retry] == false
      assert opts[:redirect] == false
      {:ok, %{status: 200, body: %{"device_auth_id" => "device-id", "usercode" => "USER-CODE", "interval" => "5"}}}
    end)

    assert {:ok, %{"user_code" => "USER-CODE", "verification_url" => "https://auth.openai.com/codex/device"}} =
             ChatGPT.start()
  end

  test "device authorization exchanges the provider-issued PKCE verifier" do
    expect(Req, :post, fn opts ->
      assert opts[:url] == "https://auth.openai.com/api/accounts/deviceauth/token"
      assert opts[:json] == %{"device_auth_id" => "device-id", "user_code" => "USER-CODE"}
      {:ok, %{status: 200, body: %{"authorization_code" => "code", "code_verifier" => "verifier"}}}
    end)

    expect(Req, :post, fn opts ->
      assert opts[:url] == "https://auth.openai.com/oauth/token"
      assert opts[:form][:client_id] == "atlas-owned-client"
      assert opts[:form][:code_verifier] == "verifier"
      assert opts[:form][:redirect_uri] == "https://auth.openai.com/deviceauth/callback"
      {:ok, %{status: 200, body: %{"access_token" => "access", "refresh_token" => "refresh", "expires_in" => 3600}}}
    end)

    assert {:ok, %{access_token: "access", refresh_token: "refresh"}} = ChatGPT.poll(login())
  end

  test "pending authorization is distinct from fatal or transient failures" do
    for status <- [403, 404] do
      expect(Req, :post, fn _opts -> {:ok, %{status: status, body: %{"secret" => "never returned"}}} end)
      assert {:error, :authorization_pending} = ChatGPT.poll(login())
    end

    expect(Req, :post, fn _opts -> {:error, %{request: "secret"}} end)
    assert {:error, :provider_unavailable} = ChatGPT.poll(login())
    expect(Req, :post, fn _opts -> {:ok, %{status: 500, body: "sensitive response"}} end)
    assert {:error, {:http_status, 500}} = ChatGPT.poll(login())
  end

  test "malformed successful responses are rejected" do
    expect(Config, :client_id, fn -> {:ok, "atlas-owned-client"} end)

    expect(Req, :post, fn _opts ->
      {:ok, %{status: 200, body: %{"device_auth_id" => "id", "user_code" => "code", "interval" => "bad"}}}
    end)

    assert {:error, :invalid_provider_response} = ChatGPT.start()
  end

  test "refresh sends a bounded non-retrying request and validates token responses" do
    expect(Config, :client_id, fn -> {:ok, "atlas-owned-client"} end)

    expect(Req, :post, fn opts ->
      assert opts[:form] == [grant_type: "refresh_token", client_id: "atlas-owned-client", refresh_token: "refresh"]
      assert opts[:retry] == false
      assert opts[:redirect] == false
      {:ok, %{status: 200, body: %{"access_token" => "access", "refresh_token" => "rotated", "expires_in" => 3600}}}
    end)

    assert {:ok, %{refresh_token: "rotated"}} = ChatGPT.refresh("refresh")
  end

  test "uses the access token expiry when expires_in is omitted and retains a non-rotated refresh token" do
    expect(Config, :client_id, fn -> {:ok, "atlas-owned-client"} end)
    expires_at = DateTime.add(DateTime.utc_now(:second), 3600)
    payload = Base.url_encode64(JSON.encode!(%{exp: DateTime.to_unix(expires_at)}), padding: false)
    token = "header.#{payload}.signature"
    expect(Req, :post, fn _opts -> {:ok, %{status: 200, body: %{"access_token" => token}}} end)
    assert {:ok, %{expires_at: ^expires_at, refresh_token: "retained"}} = ChatGPT.refresh("retained")
  end

  test "rejects opaque tokens without expiry rather than treating them as indefinitely valid" do
    expect(Config, :client_id, fn -> {:ok, "atlas-owned-client"} end)
    expect(Req, :post, fn _opts -> {:ok, %{status: 200, body: %{"access_token" => "opaque"}}} end)
    assert {:error, :invalid_provider_response} = ChatGPT.refresh("retained")
  end

  defp login, do: %{"device_auth_id" => "device-id", "user_code" => "USER-CODE", "client_id" => "atlas-owned-client"}
end
