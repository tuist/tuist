defmodule TuistWeb.UserPasskeyControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Bitwise
  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserPasskey
  alias Tuist.Accounts.Workers.SecurityNotificationWorker
  alias Tuist.Repo
  alias Tuist.Time

  # authenticatorData flags (WebAuthn §6.1)
  @user_present 0x01
  @user_verified 0x04
  @backup_eligible 0x08
  @backed_up 0x10
  @attested_credential 0x40

  setup do
    current = DateTime.truncate(DateTime.utc_now(), :second)
    stub(Time, :utc_now, fn -> current end)
    stub(TuistWeb.RateLimit.Auth, :hit, fn _ -> {:allow, 1} end)
    %{user: user_fixture(preload: [:account]), now: current}
  end

  test "a registered passkey signs in without a password and satisfies MFA", %{user: user, now: now} do
    authenticator = authenticator()
    registered = register(login(user), authenticator, "MacBook")

    assert redirected_to(registered) == ~p"/#{user.account.name}/settings/authentication"
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "passkey_added"})

    assert [%UserPasskey{name: "MacBook", backup_eligible: true, transports: ["hybrid", "internal"]}] =
             UserPasskey.list(user)

    assert Phoenix.Flash.get(registered.assigns.flash, :info) == "Passkey added."

    authentication =
      registered |> recycle() |> get(~p"/#{user.account.name}/settings/authentication") |> html_response(200)

    assert authentication =~ "Passkey added."

    assert registered |> recycle() |> get(~p"/users/settings/passkeys") |> redirected_to() ==
             ~p"/#{user.account.name}/settings/authentication"

    document = Floki.parse_document!(authentication)

    assert document |> Floki.find("#passkey-list th") |> Enum.map(&Floki.text/1) ==
             ["Name", "Created", "Last used", ""]

    assert Floki.text(Floki.find(document, "#passkey-list")) =~ "MacBook"
    assert Floki.find(document, "#passkey-actions-#{hd(UserPasskey.list(user)).id}[aria-label='Actions']") != []

    assert Floki.find(
             document,
             "[phx-click='open-security-modal'][phx-value-id='rename-passkey-#{hd(UserPasskey.list(user)).id}']"
           ) != []

    assert Floki.find(
             document,
             "[phx-click='open-security-modal'][phx-value-id='remove-passkey-#{hd(UserPasskey.list(user)).id}']"
           ) != []

    assert Floki.find(
             document,
             "form[action='/users/settings/passkeys/#{hd(UserPasskey.list(user)).id}/delete'] input[name='confirm'][value='true']"
           ) != []

    refute authentication =~ "Manage passkeys"

    settings = registered |> recycle() |> get(~p"/#{user.account.name}/settings/passkeys") |> html_response(200)
    assert settings =~ "Passkey added."
    assert settings =~ "MacBook"
    assert settings =~ "Sign in without a password."
    assert settings =~ "Never used"
    refute settings =~ "mfa-enrollment"
    refute UserMFA.enabled?(user)

    settings =
      registered |> recycle() |> get(~p"/#{user.account.name}/settings/two-factor-authentication") |> html_response(200)

    refute settings =~ "passkey-list"
    refute settings =~ "MacBook"

    # Enabling the authenticator app afterwards must not make passkey sign-in
    # ask for a code: a user-verified passkey is already multi-factor.
    enable_mfa(user, now)

    {options_conn, options} = authentication_options(build_conn(), ~p"/users/log_in/passkey/options")
    assert options["publicKey"]["allowCredentials"] == []
    assert options["publicKey"]["userVerification"] == "required"

    # Repeated requests must not invalidate an earlier challenge.
    {options_conn, _later} = authentication_options(options_conn, ~p"/users/log_in/passkey/options")

    assertion = sign_assertion(authenticator, options, user_handle(user))
    signed_in = options_conn |> recycle() |> post(~p"/users/log_in/passkey", assertion)

    assert redirected_to(signed_in) == ~p"/#{user.account.name}/projects"
    session = Accounts.get_user_session(get_session(signed_in, :user_token))
    assert session.user_id == user.id
    assert session.auth_provider == "passkey"
    assert session.mfa_verified_at

    settings = signed_in |> recycle() |> get(~p"/#{user.account.name}/settings/passkeys") |> html_response(200)
    assert settings =~ Calendar.strftime(now, "%Y-%m-%d %H:%M UTC")
    refute settings =~ "Never used"

    # Presenting the same ceremony token and assertion again must not create
    # another session.
    replayed = options_conn |> recycle() |> post(~p"/users/log_in/passkey", assertion)
    assert redirected_to(replayed) == ~p"/users/log_in"
    refute get_session(replayed, :user_token)
  end

  test "sign-in rejects assertions that are not user-verified, regress the counter, or forge backup state",
       %{user: user} do
    authenticator = authenticator(sign_count: 5)
    register(login(user), authenticator, "Security key")

    for {flags, sign_count} <- [
          {@user_present ||| @backup_eligible, 6},
          {@user_present ||| @user_verified ||| @backup_eligible, 4},
          {@user_present ||| @user_verified ||| @backed_up, 6},
          # Backup eligibility is fixed at registration and must not change.
          {@user_present ||| @user_verified, 6}
        ] do
      {conn, options} = authentication_options(build_conn(), ~p"/users/log_in/passkey/options")

      assertion =
        sign_assertion(authenticator, options, user_handle(user), flags: flags, sign_count: sign_count)

      rejected = conn |> recycle() |> post(~p"/users/log_in/passkey", assertion)

      assert redirected_to(rejected) == ~p"/users/log_in"
      refute get_session(rejected, :user_token)
    end

    # The user handle must belong to the credential's user.
    {conn, options} = authentication_options(build_conn(), ~p"/users/log_in/passkey/options")
    assertion = sign_assertion(authenticator, options, :crypto.strong_rand_bytes(32), sign_count: 6)
    refute conn |> recycle() |> post(~p"/users/log_in/passkey", assertion) |> get_session(:user_token)

    {conn, options} = authentication_options(build_conn(), ~p"/users/log_in/passkey/options")
    assertion = sign_assertion(authenticator, options, user_handle(user), sign_count: 6)
    assert conn |> recycle() |> post(~p"/users/log_in/passkey", assertion) |> get_session(:user_token)
  end

  test "a passkey completes the MFA challenge only for the challenged user", %{user: user, now: now} do
    authenticator = authenticator()
    register(login(user), authenticator, "MacBook")
    other_user = user_fixture()
    other_authenticator = authenticator()
    register(login(other_user), other_authenticator, "Other")
    enable_mfa(user, now)

    pending = login(user)
    assert redirected_to(pending) == ~p"/users/mfa"
    assert pending |> recycle() |> get(~p"/users/mfa") |> html_response(200) =~ "Use a passkey"

    # MFA passkey options require a pending challenge in this browser.
    assert build_conn() |> post(~p"/users/mfa/passkey/options") |> json_response(404)

    {conn, options} = authentication_options(pending, ~p"/users/mfa/passkey/options")
    assert [%{"id" => allowed}] = options["publicKey"]["allowCredentials"]
    assert Base.url_decode64!(allowed, padding: false) == authenticator.credential_id

    other = sign_assertion(other_authenticator, options, user_handle(other_user))
    rejected = conn |> recycle() |> post(~p"/users/mfa", other)
    assert html_response(rejected, 401) =~ "passkey could not be verified"

    # A rejected passkey is not a code guess, so it must not count toward
    # locking the authenticator app.
    expired_token = %{other | "challenge_token" => "not-a-token"}
    assert rejected |> recycle() |> post(~p"/users/mfa", expired_token) |> html_response(401)
    assert Repo.get_by!(UserMFA, user_id: user.id).failed_attempts == 0

    # A ceremony token issued for passwordless sign-in cannot answer the
    # MFA challenge.
    {conn, sign_in_options} = authentication_options(rejected, ~p"/users/log_in/passkey/options")
    wrong_ceremony = sign_assertion(authenticator, sign_in_options, user_handle(user))
    assert conn |> recycle() |> post(~p"/users/mfa", wrong_ceremony) |> html_response(401)

    {conn, options} = authentication_options(conn, ~p"/users/mfa/passkey/options")

    verified =
      conn |> recycle() |> post(~p"/users/mfa", sign_assertion(authenticator, options, user_handle(user)))

    session = Accounts.get_user_session(get_session(verified, :user_token))
    assert session.user_id == user.id
    assert session.auth_provider == "password"
    assert session.mfa_verified_at
  end

  test "changing passkeys requires a fresh sign-in and removal revokes other sessions", %{user: user, now: now} do
    authenticator = authenticator()
    current = login(user)
    register(current, authenticator, "MacBook")
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "passkey_added"})
    other_browser = login(user)
    [passkey] = UserPasskey.list(user)

    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    settings = current |> recycle() |> get(~p"/#{user.account.name}/settings/authentication") |> html_response(200)
    document = Floki.parse_document!(settings)
    assert Floki.text(Floki.find(document, "#passkey-list")) =~ "MacBook"
    assert Floki.find(document, "#passkey-list button") == []

    # The refusal comes before the browser ceremony, so no unusable
    # credential is saved in the user's password manager.
    stale_options = current |> recycle() |> post(~p"/users/settings/passkeys/options")
    assert json_response(stale_options, 403)["error"] =~ "Sign in again"
    assert json_response(stale_options, 403)["reauthenticate"]

    stale = current |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete", %{"confirm" => "true"})
    assert Phoenix.Flash.get(stale.assigns.flash, :error) =~ "Sign in again"
    assert [_] = UserPasskey.list(user)

    stub(Time, :utc_now, fn -> now end)
    mfa = enable_mfa(user, now)

    fresh =
      user
      |> login()
      |> recycle()
      |> post(~p"/users/mfa", %{"mfa_code" => NimbleTOTP.verification_code(mfa.secret, time: DateTime.to_unix(now))})

    removed = fresh |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete", %{"confirm" => "true"})

    assert redirected_to(removed) == ~p"/users/settings/passkeys"
    assert UserPasskey.list(user) == []
    assert UserMFA.enabled?(user)
    assert_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "passkey_removed"})
    refute Accounts.get_user_by_session_token(get_session(other_browser, :user_token))
    assert Accounts.get_user_by_session_token(get_session(removed, :user_token)).id == user.id
  end

  test "renaming is scoped to the signed-in user and requires a recent session", %{user: user, now: now} do
    current = register(login(user), authenticator(), "Original")
    other_user = user_fixture()
    other_browser = register(login(other_user), authenticator(), "Other")
    [passkey] = UserPasskey.list(user)
    [other_passkey] = UserPasskey.list(other_user)
    token = get_session(current, :user_token)

    renamed =
      current
      |> recycle()
      |> post(~p"/users/settings/passkeys/#{passkey.id}/rename", %{"name" => "  My vault  "})

    assert redirected_to(renamed) == ~p"/users/settings/passkeys"
    assert Phoenix.Flash.get(renamed.assigns.flash, :info) == "Passkey renamed."
    assert Repo.get!(UserPasskey, passkey.id).name == "My vault"
    assert get_session(renamed, :user_token) == token
    assert Accounts.get_user_by_session_token(get_session(other_browser, :user_token))
    refute_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "passkey_removed"})

    for {name, expected} <- [{"   ", "Passkey"}, {String.duplicate("é", 65), String.duplicate("é", 64)}] do
      renamed |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/rename", %{"name" => name})
      assert Repo.get!(UserPasskey, passkey.id).name == expected
    end

    rejected =
      renamed
      |> recycle()
      |> post(~p"/users/settings/passkeys/#{other_passkey.id}/rename", %{"name" => "Not mine"})

    assert redirected_to(rejected) == ~p"/users/settings/passkeys"
    assert Phoenix.Flash.get(rejected.assigns.flash, :error)
    assert Repo.get!(UserPasskey, other_passkey.id).name == "Other"

    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    stale =
      renamed
      |> recycle()
      |> post(~p"/users/settings/passkeys/#{passkey.id}/rename", %{"name" => "Stale"})

    assert Phoenix.Flash.get(stale.assigns.flash, :error) =~ "Sign in again"
    assert Repo.get!(UserPasskey, passkey.id).name == String.duplicate("é", 64)
  end

  test "stale passkey pages offer reauthentication without exposing mutation forms", %{user: user, now: now} do
    current = register(login(user), authenticator(), "My vault")
    [passkey] = UserPasskey.list(user)
    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    for path <- [
          ~p"/#{user.account.name}/settings/passkeys",
          ~p"/users/settings/passkeys/new",
          ~p"/users/settings/passkeys/#{passkey.id}/delete"
        ] do
      document = current |> recycle() |> get(path) |> html_response(200) |> Floki.parse_document!()
      assert Floki.text(document) =~ "Sign in again"
      assert Floki.find(document, "[data-part='terms-notice']") == []
      assert Floki.find(document, "#passkey-add, #confirm-passkey-removal, form[action$='/rename']") == []
      assert Floki.attribute(document, "form", "action") == ["/users/log_out?" <> URI.encode_query(%{return_to: path})]
      assert UserPasskey.list(user) == [passkey]
    end
  end

  test "removal confirmation and cancel are read-only and scoped to the signed-in user", %{user: user} do
    current = register(login(user), authenticator(), "My vault")
    other_browser = login(user)
    [passkey] = UserPasskey.list(user)
    token = get_session(current, :user_token)

    confirmation = current |> recycle() |> get(~p"/users/settings/passkeys/#{passkey.id}/delete")
    html = html_response(confirmation, 200)
    assert html =~ "My vault"
    assert html =~ "Your other sessions will be signed out"
    assert html =~ "This is your last passkey"
    assert html =~ "password reset"
    assert html =~ "saved credential will remain"
    document = Floki.parse_document!(html)
    assert Floki.find(document, "#sso-link #user-security-settings #confirm-passkey-removal") != []
    assert Floki.find(document, ".layout__content") == []
    assert Floki.attribute(document, "#cancel-passkey-removal", "href") == [~p"/users/settings/passkeys"]
    assert Floki.attribute(document, "form input[name=confirm]", "value") == ["true"]
    assert Floki.attribute(document, "form", "action") == [~p"/users/settings/passkeys/#{passkey.id}/delete"]

    canceled = confirmation |> recycle() |> get(~p"/#{user.account.name}/settings/passkeys")
    assert html_response(canceled, 200) =~ "My vault"
    assert Repo.get!(UserPasskey, passkey.id) == passkey
    assert get_session(canceled, :user_token) == token
    assert Accounts.get_user_by_session_token(get_session(other_browser, :user_token))
    refute_enqueued(worker: SecurityNotificationWorker, args: %{user_id: user.id, event: "passkey_removed"})

    unconfirmed = current |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete")
    assert redirected_to(unconfirmed) == ~p"/users/settings/passkeys/#{passkey.id}/delete"
    assert Repo.get!(UserPasskey, passkey.id) == passkey

    other_user = user_fixture()
    stranger = login(other_user)
    assert stranger |> recycle() |> get(~p"/users/settings/passkeys/#{passkey.id}/delete") |> response(404)

    denied = stranger |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete", %{"confirm" => "true"})
    assert redirected_to(denied) == ~p"/users/settings/passkeys"
    assert Repo.get!(UserPasskey, passkey.id) == passkey
  end

  test "passkeys are unavailable when email authentication is disabled", %{user: user, now: now} do
    authenticator = authenticator()
    signed_in = login(user)
    register(signed_in, authenticator, "MacBook")
    assert build_conn() |> get(~p"/users/log_in") |> html_response(200) =~ "passkey-login"

    document =
      signed_in |> recycle() |> get(~p"/users/settings/passkeys/new") |> html_response(200) |> Floki.parse_document!()

    assert Floki.find(document, "#sso-link #user-security-settings #passkey-registration") != []
    assert Floki.find(document, ".layout__content") == []
    stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)

    refute build_conn() |> get(~p"/users/log_in") |> html_response(200) =~ "passkey-login"

    refute signed_in
           |> recycle()
           |> get(~p"/#{user.account.name}/settings/two-factor-authentication")
           |> html_response(200) =~ "Add a passkey"

    assert build_conn() |> post(~p"/users/log_in/passkey/options") |> response(404)
    assert signed_in |> recycle() |> get(~p"/users/settings/passkeys") |> response(404)
    assert signed_in |> recycle() |> post(~p"/users/settings/passkeys/options") |> response(404)

    stub(Tuist.Environment, :email_auth_enabled?, fn -> true end)
    enable_mfa(user, now)
    pending = login(user)
    assert redirected_to(pending) == ~p"/users/mfa"
    {_conn, mfa_options} = authentication_options(pending, ~p"/users/mfa/passkey/options")
    stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)

    assert pending |> recycle() |> post(~p"/users/mfa/passkey/options") |> response(404)

    # A ceremony token issued while passkeys were enabled no longer answers
    # the MFA challenge.
    mfa_assertion = sign_assertion(authenticator, mfa_options, user_handle(user))
    rejected = pending |> recycle() |> post(~p"/users/mfa", mfa_assertion)
    assert html_response(rejected, 401) =~ "passkey could not be verified"
    refute get_session(rejected, :user_token)

    assertion = %{
      "challenge_token" => "",
      "credential_id" => encode(authenticator.credential_id),
      "user_handle" => encode(user_handle(user))
    }

    refute build_conn() |> post(~p"/users/log_in/passkey", assertion) |> get_session(:user_token)
  end

  defp login(user) do
    post(build_conn(), ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})
  end

  defp enable_mfa(user, now) do
    Repo.insert!(%UserMFA{
      user_id: user.id,
      secret: NimbleTOTP.secret(),
      enrollment_session_hash: :crypto.hash(:sha256, "enrollment"),
      enrollment_expires_at: now,
      confirmed_at: now
    })
  end

  test "passkeys created without a name get distinct labels and can be renamed", %{user: user} do
    conn = login(user)
    settings = conn |> recycle() |> get(~p"/users/settings/passkeys/new") |> html_response(200)
    assert settings =~ "Create a passkey"
    refute settings =~ ~s(id="passkey-name")

    conn = register(conn, authenticator(), nil)
    assert redirected_to(conn) == ~p"/#{user.account.name}/settings/authentication"
    assert [%UserPasskey{name: "Passkey"} = first] = UserPasskey.list(user)

    conn = register(conn, authenticator(), nil)
    assert Enum.sort(Enum.map(UserPasskey.list(user), & &1.name)) == ["Passkey", "Passkey 2"]

    conn |> recycle() |> post(~p"/users/settings/passkeys/#{first.id}/rename", %{"name" => "My vault"})
    assert Repo.get!(UserPasskey, first.id).name == "My vault"

    register(conn, authenticator(), nil)
    assert Enum.sort(Enum.map(UserPasskey.list(user), & &1.name)) == ["My vault", "Passkey", "Passkey 2"]
  end

  defp register(conn, authenticator, name) do
    options_conn = conn |> recycle() |> post(~p"/users/settings/passkeys/options")
    %{"publicKey" => options, "token" => token} = json_response(options_conn, 200)
    assert options["authenticatorSelection"]["userVerification"] == "required"

    params = %{
      "challenge_token" => token,
      "transports" => "hybrid,internal,unknown",
      "attestation_object" => encode(attestation_object(authenticator)),
      "client_data_json" => encode(client_data("webauthn.create", options["challenge"]))
    }

    params = if name, do: Map.put(params, "name", name), else: params

    options_conn
    |> recycle()
    |> post(~p"/users/settings/passkeys", params)
  end

  defp authentication_options(conn, path) do
    conn = conn |> recycle() |> post(path)
    {conn, json_response(conn, 200)}
  end

  defp user_handle(user) do
    Repo.one!(from passkey in UserPasskey, where: passkey.user_id == ^user.id, select: passkey.user_handle)
  end

  defp authenticator(opts \\ []) do
    {<<4, x::binary-size(32), y::binary-size(32)>>, private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      credential_id: :crypto.strong_rand_bytes(16),
      private_key: private_key,
      cose_key: %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)},
      sign_count: Keyword.get(opts, :sign_count, 0)
    }
  end

  defp attestation_object(authenticator) do
    flags = @user_present ||| @user_verified ||| @backup_eligible ||| @backed_up ||| @attested_credential
    credential_id = authenticator.credential_id

    attested =
      <<0::128, byte_size(credential_id)::16>> <> credential_id <> CBOR.encode(authenticator.cose_key)

    CBOR.encode(%{
      "fmt" => "none",
      "attStmt" => %{},
      "authData" => bytes(authenticator_data(flags, authenticator.sign_count) <> attested)
    })
  end

  defp sign_assertion(
         authenticator,
         %{"publicKey" => %{"challenge" => challenge}, "token" => token},
         user_handle,
         opts \\ []
       ) do
    flags = Keyword.get(opts, :flags, @user_present ||| @user_verified ||| @backup_eligible ||| @backed_up)
    authenticator_data = authenticator_data(flags, Keyword.get(opts, :sign_count, authenticator.sign_count))
    client_data_json = client_data("webauthn.get", challenge)
    signed = authenticator_data <> :crypto.hash(:sha256, client_data_json)

    %{
      "challenge_token" => token,
      "credential_id" => encode(authenticator.credential_id),
      "authenticator_data" => encode(authenticator_data),
      "client_data_json" => encode(client_data_json),
      "signature" => encode(:crypto.sign(:ecdsa, :sha256, signed, [authenticator.private_key, :prime256v1])),
      "user_handle" => encode(user_handle)
    }
  end

  defp authenticator_data(flags, sign_count) do
    :crypto.hash(:sha256, URI.parse(origin()).host) <> <<flags, sign_count::32>>
  end

  defp client_data(type, challenge) do
    JSON.encode!(%{"type" => type, "challenge" => challenge, "origin" => origin(), "crossOrigin" => false})
  end

  defp origin do
    uri = URI.parse(Tuist.Environment.app_url(route_type: :app))
    URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port})
  end

  defp bytes(value), do: %CBOR.Tag{tag: :bytes, value: value}
  defp encode(value), do: Base.url_encode64(value, padding: false)
end
