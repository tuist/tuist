defmodule TuistCloudWeb.OrganizationsControllerTest do
  alias TuistCloud.Environment
  alias TuistCloudWeb.Authentication
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")
    %{user: user}
  end

  describe "GET /api/organizations" do
    test "returns organizations", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization_one = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization_one)

      AccountsFixtures.organization_fixture(name: "tuist-org-2")

      organization_three = AccountsFixtures.organization_fixture(name: "tuist-org-3")
      Accounts.add_user_to_organization(user, organization_three, role: :admin)

      # When
      conn =
        conn
        |> get(~p"/api/organizations")

      # Then
      response = json_response(conn, :ok)

      assert [
               %{
                 "id" => organization_one.id,
                 "invitations" => [],
                 "members" => [],
                 "name" => "tuist-org",
                 "plan" => nil
               },
               %{
                 "id" => organization_three.id,
                 "invitations" => [],
                 "members" => [],
                 "name" => "tuist-org-3",
                 "plan" => nil
               }
             ] == Enum.sort_by(response["organizations"], & &1["name"])
    end

    test "returns empty list when user does not belong to any organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(~p"/api/organizations")

      # Then
      %{"organizations" => []} = json_response(conn, :ok)
    end
  end

  describe "GET /api/organizations/{id}" do
    setup do
      Environment
      |> stub(:smtp_configured?, fn -> false end)

      :ok
    end

    test "returns an organization", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      Accounts.invite_user_to_organization("tuist-inviter@tuist.io", %{
        inviter: user,
        to: organization,
        url: fn token -> token end
      })

      # When
      conn =
        conn
        |> get(~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get(~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Organization not found"
    end

    test "returns :fobidden when user is not authorized to read an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn =
        conn
        |> get(~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end
  end

  describe "DELETE /api/organizations/{id}" do
    test "deletes a given organization", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
      assert Accounts.get_organization_by_id(organization.id) == nil
    end

    test "returns :forbidden when a user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end

    test "returns :not_found if an organization does not exist", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/non-existent-tuist-org")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org not found."
    end
  end

  describe "POST /api/organizations" do
    test "creates an organization", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: "tuist-org")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
    end

    test "returns bad request when organization already exists", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: "tuist-org")

      # Then
      response = json_response(conn, :bad_request)
      assert response["message"] == "Organization tuist-org already exists"
    end

    test "returns bad request when organization contains a dot", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: "tuist.org")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "Organization name can't contain a dot. Please use a different name, such as tuist-org."
    end
  end

  describe "DELETE /api/organizations/:organization_name/members/:user_name" do
    test "removes a member from an organization", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      conn =
        conn
        |> Authentication.put_current_user(user)

      conn =
        conn
        |> delete(~p"/api/organizations/non-existent-tuist-org/members/tuist-member")

      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org not found."
    end

    test "returns :bad_request when a user does not belong to the organization", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> Authentication.put_current_user(user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")

      # When
      conn =
        conn
        |> delete(~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "User tuist-member is not a member of the organization tuist-org"
    end
  end

  describe "PUT /api/organizations/{organization_name}/members/{user_name}" do
    test "updates a member to an admin role", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org/members/tuist-member", role: "admin")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-member"
      assert response["role"] == "admin"
      assert Accounts.admin?(member, organization)
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org/members/tuist-member", role: "admin")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      conn =
        conn
        |> Authentication.put_current_user(user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/non-existent-tuist-org/members/tuist-member", role: "admin")

      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org not found."
    end

    test "returns :bad_request when a user does not belong to the organization", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> Authentication.put_current_user(user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org/members/tuist-member", role: "admin")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "User tuist-member is not a member of the organization tuist-org"
    end
  end
end
