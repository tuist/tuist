defmodule TuistWeb.UserSessionControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic
  use Gettext, backend: TuistWeb.Gettext

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment
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

    test "does not log the user in when email auth is disabled", %{conn: conn, user: user} do
      stub(Environment, :email_auth_enabled?, fn -> false end)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "disabled"
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

    test "does not carry another user's invitation return target across login", %{conn: conn, user: user} do
      other_user = user_fixture()

      conn =
        conn
        |> init_test_session(%{
          post_invitation_return_to: "/auth/device_codes/AOKJ-1234?type=cli",
          post_invitation_user_id: other_user.id,
          post_invitation_token: "invitation-token"
        })
        |> post(~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :post_invitation_return_to)
      refute get_session(conn, :post_invitation_user_id)
      refute get_session(conn, :post_invitation_token)
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

    test "redirects unconfirmed users to the confirmation resend page", %{conn: conn} do
      user = user_fixture(confirmed_at: nil)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/confirm"
      assert get_session(conn, :unconfirmed_email) == user.email
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

  describe "POST /users/log_in with Turnstile enabled" do
    setup do
      stub(Environment, :turnstile_required?, fn -> true end)
      stub(Environment, :turnstile_secret_key, fn -> "test-secret" end)
      stub(Environment, :app_url, fn -> "https://login.example.com" end)
      stub(FunWithFlags, :enabled?, fn :turnstile_kill_switch -> false end)
      :ok
    end

    test "direct submissions cannot omit the challenge, including alternate parameter shapes and actions", %{
      conn: conn,
      user: user
    } do
      for credentials <- [
            %{"user" => %{"email" => " #{user.email} ", "password" => valid_user_password(), "remember_me" => "true"}},
            %{
              "user[email]" => " #{user.email} ",
              "user[password]" => valid_user_password(),
              "user[remember_me]" => "true"
            }
          ],
          action <- [%{}, %{"_action" => "registered"}, %{"_action" => "password_updated"}],
          challenge <- [%{}, %{"cf-turnstile-response" => ""}, %{"cf-turnstile-response" => ["forged"]}] do
        response = post(conn, ~p"/users/log_in", credentials |> Map.merge(action) |> Map.merge(challenge))

        refute get_session(response, :user_token)
        refute response.resp_cookies["_tuist_web_user_remember_me"]
        assert redirected_to(response) == ~p"/users/log_in"
        assert Phoenix.Flash.get(response.assigns.flash, :email) == user.email

        assert Phoenix.Flash.get(response.assigns.flash, :error) ==
                 "Please complete the security check and try again."
      end
    end

    test "rejects a missing challenge without disclosing whether credentials are valid", %{conn: conn, user: user} do
      for email <- [user.email, "unknown@example.com"] do
        response =
          post(conn, ~p"/users/log_in", %{
            "user" => %{"email" => email, "password" => "wrong-password"}
          })

        refute get_session(response, :user_token)
        assert redirected_to(response) == ~p"/users/log_in"

        assert Phoenix.Flash.get(response.assigns.flash, :error) ==
                 "Please complete the security check and try again."
      end
    end

    test "rejects provider failures and tokens for other actions or hosts despite valid credentials", %{
      conn: conn,
      user: user
    } do
      for verification <- [
            {:ok, %Req.Response{status: 200, body: %{"success" => false, "error-codes" => ["timeout-or-duplicate"]}}},
            {:ok, %Req.Response{status: 200, body: %{"success" => true}}},
            {:ok, %Req.Response{status: 200, body: %{"success" => true, "action" => "email_login"}}},
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"success" => true, "action" => "email_signup", "hostname" => "login.example.com"}
             }},
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"success" => true, "action" => "email_login", "hostname" => "other.example.com"}
             }},
            {:ok, %Req.Response{status: 503}},
            {:error, :timeout}
          ] do
        stub(Req, :post, fn _endpoint, _opts -> verification end)

        response =
          post(conn, ~p"/users/log_in", %{
            "user" => %{"email" => user.email, "password" => valid_user_password(), "remember_me" => "true"},
            "cf-turnstile-response" => "untrusted-token"
          })

        refute get_session(response, :user_token)
        refute response.resp_cookies["_tuist_web_user_remember_me"]
        assert redirected_to(response) == ~p"/users/log_in"

        assert Phoenix.Flash.get(response.assigns.flash, :error) ==
                 "Please complete the security check and try again."
      end
    end

    test "fails closed when enabled without a secret", %{conn: conn, user: user} do
      stub(Environment, :turnstile_secret_key, fn -> nil end)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "cf-turnstile-response" => "untrusted-token"
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Please complete the security check and try again."
    end

    test "a verified login challenge still requires the correct password", %{conn: conn, user: user} do
      stub(Req, :post, fn "https://challenges.cloudflare.com/turnstile/v0/siteverify", opts ->
        assert opts[:form].secret == "test-secret"
        assert opts[:form].response in ["incorrect-password-token", "login-token"]

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"success" => true, "action" => "email_login", "hostname" => "login.example.com"}
         }}
      end)

      invalid =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "wrong-password"},
          "cf-turnstile-response" => "incorrect-password-token"
        })

      refute get_session(invalid, :user_token)
      assert Phoenix.Flash.get(invalid.assigns.flash, :error) == "Invalid email or password"

      valid =
        conn
        |> init_test_session(user_return_to: "/destination")
        |> post(~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password(), "remember_me" => "true"},
          "cf-turnstile-response" => "login-token"
        })

      assert get_session(valid, :user_token)
      assert valid.resp_cookies["_tuist_web_user_remember_me"]
      assert redirected_to(valid) == "/destination"
    end

    test "a valid challenge and password cannot bypass the authentication rate limit", %{conn: conn, user: user} do
      stub(Auth, :hit, fn _conn -> {:deny, 1} end)

      stub(Req, :post, fn _endpoint, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"success" => true, "action" => "email_login", "hostname" => "login.example.com"}
         }}
      end)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password(), "remember_me" => "true"},
          "cf-turnstile-response" => "login-token"
        })

      refute get_session(conn, :user_token)
      refute conn.resp_cookies["_tuist_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You've exceeded the rate limit. Try again later."
    end
  end

  test "self-hosted login needs no challenge even when Turnstile keys and its toggle are present", %{
    conn: conn,
    user: user
  } do
    stub(Environment, :tuist_hosted?, fn -> false end)
    stub(Environment, :turnstile_enabled?, fn -> true end)
    stub(Environment, :turnstile_secret_key, fn -> "test-secret" end)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert get_session(conn, :user_token)
    assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
  end

  describe "GET /docs/login" do
    test "redirects to login page", %{conn: conn} do
      conn = get(conn, ~p"/docs/login")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "stores return_to path in session", %{conn: conn} do
      conn = get(conn, ~p"/docs/login?#{%{return_to: "/en/docs/guides"}}")
      assert redirected_to(conn) == ~p"/users/log_in?#{%{return_to: "/en/docs/guides"}}"
      assert get_session(conn, :user_return_to) == "/en/docs/guides"
    end

    test "ignores non-local return_to paths", %{conn: conn} do
      conn = get(conn, ~p"/docs/login?#{%{return_to: "https://evil.com"}}")
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_return_to)
    end

    test "ignores protocol-relative return_to paths", %{conn: conn} do
      conn = get(conn, ~p"/docs/login?#{%{return_to: "//evil.example"}}")
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_return_to)
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

    test "redirects to return_to when it is a local path", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/log_out?#{%{return_to: "/en/docs/guides"}}")

      assert redirected_to(conn) == "/en/docs/guides"
      refute get_session(conn, :user_token)
    end

    test "ignores protocol-relative return_to paths", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/log_out?#{%{return_to: "//evil.example/foo"}}")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "ignores non-local return_to paths", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/log_out?#{%{return_to: "https://evil.example/foo"}}")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
