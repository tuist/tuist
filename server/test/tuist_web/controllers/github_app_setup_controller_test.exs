defmodule TuistWeb.GitHubAppSetupControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/github/setup" do
    test "redirects to integrations page when setup is successful and creates a github.com row that defers to env-var credentials",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      installation_id = "12345"
      state_token = "valid_token"

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, %{account_id: account.id, client_url: "https://github.com"}}
      end)

      expect(Accounts, :get_account_by_id, fn account_id ->
        assert account_id == account.id
        {:ok, account}
      end)

      conn =
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => installation_id,
          "state" => state_token
        })

      assert redirected_to(conn) == "/#{account.name}/settings/integrations"

      # Regression guard: github.com installations must land with no
      # per-installation credentials so the runtime keeps falling back
      # to TUIST_GITHUB_APP_* env vars for JWT signing and webhook
      # HMAC verification. If any of these columns start getting set
      # for github.com we'd silently break the existing integration.
      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert installation.installation_id == installation_id
      assert installation.client_url == "https://github.com"
      assert is_nil(installation.app_id)
      assert is_nil(installation.client_id)
      assert is_nil(installation.client_secret)
      assert is_nil(installation.private_key)
      assert is_nil(installation.webhook_secret)
      refute GitHubAppInstallation.enterprise?(installation)
      refute GitHubAppInstallation.per_installation_credentials?(installation)
    end

    test "fills installation_id on the pending GHES manifest row", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      installation_id = "67890"
      state_token = "ghes_token"
      ghes_url = "https://github.example.com"

      # Pending manifest row from the App registration step. This is
      # required for the GHES setup callback to succeed — without it,
      # the resulting row would have no per-installation credentials
      # and silently fall back to the github.com env vars at API call
      # time.
      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: ghes_url,
        app_id: "999",
        app_slug: "tuist-on-ghes",
        client_id: "Iv1.x",
        client_secret: "csec",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        webhook_secret: "wh"
      )

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, %{account_id: account.id, client_url: ghes_url}}
      end)

      expect(Accounts, :get_account_by_id, fn account_id ->
        assert account_id == account.id
        {:ok, account}
      end)

      conn =
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => installation_id,
          "state" => state_token
        })

      assert redirected_to(conn) == "/#{account.name}/settings/integrations"

      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert installation.installation_id == installation_id
      assert installation.client_url == ghes_url
      # Per-installation credentials from the manifest row are
      # preserved across the setup-callback update.
      assert installation.app_id == "999"
      assert installation.private_key =~ "BEGIN RSA"
    end

    test "rejects GHES setup callback when no pending manifest row exists for the host", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      state_token = "ghes_token"
      ghes_url = "https://github.example.com"

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, %{account_id: account.id, client_url: ghes_url}}
      end)

      expect(Accounts, :get_account_by_id, fn _account_id -> {:ok, account} end)

      assert_raise BadRequestError, ~r/registration flow first/, fn ->
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => "67890",
          "state" => state_token
        })
      end

      assert {:error, :not_found} = VCS.get_github_app_installation_for_account(account.id)
    end

    test "rejects GHES setup callback when the only pending row is for a different host", %{conn: conn} do
      # Defense-in-depth: if a setup callback for ghes-a.example.com
      # arrives but the only pending row is for ghes-b.example.com,
      # silently retargeting the row would leave it with credentials
      # that work against the wrong host. Refuse instead.
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      state_token = "ghes_token"
      target_ghes = "https://ghes-a.example.com"

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: nil,
        client_url: "https://ghes-b.example.com",
        app_id: "999",
        app_slug: "tuist-on-ghes-b",
        client_id: "Iv1.b",
        client_secret: "csec-b",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake-b\n-----END RSA PRIVATE KEY-----",
        webhook_secret: "wh-b"
      )

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, %{account_id: account.id, client_url: target_ghes}}
      end)

      expect(Accounts, :get_account_by_id, fn _account_id -> {:ok, account} end)

      assert_raise BadRequestError, ~r/registration flow first/, fn ->
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => "67890",
          "state" => state_token
        })
      end

      # The original ghes-b row stays untouched — installation_id NOT
      # overwritten.
      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert is_nil(installation.installation_id)
      assert installation.client_url == "https://ghes-b.example.com"
    end

    test "returns BadRequestError when installation is already connected to a different account", %{conn: conn} do
      connected_account = AccountsFixtures.account_fixture()
      selected_account = AccountsFixtures.account_fixture()
      installation_id = "12345"
      state_token = "valid_token"

      VCSFixtures.github_app_installation_fixture(
        account_id: connected_account.id,
        installation_id: installation_id
      )

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, %{account_id: selected_account.id, client_url: "https://github.com"}}
      end)

      expect(Accounts, :get_account_by_id, fn account_id ->
        assert account_id == selected_account.id
        {:ok, selected_account}
      end)

      assert_raise BadRequestError, "This GitHub app installation is already connected.", fn ->
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => installation_id,
          "state" => state_token
        })
      end
    end

    test "raises BadRequestError when installation_id is missing", %{conn: conn} do
      state_token = "valid_token"

      assert_raise BadRequestError, "Invalid GitHub app installation. Please try again.", fn ->
        get(conn, ~p"/integrations/github/setup", %{"state" => state_token})
      end
    end

    test "raises BadRequestError when state token is missing", %{conn: conn} do
      installation_id = "12345"

      assert_raise BadRequestError, "Invalid GitHub app installation. Please try again.", fn ->
        get(conn, ~p"/integrations/github/setup", %{"installation_id" => installation_id})
      end
    end

    test "raises BadRequestError when state token is invalid", %{conn: conn} do
      installation_id = "12345"
      invalid_token = "invalid_token"

      expect(VCS, :verify_github_state_token, fn ^invalid_token ->
        {:error, :invalid}
      end)

      assert_raise BadRequestError, "Invalid installation request. Please try again.", fn ->
        get(conn, ~p"/integrations/github/setup", %{
          "installation_id" => installation_id,
          "state" => invalid_token
        })
      end
    end
  end
end
