defmodule Tuist.GitHub.AppTest do
  use ExUnit.Case, async: true
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.KeyValueStore
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  @creds %{
    app_name: "tuist",
    app_id: "test-app-id",
    client_id: "test-client-id",
    client_secret: "test-client-secret",
    private_key: "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----",
    webhook_secret: "test-webhook-secret"
  }

  setup do
    stub(JOSE.JWK, :from_pem, fn _ -> "pem" end)
    stub(JOSE.JWT, :sign, fn _, _, _ -> "signed_pem" end)
    stub(JOSE.JWS, :compact, fn _ -> {%{}, "jwt"} end)
    stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    stub(KeyValueStore, :get_or_update, fn _, _, func -> func.() end)
    stub(VCS, :github_app_credentials, fn -> @creds end)
    stub(VCS, :github_app_credentials, fn _ -> @creds end)
    :ok
  end

  describe "get_installation_token/2" do
    test "returns installation token when request succeeds" do
      # Given
      installation_id = "12345"
      token = "ghs_16C7e42F292c6912E7710c838347Ae178B4a"
      expires_at = "2024-04-30T11:20:30Z"

      stub(Req, :post, fn opts ->
        assert Keyword.get(opts, :url) =~ "/app/installations/#{installation_id}/access_tokens"
        assert opts |> Keyword.get(:headers) |> Enum.member?({"Authorization", "Bearer jwt"})

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "token" => token,
             "expires_at" => expires_at
           }
         }}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:ok, %{token: ^token, expires_at: expires_at_datetime}} = result
      assert expires_at_datetime == ~U[2024-04-30 11:20:30Z]
    end

    test "returns error when request fails with non-201 status" do
      # Given
      installation_id = "12345"

      stub(Req, :post, fn _opts ->
        {:ok,
         %Req.Response{
           status: 401,
           body: %{"message" => "Bad credentials"}
         }}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, "Failed to get installation token"} = result
    end

    test "returns error when HTTP connection fails after retries" do
      # Given
      installation_id = "12345"

      # Note: The actual Req client will retry this error 3 times with exponential backoff
      # before returning the error. This test simulates the final error state after retries.
      stub(Req, :post, fn _opts ->
        {:error, %Req.HTTPError{protocol: :http2, reason: :closed_for_writing}}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, error_message} = result
      assert error_message =~ "GitHub API connection error"
      assert error_message =~ "closed_for_writing"
    end

    test "returns error when unexpected error occurs" do
      # Given
      installation_id = "12345"

      stub(Req, :post, fn _opts ->
        {:error, :timeout}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, error_message} = result
      assert error_message =~ "Unexpected error getting installation token"
      assert error_message =~ "timeout"
    end

    test "uses the GitHub Enterprise Server API URL when api_url is provided" do
      # Given
      installation_id = "12345"
      ghes_api_url = "https://github.example.com/api/v3"
      pinned_url = "https://198.51.100.10/api/v3/app/installations/#{installation_id}/access_tokens"
      token = "ghs_ghes_token"
      expires_at = "2024-04-30T11:20:30Z"

      stub(SSRFGuard, :pin, fn url ->
        assert url == "#{ghes_api_url}/app/installations/#{installation_id}/access_tokens"
        {:ok, pinned_url, "github.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn "github.example.com" -> [hostname: "github.example.com"] end)

      stub(Req, :post, fn opts ->
        # The Req call uses the IP-pinned URL with TLS hostname preserved
        assert Keyword.get(opts, :url) == pinned_url
        assert Keyword.get(opts, :connect_options) == [hostname: "github.example.com"]

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "token" => token,
             "expires_at" => expires_at
           }
         }}
      end)

      # When
      result = App.get_installation_token(installation_id, api_url: ghes_api_url)

      # Then
      assert {:ok, %{token: ^token}} = result
    end

    test "uses a persisted API override for installation tokens and their cache key" do
      installation = %GitHubAppInstallation{
        id: "proxy-installation",
        installation_id: "12345",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      }

      expect(KeyValueStore, :get_or_update, fn key, _opts, fetch ->
        assert key == [
                 App,
                 "installation_token",
                 "installation:#{installation.id}",
                 installation.api_url,
                 installation.installation_id
               ]

        fetch.()
      end)

      expect(SSRFGuard, :pin, fn url ->
        assert url == "#{installation.api_url}/app/installations/12345/access_tokens"
        {:ok, "https://198.51.100.10/api/v3/app/installations/12345/access_tokens", "proxy.example.com"}
      end)

      expect(SSRFGuard, :connect_options, fn "proxy.example.com" -> [hostname: "proxy.example.com"] end)

      expect(Req, :post, fn opts ->
        assert opts[:connect_options] == [hostname: "proxy.example.com"]
        assert opts[:url] == "https://198.51.100.10/api/v3/app/installations/12345/access_tokens"
        assert opts[:redirect] == false
        {:ok, %Req.Response{status: 201, body: %{"token" => "proxy-token", "expires_at" => "2024-04-30T11:20:30Z"}}}
      end)

      assert {:ok, %{token: "proxy-token"}} = App.get_installation_token(installation)
    end

    test "never shares tokens between rows using the same endpoint and upstream installation ID" do
      first = %GitHubAppInstallation{
        id: "first",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3",
        installation_id: "123"
      }

      second = %{first | id: "second"}

      expect(KeyValueStore, :get_or_update, 2, fn key, _opts, _fetch ->
        send(self(), {:token_key, key})
        {:ok, %{token: "token"}}
      end)

      assert {:ok, _} = App.get_installation_token(first)
      assert {:ok, _} = App.get_installation_token(second)
      assert_received {:token_key, first_key}
      assert_received {:token_key, second_key}
      refute first_key == second_key
    end

    test "rejects a persisted API override that resolves to a private IP" do
      installation = %GitHubAppInstallation{
        installation_id: "12345",
        client_url: "https://github.internal.example.com",
        api_url: "https://proxy.example.com/api/v3"
      }

      expect(SSRFGuard, :pin, fn _ -> {:error, :private_ip_resolved} end)
      reject(&Req.post/1)
      assert {:error, message} = App.get_installation_token(installation)
      assert message =~ "SSRF"
    end

    test "rejects requests to GitHub Enterprise hosts that resolve to private IPs" do
      installation_id = "12345"
      ghes_api_url = "https://internal.example.com/api/v3"

      stub(SSRFGuard, :pin, fn _url -> {:error, :private_ip_resolved} end)

      result = App.get_installation_token(installation_id, api_url: ghes_api_url)

      assert {:error, message} = result
      assert message =~ "SSRF"
    end
  end

  describe "get_jwt/1" do
    test "returns a signed JWT using the globally-configured App credentials" do
      assert {:ok, "jwt"} = App.get_jwt()
    end

    test "returns a signed JWT using credentials passed via opts (per-installation GHES App)" do
      ghes_creds = Map.put(@creds, :app_id, "ghes-app-id")

      # `get_jwt` must NOT fall back to the global credentials when
      # the caller supplied their own — the JWT must be issued with
      # the GHES App's `iss` (app_id) so GitHub on that GHES instance
      # accepts it.
      expect(JOSE.JWT, :sign, fn _key, _header, %{"iss" => iss} = _claims ->
        assert iss == "ghes-app-id"
        "signed_pem"
      end)

      assert {:ok, "jwt"} = App.get_jwt(credentials: ghes_creds)
    end

    test "returns {:error, _} when no App credentials are configured" do
      stub(VCS, :github_app_credentials, fn -> nil end)

      assert {:error, message} = App.get_jwt()
      assert message =~ "GitHub App is not configured"
    end
  end
end
