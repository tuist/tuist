defmodule TuistCloudWeb.UserResetPasswordLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistCloud.AccountsFixtures

  alias TuistCloud.Accounts

  setup do
    TuistCloud.Environment
    |> stub(:secret_key_password, fn -> "secret_key_password" end)

    TuistCloud.Environment
    |> stub(:smtp_user_name, fn -> "stmp_user_name" end)

    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{token: token, user: user}
  end

  describe "Reset password page" do
    test "renders reset password with valid token", %{conn: conn, token: token} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset_password/#{token}")

      assert html =~ "Set new password"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      {:error, {:redirect, to}} = live(conn, ~p"/users/reset_password/invalid")

      assert to == %{
               flash: %{"error" => "Reset password link is invalid or it has expired."},
               to: ~p"/users/log_in"
             }
    end
  end
end
