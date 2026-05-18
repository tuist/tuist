defmodule Tuist.OAuth2.SSOClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.OAuth2.SSOClient
  alias Tuist.OAuth2.SSRFGuard

  describe "exchange_token/5" do
    test "returns decoded JSON body on a successful 200 response" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn "idp.example.com" -> [] end)

      expect(Req, :post, fn _url, opts ->
        assert {"authorization", "Basic " <> _} = List.keyfind(opts[:headers], "authorization", 0)
        assert {"content-type", "application/x-www-form-urlencoded"} in opts[:headers]
        assert opts[:body] =~ "grant_type=authorization_code"
        assert opts[:body] =~ "code=the-code"

        {:ok,
         %Req.Response{
           status: 200,
           body: ~s({"access_token":"tok","token_type":"Bearer","expires_in":3600})
         }}
      end)

      assert {:ok, %{"access_token" => "tok", "token_type" => "Bearer", "expires_in" => 3600}} =
               SSOClient.exchange_token(
                 "https://idp.example.com/oauth2/token",
                 "the-code",
                 "https://app.example.com/callback",
                 "client-id",
                 "client-secret"
               )
    end

    test "uses Basic Auth with the client credentials" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn _ -> [] end)

      expect(Req, :post, fn _url, opts ->
        {"authorization", auth_header} = List.keyfind(opts[:headers], "authorization", 0)
        assert "Basic " <> encoded = auth_header
        assert Base.decode64!(encoded) == "my-id:my-secret"

        {:ok, %Req.Response{status: 200, body: ~s({"access_token":"tok"})}}
      end)

      assert {:ok, _} =
               SSOClient.exchange_token("https://idp.example.com/token", "code", "https://cb", "my-id", "my-secret")
    end

    test "returns an error tuple when the token endpoint returns a non-2xx status" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn _ -> [] end)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 400, body: ~s({"error":"invalid_grant"})}}
      end)

      assert {:error, {:token_exchange_failed, 400, _body}} =
               SSOClient.exchange_token("https://idp.example.com/token", "bad-code", "https://cb", "id", "secret")
    end

    test "propagates SSRFGuard pin errors" do
      expect(SSRFGuard, :pin, fn _url -> {:error, :private_ip_resolved} end)

      assert {:error, :private_ip_resolved} =
               SSOClient.exchange_token("https://10.0.0.1/token", "code", "https://cb", "id", "secret")
    end

    test "propagates Req transport errors" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn _ -> [] end)
      expect(Req, :post, fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end)

      assert {:error, %Mint.TransportError{reason: :timeout}} =
               SSOClient.exchange_token("https://idp.example.com/token", "code", "https://cb", "id", "secret")
    end
  end

  describe "fetch_userinfo/2" do
    test "returns decoded JSON body on a successful 200 response" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn "idp.example.com" -> [] end)

      expect(Req, :get, fn _url, opts ->
        {"authorization", auth_header} = List.keyfind(opts[:headers], "authorization", 0)
        assert auth_header == "Bearer my-token"

        {:ok,
         %Req.Response{
           status: 200,
           body: ~s({"sub":"user-123","email":"user@example.com","name":"User"})
         }}
      end)

      assert {:ok, %{"sub" => "user-123", "email" => "user@example.com"}} =
               SSOClient.fetch_userinfo("https://idp.example.com/userinfo", "my-token")
    end

    test "returns an error tuple when the userinfo endpoint returns a non-200 status" do
      expect(SSRFGuard, :pin, fn url -> {:ok, url, "idp.example.com"} end)
      expect(SSRFGuard, :connect_options, fn _ -> [] end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: ~s({"error":"unauthorized"})}}
      end)

      assert {:error, {:userinfo_request_failed, 401, _}} =
               SSOClient.fetch_userinfo("https://idp.example.com/userinfo", "expired-token")
    end

    test "propagates SSRFGuard pin errors" do
      expect(SSRFGuard, :pin, fn _url -> {:error, :dns_failure} end)

      assert {:error, :dns_failure} =
               SSOClient.fetch_userinfo("https://nope.invalid/userinfo", "token")
    end
  end
end
