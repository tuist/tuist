defmodule Tuist.Registry.GitHubTokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.Registry

  setup :set_mimic_from_context
  setup :verify_on_exit!

  describe "github_token/2" do
    test "uses the personal access token when no App installation is configured" do
      reject(&App.get_installation_token/1)

      assert Registry.github_token(nil, "pat") == "pat"
    end

    test "mints an installation token when an App installation is configured" do
      expect(App, :get_installation_token, fn "12345" ->
        {:ok, %{token: "installation-token", expires_at: DateTime.utc_now()}}
      end)

      assert Registry.github_token("12345", "pat") == "installation-token"
    end

    test "falls back to the personal access token when the App cannot issue one" do
      expect(App, :get_installation_token, fn "12345" -> {:error, "GitHub App is not configured"} end)

      assert Registry.github_token("12345", "pat") == "pat"
    end

    test "reports no token when the App fails and there is no personal access token to fall back to" do
      expect(App, :get_installation_token, fn "12345" -> {:error, :unavailable} end)

      assert Registry.github_token("12345", nil) == nil
    end
  end

  describe "github_credentials_configured?/2" do
    test "reads an App installation alone as configured, without minting a token" do
      reject(&App.get_installation_token/1)

      assert Registry.github_credentials_configured?("12345", nil)
    end

    test "reads a personal access token alone as configured" do
      assert Registry.github_credentials_configured?(nil, "pat")
    end

    test "reads no credential at all as unconfigured" do
      refute Registry.github_credentials_configured?(nil, nil)
    end
  end
end
