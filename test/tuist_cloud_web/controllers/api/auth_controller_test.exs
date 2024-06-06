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
      assert %{"token" => user.token} == response
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
end
