defmodule TuistWeb.API.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TelemetryTest

  alias Tuist.Accounts
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Authentication.RefreshReplays
  alias Tuist.OAuth.Apple
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit.Auth

  setup [:telemetry_listen]

  setup context do
    if Map.get(context, :rate_limited, false) do
      Auth
      |> expect(:hit, fn _conn ->
        {:allow, 1}
      end)
      |> expect(:hit, fn _conn ->
        {:deny, 1}
      end)
    else
      stub(Auth, :hit, fn _conn ->
        {:allow, 1000}
      end)
    end

    :ok
  end

  describe "POST /api/auth/device_codes" do
    test "starts a device sign-in with a secret device code and a short user code", %{conn: conn} do
      response = conn |> post(~p"/api/auth/device_codes") |> json_response(:ok)

      assert %{"device_code" => device_code, "user_code" => user_code, "expires_in" => 300, "interval" => 1} = response
      assert response["verification_uri"] =~ ~r{/auth/device$}
      assert user_code =~ ~r/^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/
      assert byte_size(device_code) >= 43
      assert Accounts.get_device_code(device_code).user_code == String.replace(user_code, "-", "")

      assert json_response(get(build_conn(), ~p"/api/auth/device_code/#{device_code}"), :accepted) == %{}
    end
  end

  describe "GET /api/auth/device_code" do
    test "returns accepted response when a device code does not exist", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      # When
      conn = get(conn, ~p"/api/auth/device_code/#{device_code}")

      # Then
      response = json_response(conn, :accepted)
      assert response == %{}
    end

    test "returns accepted response when a device code exists, it is not authenticated and not expired",
         %{conn: conn} do
      # Given
      device_code = Accounts.create_device_code("AOKJ-1234")

      # When
      conn = get(conn, ~p"/api/auth/device_code/#{device_code.code}")

      # Then
      response = json_response(conn, :accepted)
      assert response == %{}
    end

    test "returns bad request response if device code is expired", %{conn: conn} do
      # Given
      stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      device_code =
        Accounts.create_device_code("AOKJ-1234", created_at: ~U[2024-04-30 10:14:30Z])

      # When
      conn = get(conn, ~p"/api/auth/device_code/#{device_code.code}")

      # Then
      json_response(conn, :bad_request)
    end

    test "returns user token when a device code is not expired and is authenticated", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])

      device_code =
        Accounts.create_device_code("AOKJ-1234", created_at: ~U[2024-04-30 10:14:30Z])

      stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:15:32Z] end)
      Accounts.authenticate_device_code(device_code.code, user)

      # When
      conn = get(conn, ~p"/api/auth/device_code/#{device_code.code}")

      # Then
      response = json_response(conn, :ok)

      assert response["token"] == user.token

      {:ok, access_token_claims} =
        Tuist.Authentication.decode_and_verify(response["access_token"], %{
          "typ" => "access"
        })

      assert access_token_claims["email"] == user.email
      assert access_token_claims["preferred_username"] == user.account.name

      {:ok, refresh_token_claims} =
        Tuist.Authentication.decode_and_verify(response["refresh_token"], %{
          "typ" => "refresh"
        })

      assert refresh_token_claims["email"] == user.email
      assert refresh_token_claims["preferred_username"] == user.account.name
    end
  end

  describe "GET /auth/device_codes/:device_code" do
    setup [:register_and_log_in_user]

    test "creates device code", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      # When
      conn = get(conn, ~p"/auth/device_codes/#{device_code}")

      # Then
      html_response(conn, 200)
      assert Accounts.get_device_code(device_code).code == device_code
    end

    test "does not create a new device code on a subsequent request", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      conn = get(conn, ~p"/auth/device_codes/#{device_code}")

      # When
      conn = get(conn, ~p"/auth/device_codes/#{device_code}")

      # Then
      html_response(conn, 200)
      assert length(Repo.all(DeviceCode)) == 1
    end
  end

  describe "POST /auth/refresh_token" do
    test "returns refreshed tokens if the refresh token is valid", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      {:ok, refresh_token, _opts} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      response = json_response(conn, :ok)

      assert Tuist.Authentication.decode_and_verify(response["access_token"], %{
               "typ" => "access",
               "sub" => user.id
             })

      assert Tuist.Authentication.decode_and_verify(response["refresh_token"], %{
               "typ" => "refresh",
               "sub" => user.id
             })
    end

    test "returns refreshed tokens when the refresh token resolves to an AuthenticatedAccount",
         %{conn: conn} do
      # Given
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      {:ok, refresh_token, _opts} =
        Tuist.Authentication.encode_and_sign(
          account,
          %{"type" => "account", "scopes" => ["preview_create"]},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      response = json_response(conn, :ok)

      assert Tuist.Authentication.decode_and_verify(response["access_token"], %{
               "typ" => "access",
               "sub" => to_string(account.id)
             })

      assert Tuist.Authentication.decode_and_verify(response["refresh_token"], %{
               "typ" => "refresh",
               "sub" => to_string(account.id)
             })
    end

    test "returns unautheticated if the refresh token is expired", %{conn: conn} do
      # Given
      refresh_token = "refresh_token"

      expect(Tuist.Authentication, :refresh, fn ^refresh_token, [ttl: {4, :weeks}, sso_claims: nil] ->
        {:error, :expired_token}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] == "The refresh token is expired or invalid"
    end

    test "returns bad request if the request has no body", %{conn: conn} do
      # When
      conn = post(conn, "/api/auth/refresh_token")

      # Then
      assert json_response(conn, :bad_request) == %{"message" => "Missing header: content-type"}
    end

    test "returns unautheticated if the refresh token is invalid", %{conn: conn} do
      # Given
      refresh_token = "refresh_token"

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] == "The refresh token is expired or invalid"
    end

    @tag telemetry_listen: [:analytics, :authentication, :token_refresh, :error]
    test "returns bad request if the token is not a refresh token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      cli_version = "1.2.3"

      {:ok, access_token, _opts} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :access,
          ttl: {4, :weeks}
        )

      # When
      conn =
        conn
        |> TuistWeb.Headers.put_cli_version(cli_version)
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: access_token})

      # Then
      assert json_response(conn, :unauthorized) == %{
               "message" => "The refresh token is invalid."
             }

      expected_metadata = %{cli_version: cli_version, reason: "invalid_token_type"}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :authentication, :token_refresh, :error],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end

    @tag telemetry_listen: [:analytics, :authentication, :token_refresh, :error]
    test "doesn't include the cli version with the telemetry event if it's not present in the header",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      {:ok, access_token, _opts} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :access,
          ttl: {4, :weeks}
        )

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: access_token})

      # Then
      assert json_response(conn, :unauthorized) == %{
               "message" => "The refresh token is invalid."
             }

      expected_metadata = %{cli_version: nil, reason: "invalid_token_type"}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :authentication, :token_refresh, :error],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end

    test "returns bad request if the token belongs to a user that no longer exists", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      {:ok, access_token, _opts} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      Accounts.delete_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: access_token})

      # Then
      assert json_response(conn, :unauthorized) == %{
               "message" => "The refresh token is expired or invalid"
             }
    end

    test "handles token_not_found error", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      # Create a token but then remove it from Guardian.
      {:ok, refresh_token, claims} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      Guardian.DB.on_revoke(claims, refresh_token)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      assert json_response(conn, :unauthorized) == %{
               "message" => "The refresh token is expired or invalid"
             }
    end

    test "returns the same working tokens when a spent refresh token is replayed within the window", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)

      # When
      first = refresh(conn, refresh_token)
      replay = refresh(build_conn(), refresh_token)

      # Then
      assert %{"access_token" => access_token, "refresh_token" => new_refresh_token} = first
      assert replay == first
      assert Tuist.Authentication.authenticated_subject(access_token).id == user.id

      assert %{"refresh_token" => rotated_refresh_token} = refresh(build_conn(), new_refresh_token)
      refute rotated_refresh_token == new_refresh_token
    end

    test "rejects a spent refresh token replayed after the window", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      assert %{"access_token" => _} = refresh(conn, refresh_token)

      after_window = DateTime.add(DateTime.utc_now(), RefreshReplays.window_seconds() + 1, :second)
      stub(Tuist.Time, :utc_now, fn -> after_window end)

      # When
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      assert json_response(conn, :unauthorized) == %{"message" => "The refresh token is expired or invalid"}
    end

    test "doesn't replay one refresh token's response for another", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      other_refresh_token = refresh_token_fixture(user)

      # When
      first = refresh(conn, refresh_token)
      other = refresh(build_conn(), other_refresh_token)

      # Then
      refute other["access_token"] == first["access_token"]
      refute other["refresh_token"] == first["refresh_token"]
      assert refresh(build_conn(), refresh_token) == first
    end

    test "concurrent exchanges of the same refresh token mint a single pair" do
      # Given
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)

      # When
      responses =
        1..4
        |> Enum.map(fn _ -> Task.async(fn -> refresh(build_conn(), refresh_token) end) end)
        |> Task.await_many()

      # Then
      assert responses |> Enum.uniq() |> length() == 1

      assert %{rows: [[1]]} =
               Repo.query!("SELECT count(*) FROM guardian_tokens WHERE sub = $1 AND typ = 'refresh'", [
                 to_string(user.id)
               ])
    end

    test "handles token_expired error", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      {:ok, refresh_token, _claims} =
        Tuist.Authentication.encode_and_sign(user, %{},
          token_type: :refresh,
          ttl: {-1, :seconds}
        )

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Then
      assert json_response(conn, :unauthorized) == %{
               "message" => "The refresh token is expired or invalid"
             }
    end

    test "rejects refresh tokens of deactivated users", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      user |> Ecto.Changeset.change(active: false) |> Repo.update!()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      assert json_response(conn, :unauthorized) == %{"message" => "The refresh token is expired or invalid"}
    end

    test "a refresh racing a password reset yields no usable credentials", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      reset_token = reset_password_token(user)

      # The reset commits after the refresh verified the old token and before
      # it signs the new one, so the reset cannot see the new stored row.
      expect(Tuist.Authentication, :encode_and_sign, fn subject, claims, opts ->
        {:ok, _} = Accounts.reset_user_password(reset_token, %{password: "new valid password"})
        call_original(Tuist.Authentication, :encode_and_sign, [subject, claims, opts])
      end)

      %{"access_token" => access_token, "refresh_token" => new_refresh_token} = refresh(conn, refresh_token)
      stub(Tuist.Authentication, :encode_and_sign, &call_original(Tuist.Authentication, :encode_and_sign, [&1, &2, &3]))

      refute Tuist.Authentication.authenticated_subject(access_token)

      assert build_conn()
             |> put_req_header("content-type", "application/json")
             |> post("/api/auth/refresh_token", %{refresh_token: new_refresh_token})
             |> json_response(:unauthorized)
    end
  end

  describe "device codes and credential revocation" do
    test "a device code approved before a password reset grants nothing after it", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      device_code = Accounts.create_device_code("RESET-#{System.unique_integer([:positive])}")
      Accounts.authenticate_device_code(device_code.code, user, session(user, %{auth_method: :password}))

      {:ok, _} = Accounts.reset_user_password(reset_password_token(user), %{password: "new valid password"})

      assert conn |> get(~p"/api/auth/device_code/#{device_code.code}") |> json_response(:accepted) == %{}
    end
  end

  describe "POST /api/auth/refresh_token with SSO enforcement" do
    test "tokens from a device code approved without SSO keep refreshing for users no organization enforces it for",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)

      %{"refresh_token" => refresh_token} = device_code_tokens(conn, user, session(user, %{auth_method: :password}))

      assert {:ok, claims} = Tuist.Authentication.decode_and_verify(refresh_token, %{"typ" => "refresh"})
      refute Map.has_key?(claims, "sso")
      assert %{"refresh_token" => _} = refresh(build_conn(), refresh_token)
    end

    test "tokens issued before they carried SSO proof keep refreshing for users no organization enforces it for",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      # The claims every CLI token had before this change.
      {:ok, refresh_token, _claims} =
        Tuist.Authentication.encode_and_sign(user, %{email: user.email, preferred_username: "legacy"},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      assert %{"refresh_token" => _} = refresh(conn, refresh_token)
    end

    test "tokens issued before they carried SSO proof take the identity the user linked through the provider",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      organization = enforce_sso_for(user)
      AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: "example.com")

      %{"refresh_token" => refreshed_refresh_token} = refresh(conn, refresh_token)

      assert {:ok, %{"sso" => %{"provider" => "google", "provider_organization_id" => "example.com"}} = claims} =
               Tuist.Authentication.decode_and_verify(refreshed_refresh_token)

      assert claims["sso"]["organization_id"] == organization.id
      refute Map.has_key?(claims, "sso_grace_until")
      assert %{"refresh_token" => _} = refresh(build_conn(), refreshed_refresh_token)
    end

    test "an identity linked to another provider tenant is no proof", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      enforce_sso_for(user)

      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :google,
        provider_organization_id: "other.example.com"
      )

      %{"refresh_token" => refreshed_refresh_token} = refresh(conn, refresh_token)

      assert {:ok, claims} = Tuist.Authentication.decode_and_verify(refreshed_refresh_token)
      refute Map.has_key?(claims, "sso")
      assert is_integer(claims["sso_grace_until"])
    end

    test "tokens without SSO proof refresh for a grace period that starts at their first refresh and never extends",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      refresh_token = refresh_token_fixture(user)
      enforce_sso_for(user)
      now = DateTime.to_unix(DateTime.utc_now())

      %{"refresh_token" => first} = refresh(conn, refresh_token)
      assert {:ok, %{"sso_grace_until" => grace_until} = claims} = Tuist.Authentication.decode_and_verify(first)
      refute Map.has_key?(claims, "sso")
      assert_in_delta grace_until, now + 28 * 24 * 60 * 60, 60

      %{"refresh_token" => second} = refresh(build_conn(), first)
      assert {:ok, %{"sso_grace_until" => ^grace_until}} = Tuist.Authentication.decode_and_verify(second)
    end

    test "tokens whose grace period ended stop refreshing, and are not spent", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      enforce_sso_for(user)

      {:ok, refresh_token, _claims} =
        Tuist.Authentication.encode_and_sign(
          user,
          %{"sso_grace_until" => DateTime.to_unix(DateTime.utc_now()) - 1},
          token_type: :refresh,
          ttl: {4, :weeks}
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})

      # Existing CLIs answer 401 by removing the credentials and showing this.
      assert %{"message" => "Your organization requires single sign-on. Run `tuist auth login`" <> _} =
               json_response(conn, :unauthorized)

      # The refused token is not spent: signing in through the provider
      # links the identity that lets it refresh again.
      AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google, provider_organization_id: "example.com")
      assert %{"refresh_token" => _} = refresh(build_conn(), refresh_token)
    end

    test "tokens from a device code approved through the organization's SSO keep its proof and keep refreshing",
         %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      enforce_sso_for(user)
      sso_session = session(user, %{auth_method: :google, provider_organization_id: "example.com"})

      %{"access_token" => access_token, "refresh_token" => refresh_token} = device_code_tokens(conn, user, sso_session)

      for token <- [access_token, refresh_token] do
        assert {:ok, %{"sso" => %{"provider" => "google", "provider_organization_id" => "example.com"}}} =
                 Tuist.Authentication.decode_and_verify(token)
      end

      %{"refresh_token" => refreshed_refresh_token} = refresh(build_conn(), refresh_token)

      # The proof carries over to the rotated token, so later refreshes pass too.
      assert {:ok, %{"sso" => %{"provider_organization_id" => "example.com"}}} =
               Tuist.Authentication.decode_and_verify(refreshed_refresh_token)

      assert %{"refresh_token" => _} = refresh(build_conn(), refreshed_refresh_token)
    end

    test "tokens whose SSO proof no longer matches the organization drop it for a grace period", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      organization = enforce_sso_for(user)
      sso_session = session(user, %{auth_method: :google, provider_organization_id: "example.com"})
      %{"refresh_token" => refresh_token} = device_code_tokens(conn, user, sso_session)

      organization |> Ecto.Changeset.change(sso_organization_id: "other.example.com") |> Repo.update!()

      %{"refresh_token" => refreshed_refresh_token} = refresh(build_conn(), refresh_token)
      assert {:ok, claims} = Tuist.Authentication.decode_and_verify(refreshed_refresh_token)
      refute Map.has_key?(claims, "sso")
      assert is_integer(claims["sso_grace_until"])
    end
  end

  describe "POST /api/auth" do
    test "returns bad request if the request has no body", %{conn: conn} do
      # When
      conn = post(conn, "/api/auth")

      # Then
      assert json_response(conn, :bad_request) == %{"message" => "Missing header: content-type"}
    end

    test "refuses members of an organization that enforces single sign-on", %{conn: conn} do
      password = UUIDv7.generate()
      user = AccountsFixtures.user_fixture(password: password)
      enforce_sso_for(user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: password})

      assert %{"message" => "Your organization requires single sign-on." <> _} = json_response(conn, :unauthorized)
    end

    test "returns API tokens if the email and password are valid", %{conn: conn} do
      # Given
      password = UUIDv7.generate()

      user =
        [password: password] |> AccountsFixtures.user_fixture() |> Repo.preload(:account)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: password})

      # Then
      response = json_response(conn, :ok)

      {:ok, access_token_claims} =
        assert Tuist.Authentication.decode_and_verify(response["access_token"], %{
                 "typ" => "access"
               })

      assert access_token_claims["sub"] == to_string(user.id)
      assert access_token_claims["email"] == user.email
      assert access_token_claims["preferred_username"] == user.account.name

      {:ok, refresh_token_claims} =
        assert Tuist.Authentication.decode_and_verify(response["refresh_token"], %{
                 "typ" => "refresh"
               })

      assert refresh_token_claims["sub"] == to_string(user.id)
      assert refresh_token_claims["email"] == user.email
      assert refresh_token_claims["preferred_username"] == user.account.name
    end

    test "returns forbidden when email auth is disabled", %{conn: conn} do
      # Given
      stub(Tuist.Environment, :email_auth_enabled?, fn -> false end)
      password = UUIDv7.generate()
      user = AccountsFixtures.user_fixture(password: password)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: password})

      # Then
      response = json_response(conn, :forbidden)
      assert response == %{"message" => "Email and password sign-in is disabled."}
    end

    test "returns unauthorized when the password is invalid", %{conn: conn} do
      # Given
      password = UUIDv7.generate()
      user = AccountsFixtures.user_fixture(password: password)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: "invalid_password"})

      # Then
      response = json_response(conn, :unauthorized)
      assert response == %{"message" => "Invalid email or password."}
    end

    test "returns unauthorized when the email is invalid", %{conn: conn} do
      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: "invalid_email", password: "password"})

      # Then
      response = json_response(conn, :unauthorized)
      assert response == %{"message" => "Invalid email or password."}
    end

    test "returns unauthorized when the user is not confirmed", %{conn: conn} do
      # Given
      password = UUIDv7.generate()
      user = AccountsFixtures.user_fixture(password: password, confirmed_at: nil)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: password})

      # Then
      response = json_response(conn, :unauthorized)
      assert response == %{"message" => "Please confirm your account before logging in."}
    end

    @tag :rate_limited
    test "fails the requests that go above the rate limit", %{conn: conn} do
      # Given
      password = UUIDv7.generate()

      user =
        [password: password] |> AccountsFixtures.user_fixture() |> Repo.preload(:account)

      # When
      conn = put_req_header(conn, "content-type", "application/json")

      # Then
      first_response =
        conn |> post("/api/auth", %{email: user.email, password: password}) |> json_response(:ok)

      {:ok, access_token_claims} =
        assert Tuist.Authentication.decode_and_verify(first_response["access_token"], %{
                 "typ" => "access"
               })

      assert access_token_claims["sub"] == to_string(user.id)
      assert access_token_claims["email"] == user.email
      assert access_token_claims["preferred_username"] == user.account.name

      {:ok, refresh_token_claims} =
        assert Tuist.Authentication.decode_and_verify(first_response["refresh_token"], %{
                 "typ" => "refresh"
               })

      assert refresh_token_claims["sub"] == to_string(user.id)
      assert refresh_token_claims["email"] == user.email
      assert refresh_token_claims["preferred_username"] == user.account.name

      second_response =
        conn
        |> post("/api/auth", %{email: user.email, password: "password"})
        |> json_response(:too_many_requests)

      assert second_response == %{"message" => "You've exceeded the rate limit. Try again later."}
    end
  end

  describe "POST /api/auth/apple" do
    test "returns bad request if the request has no body", %{conn: conn} do
      # When
      conn = post(conn, "/api/auth/apple")

      # Then
      assert json_response(conn, :bad_request) == %{"message" => "Missing header: content-type"}
    end

    test "refuses members of an organization that enforces single sign-on", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      enforce_sso_for(user)
      stub(Apple, :verify_apple_identity_token_and_create_user, fn _token, _code -> {:ok, user} end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/apple", %{identity_token: "identity-token", authorization_code: "authorization-code"})

      assert %{"message" => "Your organization requires single sign-on." <> _} = json_response(conn, :unauthorized)
    end

    test "returns access and refresh tokens when Apple authentication succeeds", %{conn: conn} do
      # Given
      identity_token = "identity-token"
      authorization_code = "authorization-code"
      email = "my-apple@example.com"
      user = AccountsFixtures.user_fixture(email: email)

      expect(Apple, :verify_apple_identity_token_and_create_user, fn ^identity_token, ^authorization_code ->
        {:ok, user}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/apple", %{
          identity_token: identity_token,
          authorization_code: authorization_code
        })

      # Then
      response = json_response(conn, :ok)

      {:ok, _access_token_claims} =
        Tuist.Authentication.decode_and_verify(response["access_token"], %{
          "typ" => "access"
        })

      {:ok, _refresh_token_claims} =
        Tuist.Authentication.decode_and_verify(response["refresh_token"], %{
          "typ" => "refresh"
        })

      {:ok, fetched_user} = Accounts.get_user_by_email(email)
      assert fetched_user.email == email
    end
  end

  defp refresh_token_fixture(user) do
    {:ok, refresh_token, _claims} =
      Tuist.Authentication.encode_and_sign(user, %{}, token_type: :refresh, ttl: {4, :weeks})

    refresh_token
  end

  defp refresh(conn, refresh_token) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/auth/refresh_token", %{refresh_token: refresh_token})
    |> json_response(:ok)
  end

  defp session(user, auth) do
    user |> Accounts.generate_user_session_token(auth) |> Accounts.get_user_session()
  end

  defp reset_password_token(user) do
    {token, user_token} = Accounts.UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    token
  end

  defp device_code_tokens(conn, user, session) do
    device_code = Accounts.create_device_code("SSO-#{System.unique_integer([:positive])}")
    Accounts.authenticate_device_code(device_code.code, user, session)

    conn |> get(~p"/api/auth/device_code/#{device_code.code}") |> json_response(:ok)
  end

  defp enforce_sso_for(user) do
    organization = AccountsFixtures.organization_fixture()
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    # Enabling enforcement through `Accounts` also requires a verified login
    # email domain, which is not what these tests are about.
    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: :google, sso_organization_id: "example.com")
    |> Repo.update!()
  end
end
