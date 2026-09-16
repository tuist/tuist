defmodule CacheWeb.XcodeControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.CacheArtifacts
  alias Cache.S3
  alias Cache.S3Transfers
  alias Cache.S3TransfersBuffer
  alias Cache.Xcode

  setup :set_mimic_from_context

  setup context do
    context = Cache.BufferTestHelpers.setup_s3_transfers_buffer(context)

    {:ok, test_storage_dir} = Briefly.create(directory: true)
    stub(Cache.Disk, :storage_dir, fn -> test_storage_dir end)
    stub(Authentication, :server_url, fn -> "http://localhost:4000" end)

    {:ok, Map.put(context, :test_storage_dir, test_storage_dir)}
  end

  describe "POST /api/cache/cas/:id" do
    test "saves artifact successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :xcode_cache
        send(test_pid, {:s3_exists_checked, self()})
        false
      end)

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, ^body ->
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

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = S3TransfersBuffer.flush()

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :xcode_cache
      assert upload.key == key
    end

    test "tracks artifact access but skips the S3 upload enqueue when Xcode database interactions are disabled", %{
      conn: conn
    } do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      stub(Cache.Config, :xcode_database_interactions_enabled?, fn -> false end)
      expect(CacheArtifacts, :record_content_sha256, fn ^key, nil -> :ok end)
      reject(S3Transfers, :enqueue_upload_if_missing, 4)

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, ^body ->
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
      large_body = :binary.copy("0123456789abcdef", 150_000)
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :xcode_cache
        send(test_pid, {:s3_exists_checked, self()})
        false
      end)

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, {:file, tmp_path} ->
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

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = S3TransfersBuffer.flush()

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :xcode_cache
      assert upload.key == key
    end

    test "does not enqueue upload when artifact already exists in S3", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :xcode_cache
        send(test_pid, {:s3_exists_checked, self()})
        true
      end)

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, ^body ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", body)

      assert conn.status == 204
      assert conn.resp_body == ""

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "returns timeout instead of acknowledging a chunked upload timeout as success", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      chunk = String.duplicate("x", 200_000)
      call_count = :counters.new(1, [])

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Xcode.Disk, :exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)

      reject(Xcode.Disk, :put, 4)

      expect(Plug.Conn, :read_body, 2, fn conn, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:more, chunk, conn}
        else
          raise Bandit.TransportError, message: "Request body read timed out", error: :timeout
        end
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}", chunk)

        assert conn.status == 408
        response = json_response(conn, 408)
        assert response["message"] == "Request body read timed out"
      end)

      :ok = S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "skips save when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Xcode.Disk, :exists?, fn ^account_handle, ^project_handle, ^id ->
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

    test "skips save for large duplicate uploads without returning 500", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      body = :binary.copy("0123456789abcdef", 20_000)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Xcode.Disk, :exists?, fn ^account_handle, ^project_handle, ^id ->
        true
      end)

      reject(Xcode.Disk, :put, 4)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
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

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, ^body ->
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

      Xcode.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^id ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^id, {:file, tmp_path} ->
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

    test "returns 422 when path params contain traversal", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/cache/cas/..?account_handle=#{account_handle}&project_handle=#{project_handle}", "body")

      assert conn.status == 422

      response = json_response(conn, 422)

      assert %{
               "errors" => [
                 %{
                   "title" => "Invalid value",
                   "source" => %{"pointer" => "/id"},
                   "detail" => detail
                 }
               ]
             } = response

      assert is_binary(detail)
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

      expect(Xcode.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
             ]

      assert conn.resp_body == ""
    end

    # Deliberately mock-identical to the flag-on local-hit test above: it pins
    # that tracking stays ungated when the flag is off, which is the regression
    # #12252 fixed. Do not remove it as a duplicate.
    test "tracks artifact access when serving a local file with Xcode database interactions disabled", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      stub(Cache.Config, :xcode_database_interactions_enabled?, fn -> false end)
      expect(CacheArtifacts, :track_artifact_access, fn ^key -> :ok end)

      expect(Xcode.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
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

      expect(Xcode.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        :ok
      end)

      expect(S3, :presign_download_url, fn key, opts ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        assert Keyword.get(opts, :type) == :xcode_cache
        {:ok, "https://example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/remote/https/example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"
             ]

      assert conn.resp_body == ""
    end

    test "tracks artifact access but skips the S3 download enqueue when Xcode database interactions are disabled", %{
      conn: conn
    } do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"
      key = "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      stub(Cache.Config, :xcode_database_interactions_enabled?, fn -> false end)
      expect(CacheArtifacts, :track_artifact_access, fn ^key -> :ok end)
      reject(S3Transfers, :enqueue_xcode_download, 3)

      expect(Xcode.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:error, :enoent}
      end)

      expect(S3, :presign_download_url, fn key, opts ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        assert Keyword.get(opts, :type) == :xcode_cache
        {:ok, "https://example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/remote/https/example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"
             ]

      assert conn.resp_body == ""
    end

    test "enqueues S3 download transfer when serving from remote", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      id = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Xcode.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        :ok
      end)

      expect(S3, :presign_download_url, fn key, opts ->
        assert key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
        assert Keyword.get(opts, :type) == :xcode_cache
        {:ok, "https://example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> get("/api/cache/cas/#{id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

        assert conn.status == 200

        assert get_resp_header(conn, "x-accel-redirect") == [
                 "/internal/remote/https/example.com/prefix/#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}?token=abc"
               ]

        assert conn.resp_body == ""
      end)

      :ok = S3TransfersBuffer.flush()

      downloads = S3Transfers.pending(:download, 10)
      assert length(downloads) == 1
      download = hd(downloads)
      assert download.type == :download
      assert download.account_handle == account_handle
      assert download.project_handle == project_handle
      assert download.artifact_type == :xcode_cache
      assert download.key == "#{account_handle}/#{project_handle}/xcode/ab/c1/#{id}"
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

  describe "tuist-checksum-sha256" do
    setup do
      stub(Cache.Config, :xcode_database_interactions_enabled?, fn -> false end)

      stub(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      test_pid = self()

      stub(CacheArtifacts, :record_content_sha256, fn key, digest ->
        send(test_pid, {:recorded, key, digest})
        :ok
      end)

      :ok
    end

    test "stores the digest an upload declares when the body matches it", %{conn: conn} do
      body = "test artifact content"
      digest = sha256(body)

      Xcode.Disk
      |> expect(:exists?, fn "test-account", "test-project", "abc123" -> false end)
      |> expect(:put, fn "test-account", "test-project", "abc123", ^body -> :ok end)

      conn = save_artifact(conn, body, digest)

      assert conn.status == 204
      assert_received {:recorded, "test-account/test-project/xcode/ab/c1/abc123", ^digest}
    end

    test "clears the recorded digest when an upload declares none", %{conn: conn} do
      body = "test artifact content"

      Xcode.Disk
      |> expect(:exists?, fn "test-account", "test-project", "abc123" -> false end)
      |> expect(:put, fn "test-account", "test-project", "abc123", ^body -> :ok end)

      conn = save_artifact(conn, body, nil)

      assert conn.status == 204
      assert_received {:recorded, "test-account/test-project/xcode/ab/c1/abc123", nil}
    end

    test "refuses a body that does not match its declared digest without persisting it", %{conn: conn} do
      expect(Xcode.Disk, :exists?, fn "test-account", "test-project", "abc123" -> false end)
      reject(&Xcode.Disk.put/4)

      conn = save_artifact(conn, "test artifact content", sha256("other content"))

      assert json_response(conn, 422)["message"] =~ "does not match tuist-checksum-sha256"
      refute_received {:recorded, _key, _digest}
    end

    test "removes a large body streamed to disk when it does not match its declared digest", %{
      conn: conn,
      test_storage_dir: test_storage_dir
    } do
      large_body = :binary.copy("0123456789abcdef", 150_000)
      expect(Xcode.Disk, :exists?, fn "test-account", "test-project", "abc123" -> false end)
      reject(&Xcode.Disk.put/4)

      conn =
        conn
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
        |> save_artifact(large_body, sha256("other content"))

      assert json_response(conn, 422)["message"] =~ "does not match tuist-checksum-sha256"
      assert Path.wildcard(Path.join(test_storage_dir, "**/.cache-upload-*"), match_dot: true) == []
    end

    test "rejects a malformed declared digest before reading the body", %{conn: conn} do
      reject(&Xcode.Disk.exists?/3)
      reject(&Xcode.Disk.put/4)

      conn = save_artifact(conn, "test artifact content", "not-a-digest")

      assert json_response(conn, 400)["message"] == "tuist-checksum-sha256 must be 64 hex characters"
    end

    test "does not check an upload against its digest when the artifact already exists", %{conn: conn} do
      expect(Xcode.Disk, :exists?, fn "test-account", "test-project", "abc123" -> true end)
      reject(&Xcode.Disk.put/4)

      conn = save_artifact(conn, "test artifact content", sha256("other content"))

      assert conn.status == 204
    end

    test "serves the recorded digest with a local file", %{conn: conn} do
      digest = sha256("test artifact content")
      stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
      stub(CacheArtifacts, :content_sha256, fn "test-account/test-project/xcode/ab/c1/abc123" -> digest end)

      expect(Xcode.Disk, :stat, fn "test-account", "test-project", "abc123" ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      conn = download_artifact(conn)

      assert conn.status == 200
      assert get_resp_header(conn, "tuist-checksum-sha256") == [digest]
    end

    test "serves no digest with a local file that has none", %{conn: conn} do
      stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
      stub(CacheArtifacts, :content_sha256, fn _key -> nil end)

      expect(Xcode.Disk, :stat, fn "test-account", "test-project", "abc123" ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      conn = download_artifact(conn)

      assert conn.status == 200
      assert get_resp_header(conn, "tuist-checksum-sha256") == []
    end
  end

  defp save_artifact(conn, body, checksum_sha256) do
    conn
    |> put_req_header("authorization", "Bearer valid-token")
    |> put_req_header("content-type", "application/octet-stream")
    |> then(&if(checksum_sha256, do: put_req_header(&1, "tuist-checksum-sha256", checksum_sha256), else: &1))
    |> post("/api/cache/cas/abc123?account_handle=test-account&project_handle=test-project", body)
  end

  defp download_artifact(conn) do
    conn
    |> put_req_header("authorization", "Bearer valid-token")
    |> get("/api/cache/cas/abc123?account_handle=test-account&project_handle=test-project")
  end

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)
end
