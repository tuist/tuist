defmodule TuistWeb.API.InvitationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")
    %{user: user}
  end

  describe "DELETE /api/organizations/:organization_name/invitations/:invitation_id" do
    test "deletes an invitation", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      Accounts.get_account_from_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      Accounts.invite_user_to_organization("new@tuist.io", %{
        inviter: user,
        to: organization,
        url: &url(~p"/auth/invitations/#{&1}")
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/api/organizations/tuist-org/invitations", invitee_email: "new@tuist.io")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end

    test "returns :not_found when an organization that should be invited is not found", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/api/organizations/non-existent-tuist-org/invitations",
          invitee_email: "new@tuist.io"
        )

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The invitation with the given invitee email and organization name was not found"
    end

    test "returns :not_found when an invitation with the given invitee email is not found", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/api/organizations/tuist-org/invitations",
          invitee_email: "new@tuist.io"
        )

      # Then
      response = json_response(conn, :not_found)

      assert response["message"] ==
               "The invitation with the given invitee email and organization name was not found"
    end

    test "returns :forbidden when a user is not authorized to cancel an invitation", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      Accounts.invite_user_to_organization("new@tuist.io", %{
        inviter: user,
        to: organization,
        url: &url(~p"/auth/invitations/#{&1}")
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/api/organizations/tuist-org/invitations",
          invitee_email: "new@tuist.io"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end
  end

  describe "POST /api/organizations/:organization_name/invitations" do
    test "invites user to an organization", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      user_account = Accounts.get_account_from_user(user)
      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations/tuist-org/invitations", invitee_email: "new@tuist.io")

      # Then
      response = json_response(conn, :ok)
      assert response["invitee_email"] == "new@tuist.io"

      assert response["inviter"] == %{
               "id" => user.id,
               "email" => user.email,
               "name" => user_account.name
             }

      assert response["organization_id"] == organization.id
    end

    test "returns an error if the invitee email is not a valid email address", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations/tuist-org/invitations", invitee_email: "invalid")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "The invitee email address is not a valid email address."
    end

    test "returns :bad_request when a user was already invited to an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      Accounts.invite_user_to_organization("new@tuist.io", %{
        inviter: user,
        to: organization,
        url: &url(~p"/auth/invitations/#{&1}")
      })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations/tuist-org/invitations", invitee_email: "new@tuist.io")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "The user is already invited to the organization."
    end

    test "returns :bad_request when a user is already a member of an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      invitee = AccountsFixtures.user_fixture(email: "new@tuist.io")
      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      Accounts.add_user_to_organization(invitee, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations/tuist-org/invitations", invitee_email: "new@tuist.io")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "The user is already a member of the organization."
    end

    test "returns :forbidden when a user is not authorized to invite new users", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations/tuist-org/invitations", invitee_email: "new@tuist.io")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end
  end

  test "returns :not_found when an organization that should be invited is not found", %{
    conn: conn,
    user: user
  } do
    # Given
    conn = Authentication.put_current_user(conn, user)

    # When
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/organizations/non-existent-tuist-org/invitations",
        invitee_email: "new@tuist.io"
      )

    # Given
    response = json_response(conn, :not_found)
    assert response["message"] == "Organization non-existent-tuist-org was not found."
  end
end
