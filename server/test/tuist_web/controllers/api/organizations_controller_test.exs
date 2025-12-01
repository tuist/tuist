defmodule TuistWeb.API.OrganizationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])
    %{user: user}
  end

  describe "GET /api/organizations" do
    test "returns organizations", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization_one = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization_one)

      AccountsFixtures.organization_fixture(name: "tuist-org-2")

      organization_three = AccountsFixtures.organization_fixture(name: "tuist-org-3")
      Accounts.add_user_to_organization(user, organization_three, role: :admin)

      # When
      conn = get(conn, ~p"/api/organizations")

      # Then
      response = json_response(conn, :ok)

      assert [
               %{
                 "id" => organization_one.id,
                 "invitations" => [],
                 "members" => [],
                 "name" => "tuist-org",
                 "plan" => "none"
               },
               %{
                 "id" => organization_three.id,
                 "invitations" => [],
                 "members" => [],
                 "name" => "tuist-org-3",
                 "plan" => "none"
               }
             ] == Enum.sort_by(response["organizations"], & &1["name"])
    end

    test "returns empty list when user does not belong to any organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/organizations")

      # Then
      %{"organizations" => []} = json_response(conn, :ok)
    end
  end

  describe "GET /api/organizations/{id}" do
    setup do
      stub(Environment, :mail_configured?, fn -> false end)
      :ok
    end

    test "returns an organization", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      Accounts.invite_user_to_organization("tuist-inviter@tuist.io", %{
        inviter: user,
        to: organization,
        url: fn token -> token end
      })

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
      assert response["plan"] == "none"
    end

    test "returns an organization with an active pro plan", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      Accounts.invite_user_to_organization("tuist-inviter@tuist.io", %{
        inviter: user,
        to: organization,
        url: fn token -> token end
      })

      BillingFixtures.subscription_fixture(
        account_id: organization.account.id,
        plan: :pro,
        status: "active"
      )

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
      assert response["plan"] == "pro"
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Organization not found"
    end

    test "returns :fobidden when user is not authorized to read an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end
  end

  describe "GET /api/organizations/{id}/usage" do
    setup do
      stub(Environment, :mail_configured?, fn -> false end)
      :ok
    end

    test "returns an organization usage", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization =
        AccountsFixtures.organization_fixture(
          name: "tuist-org",
          current_month_remote_cache_hits_count: 1
        )

      Accounts.add_user_to_organization(user, organization)

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org/usage")

      # Then
      response = json_response(conn, :ok)
      assert response["current_month_remote_cache_hits"] == 1
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org/usage")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Organization not found"
    end

    test "returns :fobidden when user is not authorized to read an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn = get(conn, ~p"/api/organizations/tuist-org/usage")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end
  end

  describe "DELETE /api/organizations/{id}" do
    test "deletes a given organization", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
      assert Accounts.get_organization_by_id(organization.id) == {:error, :not_found}
    end

    test "returns :forbidden when a user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end

    test "returns :not_found if an organization does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = delete(conn, ~p"/api/organizations/non-existent-tuist-org")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org not found."
    end
  end

  describe "POST /api/organizations" do
    test "creates an organization", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: "tuist-org")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "A user or organization with the handle tuist-org already exists"
    end

    test "returns bad request when a user with the same handle already exists", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: user.account.name)

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "A user or organization with the handle tuist already exists"
    end

    test "returns bad request when organization contains a dot", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

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

    test "returns bad request when organization contains a space", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/organizations", name: "tuist org")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "Organization must contain only alphanumeric characters"
    end
  end

  describe "PUT /api/organizations/:organization_name" do
    test "updates an organization with SSO settings when user's google hosted domain is equal to the new value",
         %{conn: conn} do
      # Given
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org",
          sso_provider: "google",
          sso_organization_id: "tuist.io"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
      assert response["sso_provider"] == "google"
      assert response["sso_organization_id"] == "tuist.io"
    end

    test "updates SSO to nil",
         %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      )

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org",
          sso_provider: "none"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-org"
      assert response["sso_provider"] == nil
      assert response["sso_organization_id"] == nil
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org",
          sso_provider: "google",
          sso_organization_id: "tuist.io"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action."
    end

    test "returns :bad_request when organization with a given google hosted domain already exists",
         %{
           conn: conn
         } do
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(
        creator: user,
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      )

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org",
          sso_provider: "google",
          sso_organization_id: "tuist.io"
        )

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID."
    end

    test "returns :bad_request when user's google hosted domain is not equal to the new value", %{
      conn: conn
    } do
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org",
          sso_provider: "google",
          sso_organization_id: "tools.io"
        )

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "Your SSO organization must be the same as the one you are trying to update your organization to."
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/non-existent-tuist-org",
          sso_provider: "google",
          sso_organization_id: "tuist.io"
        )

      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org was not found."
    end
  end

  describe "DELETE /api/organizations/:organization_name/members/:user_name" do
    test "removes a member from an organization", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end

    test "removes a member with a google hosted domain", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      )

      member =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist-member@tuist.io"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
      assert Accounts.get_user_by_id(member.id) == nil
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)
      member = AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")
      Accounts.add_user_to_organization(member, organization)

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action"
    end

    test "returns :not_found when organization does not exist", %{conn: conn, user: user} do
      conn = Authentication.put_current_user(conn, user)

      conn = delete(conn, ~p"/api/organizations/non-existent-tuist-org/members/tuist-member")

      response = json_response(conn, :not_found)
      assert response["message"] == "Organization non-existent-tuist-org not found."
    end

    test "returns :bad_request when a user does not belong to the organization", %{
      conn: conn,
      user: user
    } do
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
      AccountsFixtures.user_fixture(email: "tuist-member@tuist.io")

      # When
      conn = delete(conn, ~p"/api/organizations/tuist-org/members/tuist-member")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] ==
               "User tuist-member is not a member of the organization tuist-org"
    end
  end

  describe "PUT /api/organizations/{organization_name}/members/{user_name}" do
    test "updates a member to an admin role", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
      assert Accounts.organization_admin?(member, organization)
    end

    test "updates a member that's a user through google hosted domain to an admin role", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization =
        AccountsFixtures.organization_fixture(
          name: "tuist-org",
          creator: user,
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        )

      member =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist-member@tuist.io"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/organizations/tuist-org/members/tuist-member", role: "admin")

      # Then
      response = json_response(conn, :ok)
      assert response["name"] == "tuist-member"
      assert response["role"] == "admin"
      assert Accounts.organization_admin?(Accounts.get_user!(member.id), organization) == true
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

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
