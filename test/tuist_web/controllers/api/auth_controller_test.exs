defmodule TuistWeb.API.AuthControllerTest do
  alias Tuist.Repo
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  setup context do
    if Map.get(context, :rate_limited, false) do
      remote_ip = "127.0.0.1"
      rate_limit_key = "api_auth_authenticate:#{remote_ip}"
      rate_limit_scale = :timer.minutes(1)
      rate_limit_limit = 10
      TuistWeb.RemoteIp |> stub(:get, fn _ -> remote_ip end)

      TuistWeb.RateLimit
      |> expect(:hit, 1, fn ^rate_limit_key, ^rate_limit_scale, ^rate_limit_limit ->
        {:allow, 1}
      end)
      |> expect(:hit, 1, fn ^rate_limit_key, ^rate_limit_scale, ^rate_limit_limit ->
        {:deny, 1}
      end)
    else
      TuistWeb.RateLimit
      |> stub(:hit, fn _, _, _ ->
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
      conn =
        conn
        |> get(~p"/api/auth/device_code/#{device_code}")

      # Then
      response = json_response(conn, :accepted)
      assert response == %{}
    end

    test "returns accepted response when a device code exists, it is not authenticated and not expired",
         %{conn: conn} do
      # Given
      device_code = Accounts.create_device_code("AOKJ-1234")

      # When
      conn =
        conn
        |> get(~p"/api/auth/device_code/#{device_code.code}")

      # Then
      response = json_response(conn, :accepted)
      assert response == %{}
    end

    test "returns bad request response if device code is expired", %{conn: conn} do
      # Given
      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      device_code =
        Accounts.create_device_code("AOKJ-1234", created_at: ~U[2024-04-30 10:14:30Z])

      # When
      conn =
        conn
        |> get(~p"/api/auth/device_code/#{device_code.code}")

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

      Tuist.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:15:32Z] end)

      Accounts.authenticate_device_code(device_code.code, user)

      # When
      conn =
        conn
        |> get(~p"/api/auth/device_code/#{device_code.code}")

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
      conn =
        conn
        |> get(~p"/auth/device_codes/#{device_code}")

      # Then
      html_response(conn, 302)
      assert Accounts.get_device_code(device_code).code == device_code
    end

    test "does not create a new device code on a subsequent request", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      conn =
        conn
        |> get(~p"/auth/device_codes/#{device_code}")

      # When
      conn =
        conn
        |> get(~p"/auth/device_codes/#{device_code}")

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

      Tuist.Authentication
      |> expect(:refresh, fn ^refresh_token, ttl: {4, :weeks} ->
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
  end

  describe "POST /api/auth" do
    test "returns API tokens if the email and password are valid", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(password: "password") |> Tuist.Repo.preload(:account)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: "password"})

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
      user = AccountsFixtures.user_fixture(password: "password")

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
      user = AccountsFixtures.user_fixture(password: "password", confirmed_at: nil)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth", %{email: user.email, password: "password"})

      # Then
      response = json_response(conn, :unauthorized)
      assert response == %{"message" => "Please confirm your account before logging in."}
    end

    @tag :rate_limited
    test "fails the requests that go above the rate limit", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(password: "password") |> Tuist.Repo.preload(:account)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")

      # Then
      first_response =
        json_response(conn |> post("/api/auth", %{email: user.email, password: "password"}), :ok)

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
        json_response(
          conn |> post("/api/auth", %{email: user.email, password: "password"}),
          :too_many_requests
        )

      assert second_response == %{"message" => "You've exceeded the rate limit. Try again later."}
    end
  end
end
