defmodule CacheWeb.CasControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  alias Cache.Storage

  setup :verify_on_exit!

  # GET reads are now served directly by nginx via auth_request

  describe "POST /api/projects/:account/:project/cache/cas/:id" do
    test "stores object successfully", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id"
      body = "test binary content"

      expect(Storage, :object_exists?, fn ^cas_id, ^account_handle, ^project_handle ->
        false
      end)

      expect(Storage, :put_object, fn ^cas_id, ^account_handle, ^project_handle, ^body, opts ->
        assert opts[:content_type] == "application/octet-stream"
        :ok
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 204 when object already exists", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id"
      body = "test binary content"

      expect(Storage, :object_exists?, fn ^cas_id, ^account_handle, ^project_handle ->
        true
      end)

      # Storage.put_object should not be called

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 500 on S3 error", %{conn: conn} do
      # Given
      account_handle = "test-account"
      project_handle = "test-project"
      cas_id = "test_cas_id"
      body = "test binary content"

      expect(Storage, :object_exists?, fn ^cas_id, ^account_handle, ^project_handle ->
        false
      end)

      expect(Storage, :put_object, fn ^cas_id, ^account_handle, ^project_handle, ^body, _opts ->
        {:error, :s3_error}
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      # Then
      response = json_response(conn, :internal_server_error)
      assert response["message"] == "S3 error"
    end
  end
end
