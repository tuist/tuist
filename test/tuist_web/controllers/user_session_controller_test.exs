defmodule TuistWeb.UserSessionControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic
  use Gettext, backend: TuistWeb.Gettext

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias TuistWeb.RateLimit.Auth

  setup context do
    if Map.get(context, :rate_limited, false) do
      Auth
      |> expect(:hit, fn _conn ->
        {:allow, 1}
      end)
      |> expect(:hit, 1, fn _conn ->
        {:deny, 1}
      end)
    else
      stub(Auth, :hit, fn _ ->
        {:allow, 1000}
      end)
    end

    %{user: user_fixture(preload: [:account])}
  end

  describe "POST /users/log_in" do
    test "logs the user in when user params are in the user key", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "logs the user in when user params are flattened", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user[email]" => user.email,
          "user[password]" => valid_user_password()
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_tuist_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login following registration", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "_action" => "registered",
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully"
    end

    test "login following password update", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "_action" => "password_updated",
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "invalid@email.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    @tag rate_limited: true
    test "errors when it hits the rate limit", %{conn: conn, user: user} do
      # When under the rate limit
      first_conn =
        post(conn, ~p"/users/log_in", %{
          "user[email]" => user.email,
          "user[password]" => valid_user_password()
        })

      assert get_session(first_conn, :user_token)
      assert redirected_to(first_conn) == ~p"/#{user.account.name}/projects"

      # When above the rate limit
      second_conn =
        post(conn, ~p"/users/log_in", %{
          "user[email]" => user.email,
          "user[password]" => valid_user_password()
        })

      assert Phoenix.Flash.get(second_conn.assigns.flash, :error) ==
               gettext("You've exceeded the rate limit. Try again later.")

      assert redirected_to(second_conn) == ~p"/users/log_in"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
