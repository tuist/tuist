defmodule TuistWeb.UserResetPasswordLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo

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

    test "reset links last fifteen minutes, not one day", %{conn: conn, token: token, user: user} do
      age_reset(user, 14 * 60)
      assert {:ok, _, _} = live(conn, ~p"/users/reset_password/#{token}")
      age_reset(user, 15 * 60)
      assert {:error, {:redirect, _}} = live(conn, ~p"/users/reset_password/#{token}")
    end

    for reason <- [:expired, :replaced, :used] do
      test "rejects an already-open #{reason} reset form", %{conn: conn, token: token, user: user} do
        {:ok, stale, _} = live(conn, ~p"/users/reset_password/#{token}")

        case unquote(reason) do
          :expired ->
            age_reset(user, 15 * 60)

          :replaced ->
            age_reset(user, 6 * 60)

            extract_user_token(fn url ->
              Accounts.deliver_user_reset_password_instructions(%{user: user, reset_password_url: url})
            end)

          :used ->
            {:ok, first, _} = live(conn, ~p"/users/reset_password/#{token}")
            submit_password(first, "first replacement password")
        end

        submit_password(stale, "stale replacement password")
        assert_redirect(stale, "/users/log_in")

        assert {:error, :invalid_email_or_password} =
                 Accounts.get_user_by_email_and_password(user.email, "stale replacement password")
      end
    end

    test "redirects to log in when email auth is disabled", %{conn: conn, token: token} do
      stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/reset_password/#{token}")
      assert to == ~p"/users/log_in"
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

  describe "API credentials" do
    setup do
      stub(TuistWeb.RateLimit.Auth, :hit, fn _ -> {:allow, 1} end)
      :ok
    end

    test "resetting the password revokes the user's refresh tokens and legacy token", %{token: token, user: user} do
      %{"access_token" => access_token, "refresh_token" => refresh_token} =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: valid_user_password()})
        |> json_response(:ok)

      assert Tuist.Authentication.authenticated_subject(user.token).id == user.id

      # Account tokens share `guardian_tokens`, with `sub` holding an account
      # ID that can equal the user's ID. They are not the user's credentials.
      account = user_fixture().account

      {:ok, account_refresh_token, %{"jti" => account_jti}} =
        Tuist.Guardian.encode_and_sign(account, %{"type" => "account", "scopes" => ["ci"]}, token_type: "refresh")

      Repo.update_all(from(t in "guardian_tokens", where: t.jti == ^account_jti), set: [sub: to_string(user.id)])

      other = user_fixture()
      {:ok, other_refresh_token, _} = Tuist.Authentication.encode_and_sign(other, %{}, token_type: :refresh)

      {:ok, lv, _} = live(build_conn(), ~p"/users/reset_password/#{token}")
      submit_password(lv, "new valid password")

      assert api_refresh(refresh_token).status == 401
      refute Tuist.Authentication.authenticated_subject(access_token)
      refute Tuist.Authentication.authenticated_subject(user.token)
      assert {:ok, _, _} = Tuist.Guardian.resource_from_token(account_refresh_token, %{"typ" => "refresh"})
      assert api_refresh(other_refresh_token).status == 200
      assert Tuist.Authentication.authenticated_subject(other.token).id == other.id
    end
  end

  defp api_refresh(refresh_token) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})
  end

  defp active_session_tokens(user) do
    [
      Accounts.generate_user_session_token(user),
      Accounts.generate_user_session_token(user)
    ]
  end

  defp age_reset(user, seconds) do
    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
      set: [inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-seconds) |> NaiveDateTime.truncate(:second)]
    )
  end

  defp submit_password(view, password) do
    view
    |> form("#reset_password_form", user: %{password: password, password_confirmation: password})
    |> render_submit()
  end
end
