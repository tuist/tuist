defmodule TuistWeb.UserForgotPasswordLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  test "unknown addresses spend the same requester budget across fresh sessions", %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    parent = self()

    stub(Bamboo.TestAdapter, :deliver, fn email, config ->
      send(parent, {:reset_email, email})
      Mimic.call_original(Bamboo.TestAdapter, :deliver, [email, config])
    end)

    user = user_fixture()
    # Fresh HTTP/LiveView sessions from one requester must not reset its quota.
    conn = %{conn | remote_ip: {192, 0, 2, rem(user.id, 250) + 1}}

    for _ <- 1..10 do
      {:ok, view, _} = live(conn, "/users/reset_password")
      render_submit(view, "send_email", %{"user" => %{"email" => "missing-#{user.id}@example.com"}})
      assert has_element?(view, "#forgot-password-success")
    end

    {:ok, blocked, _} = live(conn, "/users/reset_password")
    render_submit(blocked, "send_email", %{"user" => %{"email" => user.email}})
    assert has_element?(blocked, "#forgot-password-success")
    refute_receive {:reset_email, _}
    refute Repo.exists?(from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"))

    {:ok, allowed, _} = live(%{conn | remote_ip: {198, 51, 100, rem(user.id, 250) + 1}}, "/users/reset_password")
    render_submit(allowed, "send_email", %{"user" => %{"email" => user.email}})
    assert has_element?(allowed, "#forgot-password-success")
    assert_receive {:reset_email, _}
  end

  test "a configured shared limiter outage does not send mail or enumerate accounts", %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :redis_url, fn -> "redis://unavailable" end)
    stub(Tuist.RateLimit.PersistentTokenBucket, :hit, fn _, _, _, _ -> exit(:noproc) end)
    user = user_fixture()

    responses =
      for email <- [user.email, "missing-#{user.id}@example.com"] do
        {:ok, view, _} = live(conn, "/users/reset_password")
        render_submit(view, "send_email", %{"user" => %{"email" => email}})
        view |> element("#forgot-password-success") |> render()
      end

    assert [response] = Enum.uniq(responses)
    assert response =~ "If your email exists in our records"
    refute Repo.exists?(from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"))
  end

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset_password")

      assert html =~ "Forgot your password?"
    end

    test "redirects to log in when email auth is disabled", %{conn: conn} do
      stub(Environment, :email_auth_enabled?, fn -> false end)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/reset_password")
      assert to == ~p"/users/log_in"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture(preload: [:account])

      result =
        conn
        |> log_in_user(user)
        |> live(~p"/users/reset_password")
        |> follow_redirect(conn, ~p"/#{user.account.name}/projects")

      assert {:ok, _conn} = result
    end

    test "keeps the response non-enumerating on provider and mail configuration failures", %{conn: conn} do
      stub(Bamboo.TestAdapter, :deliver, fn _email, _config ->
        {:error, Bamboo.ApiError.exception("mail provider unavailable")}
      end)

      user = user_fixture()

      for failure <- [:provider, :configuration, :sender] do
        stub(Environment, :mailing_from_address, fn ->
          if failure == :sender, do: nil, else: "noreply@tuist.dev"
        end)

        stub(Bamboo.TestAdapter, :handle_config, fn config ->
          if failure == :configuration do
            Bamboo.MailgunAdapter.handle_config(Map.put(config, :api_key, nil))
          else
            config
          end
        end)

        responses =
          for email <- [user.email, "unknown@example.com"] do
            {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

            lv
            |> form("#login_form", user: %{email: email})
            |> render_submit()

            assert has_element?(lv, "#forgot-password-success")
            lv |> element("#forgot-password-success") |> render()
          end

        assert [response] = Enum.uniq(responses)
        assert response =~ "If your email exists in our records"
        refute Repo.exists?(from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"))
      end
    end

    test "delivers a usable reset link without enumerating accounts or resending during cooldown", %{conn: conn} do
      stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)

      test_pid = self()

      stub(Bamboo.TestAdapter, :deliver, fn email, config ->
        result = Mimic.call_original(Bamboo.TestAdapter, :deliver, [email, config])
        send(test_pid, {:reset_email, email})
        result
      end)

      user = user_fixture()

      {:ok, first_live, _html} = live(conn, ~p"/users/reset_password")

      first_live
      |> form("#login_form", user: %{email: "  #{String.upcase(user.email)}  "})
      |> render_submit()

      assert has_element?(first_live, "#forgot-password-success")
      assert_receive {:reset_email, email}
      assert email.to == [nil: user.email]
      assert email.subject == "Reset password instructions"

      [reset_url] = email.html_body |> Floki.parse_document!() |> Floki.attribute("a.button-primary", "href")
      assert email.text_body =~ reset_url
      assert URI.parse(reset_url).host == "localhost"
      assert "/users/reset_password/" <> token = URI.parse(reset_url).path
      assert Accounts.get_user_by_reset_password_token(token).id == user.id

      {:ok, second_live, _html} = live(build_conn(), ~p"/users/reset_password")

      second_live
      |> form("#login_form", user: %{email: user.email})
      |> render_submit()

      assert Repo.aggregate(
               from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
               :count,
               :id
             ) == 1

      refute_receive {:reset_email, _}

      {:ok, reset_live, _html} = live(build_conn(), URI.parse(reset_url).path)

      reset_live
      |> form("#reset_password_form",
        user: %{password: "replacement password", password_confirmation: "replacement password"}
      )
      |> render_submit()

      assert_redirect(reset_live, ~p"/users/log_in")
      assert {:ok, updated_user} = Accounts.get_user_by_email_and_password(user.email, "replacement password")
      assert updated_user.id == user.id

      assert {:error, :invalid_email_or_password} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())

      refute Accounts.get_user_by_reset_password_token(token)

      {:ok, unknown_live, _html} = live(build_conn(), ~p"/users/reset_password")

      unknown_live
      |> form("#login_form", user: %{email: "unknown@example.com"})
      |> render_submit()

      assert has_element?(unknown_live, "#forgot-password-success")

      assert unknown_live |> element("#forgot-password-success") |> render() ==
               first_live |> element("#forgot-password-success") |> render()

      refute_receive {:reset_email, _}
    end
  end
end
