defmodule CacheWeb.ModuleCacheControllerTest do
  use CacheWeb.ConnCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.MultipartUploads
  alias Cache.Repo
  alias Cache.S3
  alias Cache.S3Transfer

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    stub(Disk, :storage_dir, fn -> test_storage_dir end)

    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "GET /api/cache/module/:id (download)" do
    test "returns X-Accel-Redirect to local file when on disk", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_stat, fn "test-account", "test-project", "builds", ^hash, ^name ->
        {:ok, %File.Stat{size: 1024, type: :regular}}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn key ->
        assert key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get(
          "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
             ]

      assert conn.resp_body == ""
    end

    test "returns X-Accel-Redirect to remote when not on disk", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_stat, fn "test-account", "test-project", "builds", ^hash, ^name ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn _key ->
        :ok
      end)

      expect(S3, :exists?, fn key ->
        assert key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
        true
      end)

      expect(S3, :presign_download_url, fn key ->
        assert key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
        {:ok, "https://example.com/bucket/#{key}?token=abc"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get(
          "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 200

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/remote/https/example.com/bucket/test-account/test-project/module/builds/ab/c1/#{hash}/#{name}?token=abc"
             ]

      # Verify S3 download was enqueued via S3Transfers table
      transfer = Repo.one(S3Transfer)
      assert transfer.type == :download
      assert transfer.account_handle == "test-account"
      assert transfer.project_handle == "test-project"
      assert transfer.artifact_type == :module
      assert transfer.key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
    end

    test "returns 404 when S3 presign fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_stat, fn "test-account", "test-project", "builds", ^hash, ^name ->
        {:error, :enoent}
      end)

      expect(CacheArtifacts, :track_artifact_access, fn _key ->
        :ok
      end)

      expect(S3, :exists?, fn _key ->
        true
      end)

      expect(S3, :presign_download_url, fn _key ->
        {:error, "S3 error"}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> get(
            "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
          )

        assert conn.status == 404
      end)
    end
  end

  describe "HEAD /api/cache/module/:id (exists)" do
    test "returns 204 when artifact exists on disk", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> head(
          "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 204
    end

    test "returns 204 when artifact exists in S3", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        false
      end)

      expect(S3, :exists?, fn key ->
        assert key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> head(
          "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 204
    end

    test "returns 404 when artifact doesn't exist", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      artifact_id = "some-artifact-id"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        false
      end)

      expect(S3, :exists?, fn _key ->
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> head(
          "/api/cache/module/#{artifact_id}?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 404
    end
  end

  describe "POST /api/cache/module/start (start_multipart)" do
    test "returns upload_id when artifact doesn't exist", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post(
          "/api/cache/module/start?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 200
      response = json_response(conn, 200)
      assert is_binary(response["upload_id"])
      assert String.length(response["upload_id"]) == 36
    end

    test "returns null upload_id when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post(
          "/api/cache/module/start?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["upload_id"] == nil
    end

    test "uses cache_category parameter when provided", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      category = "custom_category"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", ^category, ^hash, ^name ->
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post(
          "/api/cache/module/start?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}&cache_category=#{category}"
        )

      assert conn.status == 200
      response = json_response(conn, 200)
      assert is_binary(response["upload_id"])
    end
  end

  describe "POST /api/cache/module/part (upload_part)" do
    test "uploads part successfully", %{conn: conn} do
      {:ok, upload_id} = MultipartUploads.start_upload("test-account", "test-project", "builds", "abc123", "test.zip")
      body = String.duplicate("x", 1000)

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          "/api/cache/module/part?account_handle=test-account&project_handle=test-project&upload_id=#{upload_id}&part_number=1",
          body
        )

      assert conn.status == 204

      {:ok, upload} = MultipartUploads.get_upload(upload_id)
      assert Map.has_key?(upload.parts, 1)
      assert upload.parts[1].size == 1000
    end

    test "returns 404 for unknown upload_id", %{conn: conn} do
      body = String.duplicate("x", 1000)

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          "/api/cache/module/part?account_handle=test-account&project_handle=test-project&upload_id=nonexistent&part_number=1",
          body
        )

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["message"] == "Artifact not found"
    end
  end

  describe "POST /api/cache/module/complete (complete_multipart)" do
    test "completes upload successfully", %{conn: conn} do
      hash = "abc123"
      name = "test.zip"
      {:ok, upload_id} = MultipartUploads.start_upload("test-account", "test-project", "builds", hash, name)

      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "test content")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 12)

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_put_from_parts, fn "test-account", "test-project", "builds", ^hash, ^name, [^tmp_path] ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/module/complete?account_handle=test-account&project_handle=test-project&upload_id=#{upload_id}",
          Jason.encode!(%{parts: [1]})
        )

      assert conn.status == 204

      # Upload should be removed from state after completion
      assert {:error, :not_found} = MultipartUploads.get_upload(upload_id)

      # Verify S3 upload was enqueued via S3Transfers table
      transfer = Repo.one(S3Transfer)
      assert transfer.type == :upload
      assert transfer.account_handle == "test-account"
      assert transfer.project_handle == "test-project"
      assert transfer.artifact_type == :module
      assert transfer.key == "test-account/test-project/module/builds/ab/c1/abc123/test.zip"
    end

    test "returns 404 for unknown upload_id", %{conn: conn} do
      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/module/complete?account_handle=test-account&project_handle=test-project&upload_id=nonexistent",
          Jason.encode!(%{parts: [1]})
        )

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["message"] == "Artifact not found"
    end

    test "returns 400 when parts don't match", %{conn: conn} do
      {:ok, upload_id} = MultipartUploads.start_upload("test-account", "test-project", "builds", "abc123", "test.zip")

      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "test content")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 12)

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/module/complete?account_handle=test-account&project_handle=test-project&upload_id=#{upload_id}",
          Jason.encode!(%{parts: [1, 2]})
        )

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["message"] == "Parts mismatch or missing parts"

      File.rm(tmp_path)
    end

    test "assembles multiple parts in order", %{conn: conn} do
      hash = "xyz789"
      name = "multi.zip"
      {:ok, upload_id} = MultipartUploads.start_upload("test-account", "test-project", "builds", hash, name)

      tmp_path1 = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      tmp_path2 = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      tmp_path3 = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")

      File.write!(tmp_path1, "PART1")
      File.write!(tmp_path2, "PART2")
      File.write!(tmp_path3, "PART3")

      MultipartUploads.add_part(upload_id, 1, tmp_path1, 5)
      MultipartUploads.add_part(upload_id, 2, tmp_path2, 5)
      MultipartUploads.add_part(upload_id, 3, tmp_path3, 5)

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_put_from_parts, fn "test-account", "test-project", "builds", ^hash, ^name, part_paths ->
        assert part_paths == [tmp_path1, tmp_path2, tmp_path3]
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/module/complete?account_handle=test-account&project_handle=test-project&upload_id=#{upload_id}",
          Jason.encode!(%{parts: [1, 2, 3]})
        )

      assert conn.status == 204
    end
  end
end
