defmodule TuistWeb.UserConfirmationLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
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
  end
end
