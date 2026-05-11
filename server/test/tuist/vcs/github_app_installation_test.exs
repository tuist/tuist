defmodule Tuist.VCS.GitHubAppInstallationTest do
  use ExUnit.Case, async: true

  alias Tuist.VCS.GitHubAppInstallation

  describe "enterprise?/1" do
    test "false for the default github.com client_url" do
      refute GitHubAppInstallation.enterprise?(%GitHubAppInstallation{client_url: "https://github.com"})
    end

    test "true for any non-default client_url" do
      assert GitHubAppInstallation.enterprise?(%GitHubAppInstallation{client_url: "https://github.example.com"})
    end

    test "false when the struct is not an installation" do
      refute GitHubAppInstallation.enterprise?(nil)
      refute GitHubAppInstallation.enterprise?(%{})
    end
  end

  describe "per_installation_credentials?/1" do
    test "true when app_id and private_key are both populated" do
      installation = %GitHubAppInstallation{
        app_id: "42",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----"
      }

      assert GitHubAppInstallation.per_installation_credentials?(installation)
    end

    test "false when app_id is missing" do
      installation = %GitHubAppInstallation{private_key: "pem"}
      refute GitHubAppInstallation.per_installation_credentials?(installation)
    end

    test "false when private_key is missing" do
      installation = %GitHubAppInstallation{app_id: "42"}
      refute GitHubAppInstallation.per_installation_credentials?(installation)
    end

    test "false when both are nil (github.com installation that falls back to env vars)" do
      installation = %GitHubAppInstallation{
        client_url: "https://github.com",
        installation_id: "12345"
      }

      refute GitHubAppInstallation.per_installation_credentials?(installation)
    end

    test "false when the struct is not an installation" do
      refute GitHubAppInstallation.per_installation_credentials?(nil)
      refute GitHubAppInstallation.per_installation_credentials?(%{})
    end
  end
end
