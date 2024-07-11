defmodule TuistCloudWeb.API.AuthControllerTest do
  alias TuistCloud.Repo
  alias TuistCloud.Accounts.DeviceCode
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

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
      TuistCloud.Time
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
      user = AccountsFixtures.user_fixture()

      device_code =
        Accounts.create_device_code("AOKJ-1234", created_at: ~U[2024-04-30 10:14:30Z])

      TuistCloud.Time
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:15:32Z] end)

      Accounts.authenticate_device_code(device_code.code, user)

      # When
      conn =
        conn
        |> get(~p"/api/auth/device_code/#{device_code.code}")

      # Then
      response = json_response(conn, :ok)

      assert response["token"] == user.token

      assert TuistCloud.Authentication.decode_and_verify(response["access_token"], %{
               "typ" => "access",
               "sub" => user.id
             })

      assert TuistCloud.Authentication.decode_and_verify(response["refresh_token"], %{
               "typ" => "refresh",
               "sub" => user.id
             })
    end
  end

  describe "GET /cli/:device_code" do
    setup [:register_and_log_in_user]

    test "creates device code", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      # When
      conn =
        conn
        |> get(~p"/auth/cli/#{device_code}")

      # Then
      html_response(conn, 302)
      assert Accounts.get_device_code(device_code).code == device_code
    end

    test "does not create a new device code on a subsequent request", %{conn: conn} do
      # Given
      device_code = "AOKJ-1234"

      conn =
        conn
        |> get(~p"/auth/cli/#{device_code}")

      # When
      conn =
        conn
        |> get(~p"/auth/cli/#{device_code}")

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
        TuistCloud.Authentication.encode_and_sign(user, %{},
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

      assert TuistCloud.Authentication.decode_and_verify(response["access_token"], %{
               "typ" => "access",
               "sub" => user.id
             })

      assert TuistCloud.Authentication.decode_and_verify(response["refresh_token"], %{
               "typ" => "refresh",
               "sub" => user.id
             })
    end
  end

  test "returns unautheticated if the refresh token is expired", %{conn: conn} do
    # Given
    refresh_token = "refresh_token"

    TuistCloud.Authentication
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
