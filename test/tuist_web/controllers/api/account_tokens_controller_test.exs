defmodule TuistWeb.API.AccountTokensControllerTest do
  use TuistWeb.ConnCase, async: true
  use Mimic
  alias Tuist.Accounts
  alias Tuist.AccountsFixtures

  describe "POST /accounts/:account_handle/tokens" do
    test "returns new account token for the given user", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        conn
        |> TuistWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{user.account.name}/tokens", %{
          scopes: ["account_registry_read"]
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.account == user.account
      assert token.scopes == [:account_registry_read]
    end

    test "returns new account token for the given organization", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      organization =
        AccountsFixtures.organization_fixture(creator: user, preload: [:account])

      conn =
        conn
        |> TuistWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{organization.account.name}/tokens", %{
          scopes: ["account_registry_read"]
        })

      # Then
      response = json_response(conn, :ok)
      {:ok, token} = Accounts.account_token(response["token"], preload: [:account])
      assert token.account == organization.account
      assert token.scopes == [:account_registry_read]
    end

    test "returns not_found when an account does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> TuistWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/tuist/tokens", %{
          scopes: ["account_registry_read"]
        })

      # Then
      response = json_response(conn, :not_found)
      assert response == %{"message" => "The account tuist was not found."}
    end

    test "returns forbidden when a user can't create a new organization access token", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(preload: [:account])

      conn =
        conn
        |> TuistWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/accounts/#{organization.account.name}/tokens", %{
          scopes: ["account_registry_read"]
        })

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "The authenticated subject is not authorized to perform this action"
             }
    end
  end
end
