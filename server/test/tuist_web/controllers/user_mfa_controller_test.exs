defmodule TuistWeb.UserMFAControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Bamboo.Test
  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo
  alias Tuist.Time

  setup do
    current = DateTime.truncate(DateTime.utc_now(), :second)
    stub(Time, :utc_now, fn -> current end)
    stub(TuistWeb.RateLimit.Auth, :hit, fn _ -> {:allow, 1} end)
    %{user: user_fixture(preload: [:account]), now: current}
  end

  test "enrollment requires a fresh session, confirms possession and revokes older sessions", %{user: user, now: now} do
    old = login(user)
    old_token = get_session(old, :user_token)
    {:ok, view, _} = old |> recycle() |> live(~p"/#{user.account.name}/projects")

    enrollment = old |> recycle() |> post(~p"/users/settings/mfa/enroll")
    assert get_resp_header(enrollment, "cache-control") == ["private, no-store"]
    secret = setup_secret(enrollment)
    assert enrollment |> html_response(200) |> Floki.parse_document!() |> Floki.attribute("#mfa-setup-qr", "src") != []
    refute UserMFA.enabled?(user)

    invalid = enrollment |> recycle() |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => "invalid"})
    assert html_response(invalid, 401) =~ "code is invalid"
    assert setup_secret(invalid, 401) == secret
    refute UserMFA.enabled?(user)

    other_browser = login(user)

    assert other_browser
           |> recycle()
           |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => code(secret, now)})
           |> html_response(401)

    confirmed = enrollment |> recycle() |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => code(secret, now)})
    assert length(recovery_codes(confirmed)) == 10
    assert_email_delivered_with(subject: "Two-factor authentication enabled", to: [nil: user.email])
    assert UserMFA.enabled?(user)
    refute Accounts.get_user_by_session_token(old_token)
    render_hook(view, "open_create_project", %{})
    assert_redirect(view, ~p"/users/log_in")
    assert Accounts.get_user_by_session_token(get_session(confirmed, :user_token)).id == user.id
    [[encrypted]] = Repo.query!("SELECT secret FROM user_mfa WHERE user_id = $1", [user.id]).rows
    refute encrypted == secret

    other = user_fixture()
    stale = login(other)
    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)
    assert stale |> recycle() |> post(~p"/users/settings/mfa/enroll") |> html_response(403) =~ "Sign out"
  end

  test "browser OTP forms identify the account without restricting recovery codes to six digits", %{user: user, now: now} do
    enroll(user, now)
    pending = login(user)
    page = pending |> recycle() |> get(~p"/users/mfa") |> html_response(200) |> Floki.parse_document!()
    assert Floki.attribute(page, "#mfa-challenge input[autocomplete=username]", "value") == [user.email]
    assert Floki.find(page, ~s(label[for="mfa-code"])) != []
    assert Floki.find(page, ~s(#mfa-code[autocomplete="one-time-code"][inputmode=numeric][maxlength="6"])) != []
    assert Floki.attribute(page, "#mfa-recovery-code", "maxlength") == []

    invalid =
      pending
      |> recycle()
      |> post(~p"/users/mfa", %{"mfa_code" => "invalid-recovery-code", "recovery" => "true"})
      |> html_response(401)
      |> Floki.parse_document!()

    assert Floki.find(invalid, "#mfa-recovery[open]") != []
    assert Floki.find(invalid, "#mfa-recovery-code[autofocus]") != []
    assert Floki.find(invalid, "#mfa-code[autofocus]") == []
  end

  test "cancel discards only this browser's pending setup, never an enabled factor", %{user: user, now: now} do
    enrollment = user |> login() |> recycle() |> post(~p"/users/settings/mfa/enroll")
    secret = setup_secret(enrollment)

    other_browser = login(user)
    assert other_browser |> recycle() |> post("/users/settings/mfa/cancel") |> redirected_to() == ~p"/users/settings/mfa"

    confirmed = enrollment |> recycle() |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => code(secret, now)})
    assert UserMFA.enabled?(user)
    assert confirmed |> recycle() |> post("/users/settings/mfa/cancel") |> redirected_to() == ~p"/users/settings/mfa"
    assert UserMFA.enabled?(user)

    other = user_fixture(preload: [:account])
    pending = other |> login() |> recycle() |> post(~p"/users/settings/mfa/enroll")
    old_secret = setup_secret(pending)
    cancelled = pending |> recycle() |> post("/users/settings/mfa/cancel")
    assert redirected_to(cancelled) == ~p"/users/settings/mfa"
    refute UserMFA.enabled?(other)

    assert pending
           |> recycle()
           |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => code(old_secret, now)})
           |> html_response(401)

    replacement = cancelled |> recycle() |> post(~p"/users/settings/mfa/enroll")
    refute setup_secret(replacement) == old_secret
  end

  test "factor changes reject a session revoked after the request authenticated", %{user: user, now: now} do
    signed_in = login(user)
    session = Accounts.get_user_session(get_session(signed_in, :user_token))
    {:ok, factor} = UserMFA.begin_enrollment(user, session)
    signed_in |> recycle() |> delete(~p"/users/log_out")

    assert {:error, :enrollment_expired} = UserMFA.confirm_enrollment(user, session, code(factor.secret, now))
    refute UserMFA.enabled?(user)
    assert {:error, :reauthentication_required} = UserMFA.begin_enrollment(user, session)
  end

  test "password and remembered login need a second factor; codes and challenges cannot replay", %{user: user, now: now} do
    {_confirmed, secret, _codes} = enroll(user, now)
    stub(Time, :utc_now, fn -> DateTime.add(now, 31) end)
    pending = login(user, %{"remember_me" => "true", "mfa_verified_at" => "forged"})
    assert redirected_to(pending) == ~p"/users/mfa"
    refute get_session(pending, :user_token)
    assert pending |> recycle() |> get(~p"/#{user.account.name}/projects") |> redirected_to() == ~p"/users/log_in"

    verified = pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => code(secret, DateTime.add(now, 31))})
    assert redirected_to(verified) == ~p"/#{user.account.name}/projects"
    assert %{max_age: 28_800, value: remember} = verified.resp_cookies["_tuist_web_user_remember_me"]

    assert build_conn()
           |> put_req_cookie("_tuist_web_user_remember_me", remember)
           |> get(~p"/#{user.account.name}/projects")
           |> html_response(200)

    assert pending
           |> recycle()
           |> post(~p"/users/mfa", %{"mfa_code" => code(secret, DateTime.add(now, 31))})
           |> redirected_to() == ~p"/users/log_in"

    assert user
           |> login()
           |> recycle()
           |> post(~p"/users/mfa", %{"mfa_code" => code(secret, DateTime.add(now, 31))})
           |> html_response(401)
  end

  test "recovery codes work once across independent browser challenges", %{user: user, now: now} do
    {_confirmed, _secret, [first, second | _]} = enroll(user, now)

    assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> redirected_to() ==
             ~p"/#{user.account.name}/projects"

    pending = login(user)
    assert pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> html_response(401)

    assert pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => second}) |> redirected_to() ==
             ~p"/#{user.account.name}/projects"
  end

  test "challenge expiry, logout and password reset cannot bypass the enrolled factor", %{user: user, now: now} do
    {_confirmed, _secret, [first | _]} = enroll(user, now)
    pending = login(user)
    stub(Time, :utc_now, fn -> DateTime.add(now, 300) end)
    assert pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> redirected_to() == ~p"/users/log_in"

    pending = login(user)
    pending |> recycle() |> delete(~p"/users/log_out")
    assert pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> redirected_to() == ~p"/users/log_in"

    pending = login(user)
    {reset_token, reset_record} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(reset_record)
    {:ok, reset_view, _} = live(build_conn(), ~p"/users/reset_password/#{reset_token}")

    reset_view
    |> form("#reset_password_form", %{
      "user" => %{"password" => "a new valid password", "password_confirmation" => "a new valid password"}
    })
    |> render_submit()

    assert_redirect(reset_view, ~p"/users/log_in")

    assert pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> redirected_to() == ~p"/users/log_in"
    assert UserMFA.enabled?(user)
    assert user |> login(%{"password" => "a new valid password"}) |> redirected_to() == ~p"/users/mfa"
  end

  test "device login cannot issue human credentials before completing MFA", %{user: user, now: now} do
    {_confirmed, _secret, [recovery | _]} = enroll(user, now)
    device = Accounts.create_device_code("mfa-device-#{user.id}")
    destination = ~p"/auth/device_codes/#{device.code}/success?type=cli"
    pending = get(build_conn(), destination)
    assert redirected_to(pending) == ~p"/users/log_in"

    pending =
      pending
      |> recycle()
      |> post(~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})

    refute Accounts.get_device_code(device.code).authenticated
    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(recycle(pending), destination)
    verified = pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => recovery})
    assert redirected_to(verified) == destination
    assert {:ok, _, _} = live(recycle(verified), destination)
    assert Accounts.get_device_code(device.code).authenticated
  end

  test "five failed codes share a per-user budget across challenges, then expire", %{user: user, now: now} do
    {_confirmed, _secret, [first | _]} = enroll(user, now)

    for _ <- 1..5 do
      assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => "invalid"}) |> html_response(401)
    end

    assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> html_response(401)
    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first}) |> redirected_to() ==
             ~p"/#{user.account.name}/projects"
  end

  test "direct API password and Apple sign-in cannot skip MFA while existing tokens remain valid", %{user: user, now: now} do
    tokens =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth", %{"email" => user.email, "password" => valid_user_password()})
      |> json_response(200)

    {_confirmed, _secret, _codes} = enroll(user, now)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post(~p"/api/auth", %{"email" => user.email, "password" => valid_user_password()})
           |> json_response(401) == %{"message" => "Two-factor authentication is enabled. Use browser sign-in."}

    assert Tuist.Authentication.authenticated_subject(tokens["access_token"])
    stub(Tuist.OAuth.Apple, :verify_apple_identity_token_and_create_user, fn _, _ -> {:ok, user} end)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post(~p"/api/auth/apple", %{"identity_token" => "local-proof", "authorization_code" => "local-code"})
           |> json_response(401)
  end

  test "disabling requires a fresh verified session and unused code and revokes all sessions", %{user: user, now: now} do
    {confirmed, _secret, [first, second | _]} = enroll(user, now)
    assert_email_delivered_with(subject: "Two-factor authentication enabled", to: [nil: user.email])

    assert confirmed
           |> recycle()
           |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => "invalid"})
           |> html_response(401)

    assert UserMFA.enabled?(user)
    second_browser = user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first})
    second_token = get_session(second_browser, :user_token)
    disabled = confirmed |> recycle() |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => second})
    assert redirected_to(disabled) == ~p"/users/settings/mfa"
    assert_email_delivered_with(subject: "Two-factor authentication disabled", to: [nil: user.email])
    refute UserMFA.enabled?(user)
    refute Accounts.get_user_by_session_token(second_token)
    assert user |> login() |> redirected_to() == ~p"/#{user.account.name}/projects"
  end

  test "notification delivery failure cannot undo enrollment or disablement", %{user: user, now: now} do
    stub(Tuist.Accounts.UserNotifier, :deliver_mfa_change_notification, fn _, _ -> {:error, :delivery_unavailable} end)
    {confirmed, _secret, [recovery | _]} = enroll(user, now)
    assert UserMFA.enabled?(user)
    assert Accounts.get_user_by_session_token(get_session(confirmed, :user_token)).id == user.id

    disabled = confirmed |> recycle() |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => recovery})
    assert redirected_to(disabled) == ~p"/users/settings/mfa"
    refute UserMFA.enabled?(user)
    assert Accounts.get_user_by_session_token(get_session(disabled, :user_token)).id == user.id
  end

  defp login(user, extra \\ %{}) do
    params = Map.merge(%{"email" => user.email, "password" => valid_user_password()}, extra)
    post(build_conn(), ~p"/users/log_in", %{"user" => params})
  end

  defp enroll(user, now) do
    enrollment = user |> login() |> recycle() |> post(~p"/users/settings/mfa/enroll")
    secret = setup_secret(enrollment)
    confirmed = enrollment |> recycle() |> post(~p"/users/settings/mfa/confirm", %{"mfa_code" => code(secret, now)})
    {confirmed, secret, recovery_codes(confirmed)}
  end

  defp setup_secret(conn, status \\ 200) do
    conn
    |> html_response(status)
    |> Floki.parse_document!()
    |> Floki.find("#mfa-setup-key")
    |> Floki.text()
    |> Base.decode32!(padding: false)
  end

  defp recovery_codes(conn) do
    conn
    |> html_response(200)
    |> Floki.parse_document!()
    |> Floki.find("#mfa-recovery-codes code")
    |> Enum.map(&Floki.text/1)
  end

  defp code(secret, now), do: NimbleTOTP.verification_code(secret, time: now)
end
