defmodule Tuist.VCS.GitHubAppInstallationTest do
  use ExUnit.Case, async: true

  alias Tuist.VCS.GitHubAppInstallation

  describe "changeset/2 API URL" do
    @attrs %{account_id: 1, client_url: "https://github.internal.example.com", private_key: "pem"}

    test "normalizes the optional API URL without changing the browser URL" do
      changeset =
        GitHubAppInstallation.changeset(Map.put(@attrs, :api_url, "  https://proxy.example.com/api/v3/  "))

      assert changeset.valid?
      installation = Ecto.Changeset.apply_changes(changeset)
      assert installation.api_url == "https://proxy.example.com/api/v3"
      assert installation.client_url == @attrs.client_url
    end

    test "defaults to no API override and permits clearing it" do
      assert GitHubAppInstallation.changeset(@attrs).valid?

      for value <- [nil, "", "   "] do
        existing = %GitHubAppInstallation{api_url: "https://proxy.example.com/api/v3"}
        changeset = GitHubAppInstallation.changeset(existing, Map.put(@attrs, :api_url, value))
        assert changeset.valid?
        assert Ecto.Changeset.get_field(changeset, :api_url) == nil
      end
    end

    test "rejects malformed API URLs and embedded credentials, queries, and fragments" do
      for url <- [
            "not-a-url",
            "https://user:password@proxy.example.com/api/v3",
            "https://proxy.example.com/api/v3?token=secret",
            "https://proxy.example.com/api/v3#fragment"
          ] do
        changeset = GitHubAppInstallation.changeset(Map.put(@attrs, :api_url, url))
        refute changeset.valid?
        assert changeset.errors[:api_url]
      end
    end

    test "rejects API overrides for the shared github.com App" do
      changeset =
        GitHubAppInstallation.changeset(%{
          account_id: 1,
          client_url: "https://github.com",
          installation_id: "123",
          api_url: "https://proxy.example.com/api/v3"
        })

      refute changeset.valid?
      assert changeset.errors[:api_url]
    end

    test "installation setup updates preserve the API override" do
      existing = %GitHubAppInstallation{
        client_url: @attrs.client_url,
        api_url: "https://proxy.example.com/api/v3",
        private_key: "pem"
      }

      changeset =
        GitHubAppInstallation.update_changeset(existing, %{installation_id: "123", api_url: "https://other.com"})

      assert Ecto.Changeset.get_field(changeset, :api_url) == existing.api_url
      assert Ecto.Changeset.get_field(changeset, :installation_id) == "123"
    end
  end

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
