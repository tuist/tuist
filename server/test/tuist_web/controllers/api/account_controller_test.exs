defmodule TuistWeb.API.AccountControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Repo

  describe "PATCH /api/accounts" do
    setup [:register_and_log_in_user]

    test "successfully updates handle when valid (explicit user handle)", %{
      conn: conn,
      user: user
    } do
      user = Repo.preload(user, :account)
      new_handle = "test#{System.unique_integer()}"

      response =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/accounts/#{user.account.name}", %{handle: new_handle})
        |> json_response(:ok)

      assert response == %{"id" => user.account.id, "handle" => new_handle}

      assert (user |> Repo.reload() |> Repo.preload(:account) |> Map.get(:account)).name ==
               String.downcase(new_handle)
    end

    test "successfully updates handle when valid (explicit organization handle)", %{
      conn: conn,
      user: user
    } do
      organization = organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)
      new_handle = "test#{System.unique_integer()}"

      response =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/accounts/#{organization.account.name}", %{handle: new_handle})
        |> json_response(:ok)

      assert response == %{"id" => organization.account.id, "handle" => new_handle}

      assert (organization |> Repo.reload() |> Repo.preload(:account) |> Map.get(:account)).name ==
               String.downcase(new_handle)
    end

    test "checks authorization of the user (explicit user handle)", %{
      conn: conn,
      user: user
    } do
      other_user = Repo.preload(user_fixture(), :account)
      new_handle = "test#{System.unique_integer()}"

      conn
      |> assign(:current_user, user)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/accounts/#{other_user.account.name}", %{handle: new_handle})
      |> json_response(:forbidden)
    end

    test "checks authorization of the user (explicit organization handle)", %{
      conn: conn,
      user: user
    } do
      organization = organization_fixture()
      new_handle = "test#{System.unique_integer()}"

      conn
      |> assign(:current_user, user)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/accounts/#{organization.account.name}", %{handle: new_handle})
      |> json_response(:forbidden)
    end

    test "returns error when handle is invalid", %{conn: conn, user: user} do
      user = Repo.preload(user, :account)
      invalid_handle = "test.#{System.unique_integer()}"

      response =
        conn
        |> assign(:current_user, user)
        |> put_req_header("content-type", "application/json")
        |> patch("/api/accounts/#{user.account.name}", %{handle: invalid_handle})
        |> json_response(:bad_request)

      assert response == %{
               "fields" => %{"name" => ["must contain only alphanumeric characters"]},
               "message" => "There was an error handling your request."
             }
    end
  end

  describe "DELETE /api/accounts/:account_handle" do
    setup [:register_and_log_in_user]

    test "deletes a user account", %{conn: conn, user: user} do
      # Given
      user = Repo.preload(user, :account)

      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/#{user.account.name}")
        |> json_response(:no_content)

      # Then
      assert response == %{}
      assert Accounts.get_user_by_id(user.id) == nil
    end

    test "deletes an organization account", %{conn: conn, user: user} do
      # Given
      organization = organization_fixture(creator: user)

      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/#{organization.account.name}")
        |> json_response(:no_content)

      # Then
      assert response == %{}
      assert Accounts.get_organization_by_id(organization.id) == {:error, :not_found}
    end

    test "returns not found when account does not exist", %{conn: conn, user: user} do
      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/non-existent-account")
        |> json_response(:not_found)

      # Then
      assert response["message"] == "Account non-existent-account not found."
    end

    test "returns forbidden when user is not authorized to delete user account", %{conn: conn, user: user} do
      # Given
      other_user = Repo.preload(user_fixture(), :account)

      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/#{other_user.account.name}")
        |> json_response(:forbidden)

      # Then
      assert response["message"] == "The authenticated subject is not authorized to perform this action"
    end

    test "returns forbidden when user is not authorized to delete organization account", %{conn: conn, user: user} do
      # Given
      organization = organization_fixture()

      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/#{organization.account.name}")
        |> json_response(:forbidden)

      # Then
      assert response["message"] == "The authenticated subject is not authorized to perform this action"
    end

    test "user can delete organization account when they are admin", %{conn: conn, user: user} do
      # Given
      organization = organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)

      # When
      response =
        conn
        |> assign(:current_user, user)
        |> delete("/api/accounts/#{organization.account.name}")
        |> json_response(:no_content)

      # Then
      assert response == %{}
      assert Accounts.get_organization_by_id(organization.id) == {:error, :not_found}
    end
  end
end
