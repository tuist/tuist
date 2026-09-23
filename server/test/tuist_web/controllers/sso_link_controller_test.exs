defmodule TuistWeb.SSOLinkControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @provider_organization_id "https://login.vendor.example"

  setup do
    user = AccountsFixtures.user_fixture(email: "personal@mail.example")
    organization_name = "customer-#{TuistTestSupport.Utilities.unique_integer()}"

    organization =
      AccountsFixtures.organization_fixture(
        name: organization_name,
        creator: user,
        sso_provider: :oauth2,
        sso_organization_id: @provider_organization_id,
        oauth2_client_id: UUIDv7.generate(),
        oauth2_client_secret: UUIDv7.generate(),
        oauth2_authorize_url: "https://login.vendor.example/authorize",
        oauth2_token_url: "https://login.vendor.example/token",
        oauth2_user_info_url: "https://login.vendor.example/userinfo"
      )

    %{user: user, organization: organization, organization_name: organization_name}
  end

  describe "GET /auth/sso/link" do
    test "shows the identity the signed-in user is about to link", %{
      conn: conn,
      user: user,
      organization: organization,
      organization_name: organization_name
    } do
      conn =
        conn
        |> with_pending_link(user, organization)
        |> get(~p"/auth/sso/link")

      html = html_response(conn, 200)
      assert html =~ "Link single sign-on?"
      assert html =~ "person@customer.example"
      assert html =~ user.email
      assert html =~ organization_name
    end

    test "refuses a pending link stored for another user", %{conn: conn, user: user, organization: organization} do
      other_user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> log_in_user(other_user)
        |> put_session(:pending_sso_link, pending_link(user, organization))
        |> get(~p"/auth/sso/link")

      assert html_response(conn, 410) =~ "Link expired"
      refute get_session(conn, :pending_sso_link)
    end

    test "refuses a pending link older than ten minutes", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> with_pending_link(user, organization, %{"issued_at" => System.system_time(:second) - 601})
        |> get(~p"/auth/sso/link")

      assert html_response(conn, 410) =~ "Link expired"
    end

    test "sends a signed-out visitor to log in", %{conn: conn} do
      conn = get(conn, ~p"/auth/sso/link")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /auth/sso/link" do
    test "links the identity and signs in through the provider", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      conn =
        conn
        |> with_pending_link(user, organization, %{"return_to" => "/some-project"})
        |> post(~p"/auth/sso/link")

      assert redirected_to(conn) == "/some-project"
      assert get_session(conn, :auth_method) == :oauth2
      refute get_session(conn, :pending_sso_link)

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", @provider_organization_id)

      assert identity.user_id == user.id
    end

    test "continues to the invitation when the user was invited rather than a member", %{
      conn: conn,
      user: admin,
      organization: organization
    } do
      invitee = AccountsFixtures.user_fixture(email: "invitee@mail.example")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: admin, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn =
        conn
        |> with_pending_link(invitee, organization, %{"return_to" => "/oauth2/authorize?client_id=cli"})
        |> post(~p"/auth/sso/link")

      assert redirected_to(conn) == "/auth/invitations/#{invitation.token}"
      assert get_session(conn, :post_invitation_return_to) == "/oauth2/authorize?client_id=cli"
      assert get_session(conn, :post_invitation_user_id) == invitee.id
      assert get_session(conn, :post_invitation_token) == invitation.token

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", @provider_organization_id)

      assert identity.user_id == invitee.id
    end

    test "refuses the link once the organization points at another provider", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(sso_organization_id: "https://other-login.vendor.example")
      |> Tuist.Repo.update!()

      conn =
        conn
        |> with_pending_link(user, organization)
        |> post(~p"/auth/sso/link")

      assert html_response(conn, 410) =~ "Link expired"

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", @provider_organization_id)
    end

    test "refuses an identity that is already linked to another account", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      owner = AccountsFixtures.user_fixture()

      {:ok, _identity} =
        Accounts.link_oauth_identity_to_user(owner, %{
          provider: :oauth2,
          id_in_provider: "work-identity",
          provider_organization_id: @provider_organization_id
        })

      conn =
        conn
        |> with_pending_link(user, organization)
        |> post(~p"/auth/sso/link")

      assert html_response(conn, 409) =~ "already linked to another Tuist account"

      assert {:ok, identity} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", @provider_organization_id)

      assert identity.user_id == owner.id
    end
  end

  describe "DELETE /auth/sso/link" do
    test "discards the pending link without linking", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> with_pending_link(user, organization)
        |> delete(~p"/auth/sso/link")

      assert redirected_to(conn) == TuistWeb.Authentication.signed_in_path(user)
      refute get_session(conn, :pending_sso_link)

      assert {:error, :not_found} =
               Accounts.get_oauth2_identity(:oauth2, "work-identity", @provider_organization_id)
    end
  end

  defp with_pending_link(conn, user, organization, overrides \\ %{}) do
    conn
    |> log_in_user(user)
    |> put_session(:pending_sso_link, Map.merge(pending_link(user, organization), overrides))
  end

  defp pending_link(user, organization) do
    %{
      "user_id" => user.id,
      "organization_id" => organization.id,
      "provider" => "oauth2",
      "uid" => "work-identity",
      "provider_organization_id" => @provider_organization_id,
      "email" => "person@customer.example",
      "return_to" => nil,
      "issued_at" => System.system_time(:second)
    }
  end
end
