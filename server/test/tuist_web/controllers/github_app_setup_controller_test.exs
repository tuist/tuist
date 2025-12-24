defmodule TuistWeb.GitHubAppSetupControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/github/setup" do
    test "redirects to integrations page when setup is successful", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account
      installation_id = "12345"
      state_token = "valid_token"

      expect(VCS, :verify_github_state_token, fn ^state_token ->
        {:ok, account.id}
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
