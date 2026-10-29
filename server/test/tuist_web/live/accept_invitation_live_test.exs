defmodule TuistWeb.AcceptInvitationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Accounts.Invitation
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "/auth/invitations/:token" do
    test "redirects unauthenticated visitors to log in", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/auth/invitations/#{invitation.token}")
    end

    test "shows the accept form when the signed-in user matches the invitee", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "You have been invited"
      assert html =~ "Accept invitation"
      assert html =~ "Decline"
    end

    test "accepts the invitation when the user clicks Accept", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      html = lv |> element("button", "Accept invitation") |> render_click()

      assert html =~ "Invitation accepted!"
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "redirects to post_invitation_return_to after Accept when set", %{conn: conn} do
      # When SSO bounced the user here it stashed the original return target
      # (e.g. the device-code URL) under :post_invitation_return_to so we
      # can resume that flow once they accept.
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "resume-invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{
          post_invitation_return_to: device_code_url,
          post_invitation_user_id: invitee.id,
          post_invitation_token: invitation.token
        })

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert {:error, {:redirect, %{to: ^device_code_url}}} =
               lv |> element("button", "Accept invitation") |> render_click()

      assert Accounts.organization_user?(invitee, organization)
    end

    test "does not resume to the invitation page itself after Accept", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "self-return-invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      invitation_path = "/auth/invitations/#{invitation.token}"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{
          post_invitation_return_to: invitation_path,
          post_invitation_user_id: invitee.id,
          post_invitation_token: invitation.token
        })

      {:ok, lv, _html} = live(conn, invitation_path)

      html = lv |> element("button", "Accept invitation") |> render_click()

      assert html =~ "Invitation accepted!"
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "does not resume to a percent-encoded spelling of the invitation page", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "encoded-self-return@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      <<first, rest::binary>> = invitation.token
      encoded_token = "%#{Base.encode16(<<first>>)}#{rest}"
      encoded_invitation_path = "/auth/invitations/#{encoded_token}"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{
          post_invitation_return_to: encoded_invitation_path,
          post_invitation_user_id: invitee.id,
          post_invitation_token: invitation.token
        })

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      html = lv |> element("button", "Accept invitation") |> render_click()

      assert html =~ "Invitation accepted!"
      assert Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "does not resume to router-equivalent invitation paths" do
      return_path_builders = [
        fn token -> "/auth/invitations/#{token}/" end,
        fn token -> "/auth/invitations//#{token}" end
      ]

      Enum.each(Enum.with_index(return_path_builders), fn {return_path_builder, index} ->
        inviter = AccountsFixtures.user_fixture()
        organization = AccountsFixtures.organization_fixture(creator: inviter)
        invitee = AccountsFixtures.user_fixture(email: "normalized-self-return-#{index}@example.com")

        {:ok, invitation} =
          Accounts.invite_user_to_organization(
            invitee.email,
            %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
          )

        conn =
          Phoenix.ConnTest.build_conn()
          |> log_in_user(invitee)
          |> Plug.Test.init_test_session(%{
            post_invitation_return_to: return_path_builder.(invitation.token),
            post_invitation_user_id: invitee.id,
            post_invitation_token: invitation.token
          })

        {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

        html = lv |> element("button", "Accept invitation") |> render_click()

        assert html =~ "Invitation accepted!"
        assert Accounts.organization_user?(invitee, organization)
        assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
      end)
    end

    test "declines the invitation when the user clicks Decline", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      html = lv |> element("button", "Decline") |> render_click()

      assert html =~ "Invitation rejected"
      refute Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "resumes the original flow after declining an invitation", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "decline-resume@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{
          post_invitation_return_to: device_code_url,
          post_invitation_user_id: invitee.id,
          post_invitation_token: invitation.token
        })

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert {:error, {:redirect, %{to: ^device_code_url}}} =
               lv |> element("button", "Decline") |> render_click()

      refute Accounts.organization_user?(invitee, organization)
      assert {:error, :not_found} = Accounts.get_invitation_by_token(invitation.token)
    end

    test "shows a wrong-account error when the session user doesn't match the invitee", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      _invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")
      other_user = AccountsFixtures.user_fixture(email: "someone-else@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "invitee@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, other_user)
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "Wrong account"
      assert html =~ "invitee@example.com"
      refute html =~ "Accept invitation"
    end

    test "shows a not-found message when the token is invalid", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/invalid-token")

      assert html =~ "Invitation not found"
    end

    test "shows an expired message when the invitation is no longer valid", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^invitation.id),
        set: [updated_at: expired_at]
      )

      conn = log_in_user(conn, invitee)
      {:ok, _lv, html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert html =~ "Invitation expired"
      assert html =~ "Please ask the inviter to resend it"
      refute html =~ "Accept invitation"
    end

    test "resumes the original flow when the invitation expired", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "expired-resume@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^invitation.id),
        set: [updated_at: expired_at]
      )

      device_code_url = "/auth/device_codes/AOKJ-1234?type=cli"

      conn =
        conn
        |> log_in_user(invitee)
        |> Plug.Test.init_test_session(%{
          post_invitation_return_to: device_code_url,
          post_invitation_user_id: invitee.id,
          post_invitation_token: invitation.token
        })

      assert {:error, {:redirect, %{to: ^device_code_url}}} =
               live(conn, ~p"/auth/invitations/#{invitation.token}")
    end

    test "does not accept an invitation that expires after the page loads", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^invitation.id),
        set: [updated_at: expired_at]
      )

      html = lv |> element("button", "Accept invitation") |> render_click()

      assert html =~ "Invitation expired"
      refute Accounts.organization_user?(invitee, organization)
    end

    test "does not decline an invitation that was resent after the page loads", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      invitee = AccountsFixtures.user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          invitee.email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end},
          token: "old-token"
        )

      conn = log_in_user(conn, invitee)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      {:ok, _invitation} =
        Accounts.resend_invitation(
          invitation,
          %{url: fn token -> "/auth/invitations/#{token}" end},
          token: "new-token"
        )

      html = lv |> element("button", "Decline") |> render_click()

      assert html =~ "Invitation not found"
      assert {:ok, %{token: "new-token"}} = Accounts.get_invitation_by_token("new-token")
    end

    test "ignores accept_invitation pushed from a not-found state", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/invalid-token")

      # Buttons aren't rendered in the not-found state, but a crafted client
      # could still push the event. The handler must reject it server-side
      # rather than crash on `nil` assigns.
      assert render_hook(lv, "accept_invitation", %{}) =~ "Invitation not found"
      assert render_hook(lv, "decline_invitation", %{}) =~ "Invitation not found"
    end

    test "ignores accept_invitation pushed from the wrong-account state", %{conn: conn} do
      inviter = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: inviter)
      _invitee = AccountsFixtures.user_fixture(email: "real-invitee@example.com")
      other_user = AccountsFixtures.user_fixture(email: "other@example.com")

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "real-invitee@example.com",
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      conn = log_in_user(conn, other_user)
      {:ok, lv, _html} = live(conn, ~p"/auth/invitations/#{invitation.token}")

      assert render_hook(lv, "accept_invitation", %{}) =~ "Wrong account"
      assert render_hook(lv, "decline_invitation", %{}) =~ "Wrong account"

      # Neither user has been added to the org, and the invitation survives.
      refute Accounts.organization_user?(other_user, organization)
      assert {:ok, _} = Accounts.get_invitation_by_token(invitation.token)
    end
  end
end
