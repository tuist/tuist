defmodule Tuist.VCS.GitHubApiUrlTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  @client_url "https://github.internal.example.com"
  @api_url "https://proxy.example.com/api/v3"

  describe "installation_api_url/1" do
    test "uses the override on installation structs and maps" do
      assert VCS.installation_api_url(%GitHubAppInstallation{client_url: @client_url, api_url: @api_url}) == @api_url
      assert VCS.installation_api_url(%{client_url: @client_url, api_url: @api_url}) == @api_url
    end

    test "preserves existing GHES and github.com defaults" do
      assert VCS.installation_api_url(%GitHubAppInstallation{client_url: @client_url}) == "#{@client_url}/api/v3"
      assert VCS.installation_api_url(%{client_url: @client_url, api_url: nil}) == "#{@client_url}/api/v3"
      assert VCS.installation_api_url(%{client_url: @client_url, api_url: ""}) == "#{@client_url}/api/v3"
      assert VCS.installation_api_url(%GitHubAppInstallation{}) == "https://api.github.com"
    end
  end

  describe "github_api_request_url/3" do
    test "rebases canonical pagination links while preserving a proxy path prefix and query" do
      assert {:ok, "https://proxy.example.com/ghe/api/v3/installation/repositories?page=2"} =
               VCS.github_api_request_url(
                 "#{@client_url}/api/v3/installation/repositories?page=2",
                 @client_url,
                 "https://proxy.example.com/ghe/api/v3"
               )
    end

    test "leaves transport pagination links unchanged" do
      url = "#{@api_url}/installation/repositories?page=2"
      assert {:ok, ^url} = VCS.github_api_request_url(url, @client_url, @api_url)
    end

    test "matches hostnames without case sensitivity" do
      assert {:ok, "https://proxy.example.com/ghe/api/v3/repos?page=2"} =
               VCS.github_api_request_url(
                 "https://github.internal.example.com/api/v3/repos?page=2",
                 "https://GitHub.Internal.Example.Com",
                 "https://proxy.example.com/ghe/api/v3"
               )

      url = "https://PROXY.example.com/api/v3/repos?page=2"
      assert {:ok, ^url} = VCS.github_api_request_url(url, @client_url, @api_url)
    end

    test "rejects literal and encoded path traversal on canonical and transport links" do
      for base <- ["#{@client_url}/api/v3", @api_url],
          path <- [
            "/../admin",
            "/repos/./issues",
            "/%2e%2e/admin",
            "/repos/%2E%2E/admin",
            "/repos%2f..%2fadmin",
            "/repos%5c..%5cadmin"
          ] do
        assert {:error, _} = VCS.github_api_request_url(base <> path, @client_url, @api_url)
      end
    end

    test "rejects malformed percent encoding without raising" do
      for path <- ["/%", "/%2", "/%zz/repos"] do
        assert {:error, _} = VCS.github_api_request_url(@api_url <> path, @client_url, @api_url)
      end
    end

    test "rejects unrelated hosts, ports, schemes, and paths" do
      for url <- [
            "https://attacker.example/api/v3/repos",
            "https:/api/v3/repos",
            "/api/v3/repos",
            "http://github.internal.example.com/api/v3/repos",
            "#{@client_url}:444/api/v3/repos",
            "#{@client_url}/api/v30/repos",
            "#{@client_url}/login",
            "#{@api_url}/repos#fragment",
            "https://u:p@proxy.example.com/api/v3/repos"
          ] do
        assert {:error, _} = VCS.github_api_request_url(url, @client_url, @api_url)
      end
    end
  end

  describe "validate_api_url/1" do
    test "normalizes full API URLs including proxy prefixes" do
      assert {:ok, @api_url} = VCS.validate_api_url("  #{@api_url}/  ")

      assert {:ok, "https://proxy.example.com/github/api/v3"} =
               VCS.validate_api_url("https://proxy.example.com/github/api/v3")
    end

    test "rejects public GitHub endpoints, including mixed-case hostnames" do
      for url <- [
            "https://api.github.com",
            "https://API.GITHUB.COM/api/v3",
            "https://github.com/api/v3",
            "https://other.github.com",
            "https://api.github.com.",
            "https://GitHub.Com./api/v3"
          ] do
        assert {:error, :invalid_url} = VCS.validate_api_url(url)
      end
    end

    test "accepts empty optional values" do
      for value <- [nil, "", "   "] do
        assert {:ok, nil} = VCS.validate_api_url(value)
      end
    end

    test "requires HTTPS in production" do
      stub(Environment, :env, fn -> :prod end)
      assert {:error, :invalid_url} = VCS.validate_api_url("http://proxy.example.com/api/v3")
    end

    test "rejects malformed URLs and URL credentials, query strings, and fragments" do
      for value <- [
            123,
            "not-a-url",
            "ftp://proxy.example.com",
            "https://u:p@proxy.example.com",
            "#{@api_url}?x=1",
            "#{@api_url}#x"
          ] do
        assert {:error, :invalid_url} = VCS.validate_api_url(value)
      end
    end
  end

  describe "registration state" do
    test "round-trips and normalizes the API URL together with browser URL and owner" do
      token = VCS.generate_github_state_token(1, @client_url, "ios", "  #{@api_url}/  ")

      assert {:ok, %{account_id: 1, client_url: @client_url, github_app_owner: "ios", api_url: @api_url}} =
               VCS.verify_github_state_token(token)
    end

    test "installation URL carries the API override in signed state" do
      url = VCS.get_github_app_installation_url(%Account{id: 1}, client_url: @client_url, api_url: @api_url)
      token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")
      assert {:ok, %{client_url: @client_url, api_url: @api_url}} = VCS.verify_github_state_token(token)
    end

    test "ignores an API override when installing the shared github.com App" do
      stub(Environment, :github_app_name, fn -> "tuist" end)
      url = VCS.get_github_app_installation_url(%Account{id: 1}, api_url: @api_url)
      token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")
      assert {:ok, %{client_url: "https://github.com", api_url: nil}} = VCS.verify_github_state_token(token)
    end

    test "accepts every older state shape without an override" do
      for payload <- [1, {1, @client_url}, {1, @client_url, "ios"}] do
        token = Phoenix.Token.sign(TuistWeb.Endpoint, "github_state", payload)
        assert {:ok, %{account_id: 1, api_url: nil}} = VCS.verify_github_state_token(token)
      end
    end

    test "rejects malformed owners and payloads without raising" do
      for payload <- [{1, @client_url, 123}, {1, @client_url, %{}, @api_url}, {1, nil}, {"1", @client_url}] do
        token = Phoenix.Token.sign(TuistWeb.Endpoint, "github_state", payload)
        assert {:error, :invalid} = VCS.verify_github_state_token(token)
      end
    end

    test "rejects invalid API URLs even in signed state" do
      token = VCS.generate_github_state_token(1, @client_url, nil, "#{@api_url}?token=secret")
      assert {:error, :invalid} = VCS.verify_github_state_token(token)
    end

    test "emits the old three-field token shape when no override is set" do
      for override <- [nil, "", "  "] do
        token = VCS.generate_github_state_token(1, @client_url, "ios", override)

        assert {:ok, {1, @client_url, "ios"}} =
                 Phoenix.Token.verify(TuistWeb.Endpoint, "github_state", token, max_age: 60)
      end
    end

    test "rejects tampered registration state" do
      token = VCS.generate_github_state_token(1, @client_url, nil, @api_url)
      assert {:error, _} = VCS.verify_github_state_token(token <> "tampered")
    end
  end
end
