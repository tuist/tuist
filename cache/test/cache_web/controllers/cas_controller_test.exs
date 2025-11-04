defmodule CacheWeb.CASControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.Disk

  describe "GET /auth/cas" do
    test "returns 204 when project is accessible", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/auth/cas?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns error status when authentication fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        get(conn, "/auth/cas?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 401
      assert conn.resp_body == ""
    end

    test "returns 404 when project is not found", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 404, "Unauthorized or not found"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> get("/auth/cas?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 400 when account_handle is missing", %{conn: conn} do
      conn = get(conn, "/auth/cas?project_handle=test-project")

      assert conn.status == 400
      assert conn.resp_body == ""
    end

    test "returns 400 when project_handle is missing", %{conn: conn} do
      conn = get(conn, "/auth/cas?account_handle=test-account")

      assert conn.status == 400
      assert conn.resp_body == ""
    end

    test "returns 400 when account_handle is empty", %{conn: conn} do
      conn = get(conn, "/auth/cas?account_handle=&project_handle=test-project")

      assert conn.status == 400
      assert conn.resp_body == ""
    end

    test "returns 400 when project_handle is empty", %{conn: conn} do
      conn = get(conn, "/auth/cas?account_handle=test-account&project_handle=")

      assert conn.status == 400
      assert conn.resp_body == ""
    end
  end

  describe "POST /api/cache/cas/:id" do
    test "saves artifact successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{id}"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:exists?, fn ^expected_key ->
        false
      end)
      |> expect(:put, fn ^expected_key, ^body ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "streams large artifact to temporary file", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{id}"
      large_body = :binary.copy("0123456789abcdef", 150_000)

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:exists?, fn ^expected_key ->
        false
      end)
      |> expect(:put, fn ^expected_key, {:file, tmp_path} ->
        assert File.exists?(tmp_path)
        assert File.stat!(tmp_path).size == byte_size(large_body)
        File.rm(tmp_path)
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", large_body)

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "skips save when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{id}"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:exists?, fn ^expected_key ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 500 when disk write fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{id}"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:exists?, fn ^expected_key ->
        false
      end)
      |> expect(:put, fn ^expected_key, ^body ->
        {:error, :enospc}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

        assert conn.status == 500
        response = json_response(conn, 500)
        assert response["message"] == "Failed to persist artifact"
      end)
    end

    test "treats put_file exists error as success", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{id}"
      large_body = :binary.copy("0123456789abcdef", 150_000)

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:exists?, fn ^expected_key ->
        false
      end)
      |> expect(:put, fn ^expected_key, {:file, tmp_path} ->
        assert File.exists?(tmp_path)
        File.rm(tmp_path)
        {:error, :exists}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", large_body)

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", "body")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 404 when project is not accessible", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      Authentication
      |> expect(:ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 404, "Unauthorized or not found"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", "body")

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["message"] == "Unauthorized or not found"
    end
  end
end
