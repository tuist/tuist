defmodule CacheWeb.GradleControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Plug.Conn

  alias Cache.Authentication
  alias Cache.Gradle
  alias Cache.S3
  alias Cache.S3Transfers
  alias Ecto.Adapters.SQL.Sandbox

  @endpoint CacheWeb.Endpoint

  setup :set_mimic_from_context

  setup context do
    :ok = Sandbox.checkout(Cache.Repo)

    context = Cache.BufferTestHelpers.setup_s3_transfers_buffer(context)

    {:ok, test_storage_dir} = Briefly.create(directory: true)

    Cache.Disk
    |> stub(:storage_dir, fn -> test_storage_dir end)
    |> stub(:artifact_path, fn key -> Path.join(test_storage_dir, key) end)

    stub(Authentication, :server_url, fn -> "http://localhost:4000" end)

    {:ok, Map.merge(context, %{conn: build_conn(), test_storage_dir: test_storage_dir})}
  end

  describe "PUT /api/cache/gradle/:cache_key" do
    test "saves artifact successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      body = "test artifact content"
      key = "#{account_handle}/#{project_handle}/gradle/ab/c1/#{cache_key}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :cache
        send(test_pid, {:s3_exists_checked, self()})
        false
      end)

      Gradle.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^cache_key, ^body ->
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> put_req_header("content-length", Integer.to_string(byte_size(body)))
          |> put(
            "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
            body
          )

        assert conn.status == 201
        assert conn.resp_body == ""
      end)

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = Cache.S3TransfersBuffer.flush()

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :gradle
      assert upload.key == key
    end

    test "streams large artifact to temp file on same filesystem as storage", %{
      conn: conn,
      test_storage_dir: test_storage_dir
    } do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      large_body = :binary.copy("0123456789abcdef", 150_000)
      key = "#{account_handle}/#{project_handle}/gradle/ab/c1/#{cache_key}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :cache
        send(test_pid, {:s3_exists_checked, self()})
        false
      end)

      Gradle.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^cache_key, {:file, tmp_path} ->
        assert File.exists?(tmp_path)
        assert File.stat!(tmp_path).size == byte_size(large_body)

        assert String.starts_with?(tmp_path, test_storage_dir),
               "Expected temp file #{tmp_path} to be under storage dir #{test_storage_dir}"

        File.rm(tmp_path)
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> put_req_header("content-length", Integer.to_string(byte_size(large_body)))
          |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
          |> put(
            "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
            large_body
          )

        assert conn.status == 201
        assert conn.resp_body == ""
      end)

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = Cache.S3TransfersBuffer.flush()

      uploads = S3Transfers.pending(:upload, 10)
      assert length(uploads) == 1
      upload = hd(uploads)
      assert upload.type == :upload
      assert upload.account_handle == account_handle
      assert upload.project_handle == project_handle
      assert upload.artifact_type == :gradle
      assert upload.key == key
    end

    test "does not enqueue upload when Gradle artifact already exists in S3", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      body = "test artifact content"
      key = "#{account_handle}/#{project_handle}/gradle/ab/c1/#{cache_key}"
      test_pid = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :exists?, fn ^key, opts ->
        assert Keyword.get(opts, :type) == :cache
        send(test_pid, {:s3_exists_checked, self()})
        true
      end)

      Gradle.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^cache_key, ^body ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          body
        )

      assert conn.status == 201
      assert conn.resp_body == ""

      assert_receive {:s3_exists_checked, task_pid}, 1_000
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
      assert reason in [:normal, :noproc]

      :ok = Cache.S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "returns timeout instead of acknowledging a chunked upload timeout as success", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      chunk = String.duplicate("x", 200_000)
      call_count = :counters.new(1, [])

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Gradle.Disk, :exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)

      reject(Gradle.Disk, :put, 4)

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
          |> put_req_header("content-length", Integer.to_string(byte_size(chunk)))
          |> put(
            "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
            chunk
          )

        assert conn.status == 408
        response = json_response(conn, 408)
        assert response["message"] == "Request body read timed out"
      end)

      :ok = Cache.S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "rejects uploads without a Content-Length header with 411", %{conn: conn} do
      # Without Content-Length the server cannot verify the body arrived
      # whole, so the truncation check in Cache.BodyReader would be a
      # no-op. Reject such requests before any persistence happens.
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"

      reject(Gradle.Disk, :exists?, 3)
      reject(Gradle.Disk, :put, 4)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("transfer-encoding", "chunked")
        |> Map.update!(:req_headers, fn headers ->
          Enum.reject(headers, fn {name, _} -> name == "content-length" end)
        end)
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          "whatever"
        )

      assert conn.status == 411

      response = json_response(conn, 411)

      assert response["message"] ==
               "PUT /api/cache/gradle/:cache_key requires a Content-Length header"

      :ok = Cache.S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "rejects truncated uploads without persisting the partial body", %{conn: conn} do
      # Regression test for a class of bug where a client disconnect mid-PUT
      # produced an `{:ok, partial, conn}` result from the HTTP adapter. The
      # partial bytes were previously persisted as a complete cache entry
      # and served back with `200 OK` on every subsequent download, causing
      # clients to fail deep inside their snapshot parsers with null-message
      # errors. The reader must now reject the request before anything is
      # written to disk.
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      partial_chunk = String.duplicate("x", 512)
      declared_length = 10_000

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Gradle.Disk, :exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)

      reject(Gradle.Disk, :put, 4)

      expect(Plug.Conn, :read_body, fn conn, _opts ->
        {:ok, partial_chunk, conn}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("content-length", Integer.to_string(declared_length))
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          partial_chunk
        )

      assert conn.status == 400

      response = json_response(conn, 400)

      assert response["message"] ==
               "Request body was truncated before reaching the declared Content-Length"

      :ok = Cache.S3TransfersBuffer.flush()
      assert S3Transfers.pending(:upload, 10) == []
    end

    test "skips save when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Gradle.Disk, :exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          body
        )

      assert conn.status == 200
      assert conn.resp_body == ""
    end

    test "skips save for large duplicate uploads without returning 500", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      body = :binary.copy("0123456789abcdef", 20_000)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Gradle.Disk, :exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        true
      end)

      reject(Gradle.Disk, :put, 4)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          body
        )

      assert conn.status == 200
      assert conn.resp_body == ""
    end

    test "returns 500 when disk write fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Gradle.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^cache_key, ^body ->
        {:error, :enospc}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> put_req_header("content-length", Integer.to_string(byte_size(body)))
          |> put(
            "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
            body
          )

        assert conn.status == 500
        response = json_response(conn, 500)
        assert response["message"] == "Failed to persist artifact"
      end)
    end

    test "treats put_file exists error as success", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"
      large_body = :binary.copy("0123456789abcdef", 150_000)

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      Gradle.Disk
      |> expect(:exists?, fn ^account_handle, ^project_handle, ^cache_key ->
        false
      end)
      |> expect(:put, fn ^account_handle, ^project_handle, ^cache_key, {:file, tmp_path} ->
        assert File.exists?(tmp_path)
        File.rm(tmp_path)
        {:error, :exists}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put_req_header("content-length", Integer.to_string(byte_size(large_body)))
        |> Plug.Conn.put_private(:body_read_opts, length: 128_000, read_length: 128_000, read_timeout: 60_000)
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          large_body
        )

      assert conn.status == 200
      assert conn.resp_body == ""
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          "body"
        )

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end

    test "returns 404 when project is not accessible", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      cache_key = "abc123"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:error, 404, "Unauthorized or not found"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> put(
          "/api/cache/gradle/#{cache_key}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          "body"
        )

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
        |> put("/api/cache/gradle/..?account_handle=#{account_handle}&project_handle=#{project_handle}", "body")

      assert conn.status == 422

      response = json_response(conn, 422)

      assert %{
               "errors" => [
                 %{
                   "title" => "Invalid value",
                   "source" => %{"pointer" => "/cache_key"},
                   "detail" => detail
                 }
               ]
             } = response

      assert is_binary(detail)
    end
  end
end
