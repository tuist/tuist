defmodule TuistWeb.API.AccountTokensControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "POST /accounts/:account_handle/tokens" do
    test "returns new account token for the given user", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.account == user.account
      assert token.scopes == ["project:cache:read"]
      assert token.name == "my-token"
    end

    test "returns new account token for the given organization", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(creator: user, preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{organization.account.name}/tokens", %{
          scopes: ["account:registry:read"],
          name: "org-token"
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.account == organization.account
      assert token.scopes == ["account:registry:read"]
    end

    test "generates token name when name is not provided", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["project:cache:read"]
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.account == user.account
      assert String.starts_with?(token.name, "token-")
      assert String.length(token.name) == 14
    end

    test "transforms legacy scope registry_read to account:registry:read", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["registry_read"],
          name: "legacy-token"
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.scopes == ["account:registry:read"]
    end

    test "returns bad_request when scopes are invalid", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["invalid:scope"],
          name: "my-token"
        })

      # Then - OpenApiSpec validates scopes against enum before reaching controller
      response = json_response(conn, :bad_request)
      assert response["message"] != nil || response["errors"] != nil
    end

    test "returns not_found when an account does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When/Then
      {404, _, response_json_string} =
        assert_error_sent :not_found, fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> post("/api/accounts/tuist/tokens", %{
            scopes: ["project:cache:read"],
            name: "my-token"
          })
        end

      assert Jason.decode!(response_json_string) == %{
               "message" => "The account tuist was not found."
             }
    end

    test "returns forbidden when a user can't create a new organization access token", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{organization.account.name}/tokens", %{
          scopes: ["project:cache:read"],
          name: "my-token"
        })

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] =~ "not authorized"
    end

    test "creates token with project restrictions when project_handles is provided", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account: user.account)

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["project:cache:read"],
          name: "restricted-token",
          project_handles: [project.name]
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:projects])
      assert token.all_projects == false
      assert length(token.projects) == 1
      assert hd(token.projects).id == project.id
    end

    test "creates token with all_projects true when project_handles is not provided", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["project:cache:read"],
          name: "all-projects-token"
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:projects])
      assert token.all_projects == true
      assert token.projects == []
    end
  end

  describe "GET /accounts/:account_handle/tokens" do
    test "returns list of tokens for the account", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = AccountsFixtures.account_token_fixture(account: user.account, name: "test-token")

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, "/api/accounts/#{user.account.name}/tokens")

      # Then
      response = json_response(conn, :ok)
      assert length(response["tokens"]) == 1
      assert hd(response["tokens"])["id"] == token.id
      assert hd(response["tokens"])["name"] == "test-token"
    end

    test "returns forbidden when user is not authorized", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, "/api/accounts/#{organization.account.name}/tokens")

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] =~ "not authorized"
    end
  end

  describe "DELETE /accounts/:account_handle/tokens/:token_name" do
    test "revokes token by name", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      AccountsFixtures.account_token_fixture(account: user.account, name: "token-to-delete")

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn = delete(conn, "/api/accounts/#{user.account.name}/tokens/token-to-delete")

      # Then
      assert response(conn, :no_content)
      assert {:error, :not_found} == Accounts.get_account_token_by_name(user.account, "token-to-delete")
    end

    test "returns not_found when token does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn = delete(conn, "/api/accounts/#{user.account.name}/tokens/non-existent")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end

    test "returns forbidden when user is not authorized", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(preload: [:account])
      AccountsFixtures.account_token_fixture(account: organization.account, name: "org-token")

      conn = TuistWeb.Authentication.put_current_user(conn, user)

      # When
      conn = delete(conn, "/api/accounts/#{organization.account.name}/tokens/org-token")

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] =~ "not authorized"
    end
  end
end
