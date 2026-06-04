defmodule TuistWeb.UserConfirmationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts

  setup do
    %{user: user_fixture(confirmed_at: nil)}
  end

  describe "Confirm user" do
    test "confirms the given token", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: url
          })
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")
      assert has_element?(lv, "h1", "Account confirmed!")
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      {:ok, lv, _html} =
        live(conn, ~p"/users/confirm/invalid-token")

      assert has_element?(lv, "h1", "Confirmation failed")
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "redirects to /organizations/new after confirming when no pending invitation exists", %{
      conn: conn,
      user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: url
          })
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")
      send(lv.pid, :redirect)

      assert_redirect(lv, ~p"/organizations/new")
    end

    test "redirects to the pending invitation when one exists for the user's email", %{conn: conn} do
      email = "invitee-#{System.unique_integer([:positive])}@example.com"
      user = user_fixture(email: email, confirmed_at: nil)
      inviter = user_fixture()
      organization = organization_fixture(creator: inviter)

      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          email,
          %{inviter: inviter, to: organization, url: fn token -> "/auth/invitations/#{token}" end}
        )

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: url
          })
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")
      send(lv.pid, :redirect)

      assert_redirect(lv, ~p"/auth/invitations/#{invitation.token}")
    end
  end
end
