defmodule TuistWeb.UserResetPasswordLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken

  setup do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(%{
          user: user,
          reset_password_url: url
        })
      end)

    %{token: token, user: user}
  end

  describe "Reset password page" do
    test "renders reset password with valid token", %{conn: conn, token: token} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset_password/#{token}")

      assert html =~ "New password"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      {:error, {:redirect, to}} = live(conn, ~p"/users/reset_password/invalid")

      assert to == %{
               flash: %{"error" => "Reset password link is invalid or it has expired."},
               to: ~p"/users/log_in"
             }
    end

    test "disconnects all active sessions after resetting the password", %{conn: conn, token: token, user: user} do
      live_socket_ids =
        user
        |> active_session_tokens()
        |> Enum.map(&UserToken.live_socket_id/1)

      Enum.each(live_socket_ids, &TuistWeb.Endpoint.subscribe/1)

      {:ok, lv, _html} = live(conn, ~p"/users/reset_password/#{token}")

      lv
      |> form("#reset_password_form", %{
        "user" => %{
          "password" => "new valid password",
          "password_confirmation" => "new valid password"
        }
      })
      |> render_submit()

      Enum.each(live_socket_ids, fn live_socket_id ->
        assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
      end)
    end
  end

  defp active_session_tokens(user) do
    [
      Accounts.generate_user_session_token(user),
      Accounts.generate_user_session_token(user)
    ]
  end
end
