defmodule TuistWeb.API.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TelemetryTest

  alias Tuist.Accounts
  alias Tuist.Accounts.DeviceCode
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
      html_response(conn, 302)
      assert Accounts.get_device_code(device_code).code == device_code
    end

    test "does not create a new device code on a subsequent request", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      conn = get(conn, ~p"/auth/device_codes/#{device_code}")

      # When
      conn = get(conn, ~p"/auth/device_codes/#{device_code}")

      # Then
      html_response(conn, 302)
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

    test "returns unautheticated if the refresh token is expired", %{conn: conn} do
      # Given
      refresh_token = "refresh_token"

      expect(Tuist.Authentication, :refresh, fn ^refresh_token, [ttl: {4, :weeks}] ->
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
  end

  describe "POST /api/auth" do
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
    test "returns access and refresh tokens when Apple authentication succeeds", %{conn: conn} do
      # Given
      identity_token = "identity-token"
      authorization_code = "authorization-code"
      email = "my-apple@example.com"
      user = AccountsFixtures.user_fixture(email: email)

      expect(Tuist.OAuth.Apple, :verify_apple_identity_token_and_create_user, fn ^identity_token, ^authorization_code ->
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
end
