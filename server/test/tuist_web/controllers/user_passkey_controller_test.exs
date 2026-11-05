defmodule TuistWeb.UserPasskeyControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Bamboo.Test
  import Bitwise
  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserPasskey
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

    assert redirected_to(registered) == ~p"/users/settings/mfa"
    assert_email_delivered_with(subject: "Passkey added", to: [nil: user.email])

    assert [%UserPasskey{name: "MacBook", backup_eligible: true, transports: ["hybrid", "internal"]}] =
             UserPasskey.list(user)

    assert Phoenix.Flash.get(registered.assigns.flash, :info) == "Passkey added."

    settings = registered |> recycle() |> get(~p"/users/settings/mfa") |> html_response(200)
    assert settings =~ "Passkey added."
    assert settings =~ "MacBook"

    # Enabling the authenticator app afterwards must not make passkey sign-in
    # ask for a code: a user-verified passkey is already multi-factor.
    enable_mfa(user, now)

    {options_conn, options} = authentication_options(build_conn(), ~p"/users/log_in/passkey/options")
    assert options["publicKey"]["allowCredentials"] == []
    assert options["publicKey"]["userVerification"] == "required"

    # The sign-in page requests options for autofill and for the button at
    # once; a later options response must not invalidate an earlier challenge.
    {options_conn, _later} = authentication_options(options_conn, ~p"/users/log_in/passkey/options")

    assertion = sign_assertion(authenticator, options, user_handle(user))
    signed_in = options_conn |> recycle() |> post(~p"/users/log_in/passkey", assertion)

    assert redirected_to(signed_in) == ~p"/#{user.account.name}/projects"
    session = Accounts.get_user_session(get_session(signed_in, :user_token))
    assert session.user_id == user.id
    assert session.auth_provider == "passkey"
    assert session.mfa_verified_at

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
    assert_email_delivered_with(subject: "Passkey added", to: [nil: user.email])
    other_browser = login(user)
    [passkey] = UserPasskey.list(user)

    stub(Time, :utc_now, fn -> DateTime.add(now, 301) end)

    # The refusal comes before the browser ceremony, so no unusable
    # credential is saved in the user's password manager.
    stale_options = current |> recycle() |> post(~p"/users/settings/passkeys/options")
    assert json_response(stale_options, 403)["error"] =~ "Sign out"

    stale = current |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete")
    assert Phoenix.Flash.get(stale.assigns.flash, :error) =~ "Sign out"
    assert [_] = UserPasskey.list(user)

    stub(Time, :utc_now, fn -> now end)
    fresh = login(user)
    removed = fresh |> recycle() |> post(~p"/users/settings/passkeys/#{passkey.id}/delete")

    assert redirected_to(removed) == ~p"/users/settings/mfa"
    assert UserPasskey.list(user) == []
    assert_email_delivered_with(subject: "Passkey removed", to: [nil: user.email])
    refute Accounts.get_user_by_session_token(get_session(other_browser, :user_token))
    assert Accounts.get_user_by_session_token(get_session(removed, :user_token)).id == user.id
  end

  test "passkeys are unavailable when email authentication is disabled", %{user: user, now: now} do
    authenticator = authenticator()
    signed_in = login(user)
    register(signed_in, authenticator, "MacBook")
    assert build_conn() |> get(~p"/users/log_in") |> html_response(200) =~ "passkey-login"
    assert signed_in |> recycle() |> get(~p"/users/settings/mfa") |> html_response(200) =~ "Add a passkey"
    stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)

    refute build_conn() |> get(~p"/users/log_in") |> html_response(200) =~ "passkey-login"
    refute signed_in |> recycle() |> get(~p"/users/settings/mfa") |> html_response(200) =~ "Add a passkey"
    assert build_conn() |> post(~p"/users/log_in/passkey/options") |> response(404)
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

  defp register(conn, authenticator, name) do
    options_conn = conn |> recycle() |> post(~p"/users/settings/passkeys/options")
    %{"publicKey" => options, "token" => token} = json_response(options_conn, 200)
    assert options["authenticatorSelection"]["userVerification"] == "required"

    options_conn
    |> recycle()
    |> post(~p"/users/settings/passkeys", %{
      "challenge_token" => token,
      "name" => name,
      "transports" => "hybrid,internal,unknown",
      "attestation_object" => encode(attestation_object(authenticator)),
      "client_data_json" => encode(client_data("webauthn.create", options["challenge"]))
    })
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
