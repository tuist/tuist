defmodule TuistWeb.GitHubAppSetupControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/github/setup" do
    test "redirects to integrations page when setup is successful", %{conn: conn} do
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

      assert redirected_to(conn) == "/#{account.name}/integrations"
    end

    test "stores the GitHub Enterprise client_url from the state token", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      installation_id = "67890"
      state_token = "ghes_token"
      ghes_url = "https://github.example.com"

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

      assert redirected_to(conn) == "/#{account.name}/integrations"

      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert installation.installation_id == installation_id
      assert installation.client_url == ghes_url
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
