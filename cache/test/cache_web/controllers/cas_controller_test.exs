defmodule CacheWeb.CASControllerTest do
  use CacheWeb.ConnCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.S3Transfers

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    stub(Disk, :storage_dir, fn -> test_storage_dir end)

    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "POST /api/cache/cas/:id" do
    test "saves artifact successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:cas_exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:cas_put, fn ^account_handle, ^project_handle, ^id, ^body ->
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

        assert conn.status == 204
        assert conn.resp_body == ""
      end)

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :cas
      assert upload.key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
    end

    test "streams large artifact to temporary file", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      large_body = :binary.copy("0123456789abcdef", 150_000)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:cas_exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:cas_put, fn ^account_handle, ^project_handle, ^id, {:file, tmp_path} ->
        assert File.exists?(tmp_path)
        assert File.stat!(tmp_path).size == byte_size(large_body)
        File.rm(tmp_path)
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
          |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", large_body)

        assert conn.status == 204
        assert conn.resp_body == ""
      end)

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :cas
      assert upload.key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
    end

    test "skips save when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :cas_exists?, fn ^account_handle, ^project_handle, ^id ->
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

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:cas_exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:cas_put, fn ^account_handle, ^project_handle, ^id, ^body ->
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
      large_body = :binary.copy("0123456789abcdef", 150_000)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:cas_exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:cas_put, fn ^account_handle, ^project_handle, ^id, {:file, tmp_path} ->
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

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
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

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
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

  describe "GET /api/cache/cas/*id" do
    test "returns X-Accel-Redirect to local file when on disk", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :cas_stat, fn ^account_handle, ^project_handle, ^id ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
             ]

      assert conn.resp_body == ""
    end

    test "returns X-Accel-Redirect to remote when not on disk and S3 presign succeeds", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :cas_stat, fn ^account_handle, ^project_handle, ^id ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
        :ok
      end)

      # Stub presign to return a deterministic URL
      expect(Cache.S3, :presign_download_url, fn key ->
        assert key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
        {:ok, "https://example.com/prefix/#{account_handle}/#{project_handle}/cas/ab/c1/#{id}?token=abc"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/remote/https/example.com/prefix/#{account_handle}/#{project_handle}/cas/ab/c1/#{id}?token=abc"
             ]

      assert conn.resp_body == ""
    end

    test "returns 404 when S3 presign fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :cas_stat, fn ^account_handle, ^project_handle, ^id ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
        :ok
      end)

      expect(Cache.S3, :presign_download_url, fn key ->
        assert key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
        {:ok, "https://example.com/prefix/#{account_handle}/#{project_handle}/cas/ab/c1/#{id}?token=abc"}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

        assert conn.status == 200

        assert get_resp_header(conn, "x-accel-redirect") == [
                 "/internal/remote/https/example.com/prefix/#{account_handle}/#{project_handle}/cas/ab/c1/#{id}?token=abc"
               ]

        assert conn.resp_body == ""
      end)

      downloads = S3Transfers.pending(:download, 10)
      assert length(downloads) == 1
      download = hd(downloads)
      assert download.type == :download
      assert download.account_handle == account_handle
      assert download.project_handle == project_handle
      assert download.artifact_type == :cas
      assert download.key == "#{account_handle}/#{project_handle}/cas/ab/c1/#{id}"
    end

    test "returns 401 when authentication fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn = get(conn, "/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 401 when account_handle is missing", %{conn: conn} do
      conn = get(conn, "/api/cache/cas/abc123?project_handle=test-project")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 401 when project_handle is missing", %{conn: conn} do
      conn = get(conn, "/api/cache/cas/abc123?account_handle=test-account")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end
  end
end
