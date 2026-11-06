defmodule TuistWeb.UserMFAControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserToken
  alias Tuist.Accounts.Workers.SecurityNotificationWorker
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
    refute UserMFA.enabled?(user)

    document = enrollment |> html_response(200) |> Floki.parse_document!()
    assert Floki.find(document, "#sso-link #user-security-settings #mfa-enrollment") != []
    assert Floki.find(document, ".layout__content") == []
    assert ["data:image/png;base64," <> png] = Floki.attribute(document, "#mfa-setup-qr", "src")
    assert <<137, "PNG", _::binary>> = Base.decode64!(png)
    assert Floki.find(document, "#mfa-manual-setup[open]") == []
    assert Floki.find(document, "input#mfa-setup-key[readonly]") != []
    assert Floki.find(document, "button[data-copy-setup-key][aria-label='Copy setup key']") != []
    assert Floki.find(document, "#mfa-code[autocomplete='one-time-code'][inputmode='numeric']") != []
    assert Floki.find(document, "#passkey-registration") == []

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
    document = confirmed |> html_response(200) |> Floki.parse_document!()
    assert Floki.find(document, "#sso-link #user-security-settings #mfa-recovery-codes") != []
    assert Floki.find(document, ".layout__content") == []
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "mfa_enabled"})
    assert UserMFA.enabled?(user)
    refute Accounts.get_user_by_session_token(old_token)
    render_hook(view, "open_create_project", %{})
    # The projects page also serves signed-out visitors, so a revoked session
    # reloads it and the HTTP pipeline drops the dead credential.
    assert_redirect(view, ~p"/#{user.account.name}/projects")
    assert Accounts.get_user_by_session_token(get_session(confirmed, :user_token)).id == user.id
    [[encrypted]] = Repo.query!("SELECT secret FROM user_mfa WHERE user_id = $1", [user.id]).rows
    refute encrypted == secret

    other = user_fixture()
    stale = login(other)
    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)
    assert stale |> recycle() |> post(~p"/users/settings/mfa/enroll") |> html_response(403) =~ "Sign out"
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

  test "an enrolled factor rejects sessions it did not verify after confirmation", %{user: user, now: now} do
    enroll(user, now)

    # A sign-in racing confirmation reads the factor as disabled and stores a
    # session without proof; confirmation's revocation can run before it lands.
    unverified = Accounts.generate_user_session_token(user, %{auth_method: :password})
    before = Accounts.generate_user_session_token(user, %{auth_method: :password, mfa_verified_at: DateTime.add(now, -1)})
    at_confirmation = Accounts.generate_user_session_token(user, %{auth_method: :password, mfa_verified_at: now})

    refute Accounts.get_user_session(unverified)
    refute Accounts.get_user_session(before)
    assert Accounts.get_user_session(at_confirmation).user_id == user.id
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
    assert %{max_age: 2_592_000, value: remember} = verified.resp_cookies["_tuist_web_user_remember_me"]

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
    pending = login(user)
    pending = init_test_session(recycle(pending), Map.put(get_session(pending), "user_return_to", "/\\evil.example"))

    assert pending
           |> post(~p"/users/mfa", %{"mfa_code" => first})
           |> redirected_to() ==
             ~p"/#{user.account.name}/projects"

    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "recovery_used"})

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
    destination = ~p"/auth/device_codes/#{device.code}?type=cli"
    pending = get(build_conn(), destination)
    assert redirected_to(pending) == ~p"/users/log_in"

    pending =
      pending
      |> recycle()
      |> post(~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})

    refute Accounts.get_device_code(device.code).authenticated

    assert pending |> recycle() |> post(~p"/auth/device_codes/#{device.code}", %{"type" => "cli"}) |> redirected_to() ==
             ~p"/users/log_in"

    refute Accounts.get_device_code(device.code).authenticated
    verified = pending |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => recovery})
    assert redirected_to(verified) == destination
    assert verified |> recycle() |> get(destination) |> html_response(200) =~ device.code

    assert verified |> recycle() |> post(~p"/auth/device_codes/#{device.code}", %{"type" => "cli"}) |> redirected_to() ==
             ~p"/auth/device_codes/#{device.code}/success?type=cli"

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
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "mfa_enabled"})

    invalid =
      confirmed
      |> recycle()
      |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => "invalid"})
      |> html_response(401)

    document = Floki.parse_document!(invalid)
    assert Floki.find(document, "#sso-link #user-security-settings") != []
    assert Floki.find(document, "form[action='/users/settings/mfa/disable']") != []
    assert Floki.find(document, "form[action='/users/settings/mfa/recovery']") == []

    assert UserMFA.enabled?(user)
    second_browser = user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => first})
    second_token = get_session(second_browser, :user_token)
    disabled = confirmed |> recycle() |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => second})
    assert redirected_to(disabled) == ~p"/users/settings/mfa"
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "mfa_disabled"})
    refute UserMFA.enabled?(user)
    refute Accounts.get_user_by_session_token(second_token)
    assert user |> login() |> redirected_to() == ~p"/#{user.account.name}/projects"
  end

  test "notification delivery failure cannot undo enrollment or disablement", %{user: user, now: now} do
    stub(Tuist.Accounts.UserNotifier, :deliver_mfa_change_notification, fn _, _ -> {:error, :delivery_unavailable} end)
    {confirmed, _secret, [recovery | _]} = enroll(user, now)
    assert UserMFA.enabled?(user)
    assert Accounts.get_user_by_session_token(get_session(confirmed, :user_token)).id == user.id

    assert {:error, :delivery_unavailable} =
             perform_job(SecurityNotificationWorker, %{user_id: user.id, event: "mfa_enabled"})

    disabled = confirmed |> recycle() |> post(~p"/users/settings/mfa/disable", %{"mfa_code" => recovery})
    assert redirected_to(disabled) == ~p"/users/settings/mfa"
    refute UserMFA.enabled?(user)
    assert Accounts.get_user_by_session_token(get_session(disabled, :user_token)).id == user.id
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "mfa_disabled"})
  end

  test "regeneration requires fresh proof, replaces the entire code set and preserves the authenticator", %{
    user: user,
    now: now
  } do
    {confirmed, secret, [first, old_unused | _]} = enroll(user, now)
    old_token = get_session(confirmed, :user_token)
    assert UserMFA.recovery_code_count(user) == 10

    invalid =
      confirmed
      |> recycle()
      |> post(~p"/users/settings/mfa/recovery", %{"mfa_code" => "invalid"})
      |> html_response(401)

    document = Floki.parse_document!(invalid)
    assert Floki.find(document, "#sso-link #user-security-settings") != []
    assert Floki.find(document, "form[action='/users/settings/mfa/recovery']") != []
    assert Floki.find(document, "form[action='/users/settings/mfa/disable']") == []

    assert UserMFA.recovery_code_count(user) == 10

    regenerated = confirmed |> recycle() |> post(~p"/users/settings/mfa/recovery", %{"mfa_code" => first})
    [new_code | _] = new_codes = recovery_codes(regenerated)
    assert length(new_codes) == 10
    refute first in new_codes
    assert UserMFA.enabled?(user)
    assert Repo.get_by!(UserMFA, user_id: user.id).secret == secret
    assert get_resp_header(regenerated, "cache-control") == ["private, no-store"]
    refute Accounts.get_user_by_session_token(old_token)
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "recovery_regenerated"})

    assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => old_unused}) |> html_response(401)

    assert user |> login() |> recycle() |> post(~p"/users/mfa", %{"mfa_code" => new_code}) |> redirected_to() ==
             ~p"/#{user.account.name}/projects"

    assert UserMFA.recovery_code_count(user) == 9

    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    assert regenerated
           |> recycle()
           |> post(~p"/users/settings/mfa/recovery", %{"mfa_code" => Enum.at(new_codes, 1)})
           |> html_response(401)

    assert UserMFA.recovery_code_count(user) == 9
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
    |> Floki.attribute("#mfa-setup-key", "value")
    |> List.first()
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
