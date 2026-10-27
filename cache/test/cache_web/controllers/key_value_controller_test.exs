defmodule CacheWeb.KeyValueControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.KeyValueStore

  describe "GET /api/cache/keyvalue/:cas_id" do
    test "gets cache value successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id_123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, ["value1", "value2"])

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      response = json_response(conn, :ok)

      assert response["entries"] == [
               %{"value" => "value1"},
               %{"value" => "value2"}
             ]
    end

    test "returns not found when no entries exist", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "nonexistent_cas_id"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      response = json_response(conn, :not_found)
      assert response["message"] == "No entries found for CAS ID #{cas_id}."
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        get(conn, "/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      response = json_response(conn, :unauthorized)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 404 when project is not accessible", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 404, "Unauthorized or not found"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> get("/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      response = json_response(conn, :not_found)
      assert response["message"] == "Unauthorized or not found"
    end

    test "returns not found when store absorbs read-through contention as a miss", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "busy_cas_id"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(KeyValueStore, :get_key_value, fn ^cas_id, ^account_handle, ^project_handle ->
        {:error, :not_found}
      end)

      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get("/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")
      |> json_response(:not_found)
    end
  end

  describe "PUT /api/cache/keyvalue" do
    test "stores cache value successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id_123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      entries = [
        %{"value" => "test_value_1"},
        %{"value" => "test_value_2"}
      ]

      body = %{
        "cas_id" => cas_id,
        "entries" => entries
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      assert conn.status == 204
      assert conn.resp_body == ""

      {:ok, stored_json} = KeyValueStore.get_key_value(cas_id, account_handle, project_handle)
      stored_response = JSON.decode!(stored_json)

      assert stored_response["entries"] == [
               %{"value" => "test_value_1"},
               %{"value" => "test_value_2"}
             ]
    end

    test "returns 408 when request body read times out during JSON parsing", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      reject(KeyValueStore, :put_key_value, 4)

      expect(Plug.Conn, :read_body, fn _conn, _opts ->
        raise Bandit.TransportError, message: "Request body read timed out", error: :timeout
      end)

      capture_log(fn ->
        assert_error_sent 408, fn ->
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/json")
          |> put(
            "/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}",
            ~s({"cas_id":"test_cas_id_123","entries":[{"value":"test_value_1"}]})
          )
        end
      end)
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      body = %{
        "cas_id" => "test_cas_id",
        "entries" => [%{"value" => "test_value"}]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      response = json_response(conn, :unauthorized)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 404 when project is not accessible", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 404, "Unauthorized or not found"}
      end)

      body = %{
        "cas_id" => "test_cas_id",
        "entries" => [%{"value" => "test_value"}]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      response = json_response(conn, :not_found)
      assert response["message"] == "Unauthorized or not found"
    end
  end
end
