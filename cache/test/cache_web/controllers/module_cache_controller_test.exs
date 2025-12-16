defmodule CacheWeb.ModuleCacheControllerTest do
  use CacheWeb.ConnCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.Repo
  alias Cache.S3
  alias Cache.S3Transfer

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    stub(Disk, :storage_dir, fn -> test_storage_dir end)

    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "POST /api/cache/module (upload)" do
    test "saves artifact successfully when authenticated", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        false
      end)
      |> expect(:module_put, fn "test-account", "test-project", "builds", ^hash, ^name, ^body ->
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post(
            "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}",
            body
          )

        assert conn.status == 204
        assert conn.resp_body == ""
      end)

      # Verify S3 upload was enqueued via S3Transfers table
      transfer = Repo.one(S3Transfer)
      assert transfer.type == :upload
      assert transfer.account_handle == "test-account"
      assert transfer.project_handle == "test-project"
      assert transfer.artifact_id == CacheArtifacts.encode_module("builds", hash, name)
    end

    test "returns 204 when artifact already exists", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}",
          body
        )

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 500 when disk write fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      body = "test artifact content"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:module_exists?, fn "test-account", "test-project", "builds", ^hash, ^name ->
        false
      end)
      |> expect(:module_put, fn "test-account", "test-project", "builds", ^hash, ^name, ^body ->
        {:error, :enospc}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post(
            "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}",
            body
          )

        assert conn.status == 500
        response = json_response(conn, 500)
        assert response["message"] == "Failed to persist artifact"
      end)
    end

    test "uses cache_category parameter when provided", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      body = "test artifact content"
      category = "custom_category"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      Disk
      |> expect(:module_exists?, fn "test-account", "test-project", ^category, ^hash, ^name ->
        false
      end)
      |> expect(:module_put, fn "test-account", "test-project", ^category, ^hash, ^name, ^body ->
        :ok
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> put_req_header("content-type", "application/octet-stream")
          |> post(
            "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}&cache_category=#{category}",
            body
          )

        assert conn.status == 204
      end)
    end
  end

  describe "GET /api/cache/module (download)" do
    test "returns X-Accel-Redirect to local file when on disk", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"

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
          "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
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
          "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
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
      assert transfer.artifact_id == CacheArtifacts.encode_module("builds", hash, name)
    end

    test "returns 404 when S3 presign fails", %{conn: conn} do
      account_handle = "test-account"
      project_handle = "test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"

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
            "/api/cache/module?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
          )

        assert conn.status == 404
      end)
    end
  end

  describe "GET /api/cache/module/exists" do
    test "returns 204 when artifact exists on disk", %{conn: conn} do
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
        |> get(
          "/api/cache/module/exists?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 204
    end

    test "returns 204 when artifact exists in S3", %{conn: conn} do
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

      expect(S3, :exists?, fn key ->
        assert key == "test-account/test-project/module/builds/ab/c1/#{hash}/#{name}"
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get(
          "/api/cache/module/exists?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 204
    end

    test "returns 404 when artifact doesn't exist", %{conn: conn} do
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

      expect(S3, :exists?, fn _key ->
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get(
          "/api/cache/module/exists?account_handle=#{account_handle}&project_handle=#{project_handle}&hash=#{hash}&name=#{name}"
        )

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["message"] == "Artifact not found"
    end
  end
end
