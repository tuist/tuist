defmodule CacheWeb.KeyValueControllerTest do
  use CacheWeb.ConnCase

  alias Cache.KeyValueStore

  describe "GET /api/projects/:account/:project/cache/keyvalue/:cas_id" do
    test "gets cache value successfully", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id_123"

      # Store values directly
      :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, ["value1", "value2"])

      # When
      conn =
        get(conn, "/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      response = json_response(conn, :ok)

      assert response["entries"] == [
               %{"value" => "value1"},
               %{"value" => "value2"}
             ]
    end

    test "returns not found when no entries exist", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "nonexistent_cas_id"

      # When
      conn =
        get(conn, "/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "No entries found for CAS ID #{cas_id}."
    end
  end

  describe "PUT /api/projects/:account/:project/cache/keyvalue" do
    test "stores cache value successfully", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id_123"

      entries = [
        %{"value" => "test_value_1"},
        %{"value" => "test_value_2"}
      ]

      body = %{
        "cas_id" => cas_id,
        "entries" => entries
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""

      # Verify values were stored
      stored_values = KeyValueStore.get_key_value(cas_id, account_handle, project_handle)
      assert stored_values == ["test_value_1", "test_value_2"]
    end

    test "returns 400 when cas_id is missing", %{conn: conn} do
      # Given
      body = %{
        "entries" => [%{"value" => "test_value"}]
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=test-account&project_handle=test-project", body)

      # Then
      assert conn.status == 400
    end

    test "returns 400 when entries is not an array", %{conn: conn} do
      # Given
      body = %{
        "cas_id" => "test_cas_id",
        "entries" => "not-an-array"
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=test-account&project_handle=test-project", body)

      # Then
      assert conn.status == 400
    end

    test "returns 400 when entries is empty", %{conn: conn} do
      # Given
      body = %{
        "cas_id" => "test_cas_id",
        "entries" => []
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/cache/keyvalue?account_handle=test-account&project_handle=test-project", body)

      # Then
      assert conn.status == 400
    end
  end
end
