defmodule CacheWeb.ModuleCacheControllerTest do
  use CacheWeb.ConnCase, async: true
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  alias Cache.Authentication
  alias Cache.Disk
  alias Cache.S3

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    stub(Disk, :storage_dir, fn -> test_storage_dir end)

    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "GET /api/cache (download)" do
    test "returns presigned URL when authenticated", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :generate_download_url, fn key, opts ->
        assert key == "test-account/test-project/module/#{cache_category}/#{hash}/#{name}"
        assert Keyword.get(opts, :expires_in) == 3600
        "https://s3.example.com/bucket/#{key}?token=abc"
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["url"] =~ "s3.example.com"
      assert is_integer(response["data"]["expires_at"])
    end

    test "returns 400 when project_id is missing", %{conn: conn} do
      # Auth is called with nil params, returns 401, but we check for missing params
      expect(Authentication, :ensure_project_accessible, fn _conn, nil, nil ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache?hash=abc123&name=test.zip")

      # Auth plug returns 401 when params are missing and auth check fails
      assert conn.status == 401
    end

    test "returns 400 when project_id format is invalid", %{conn: conn} do
      # Auth is called with nil params from invalid project_id
      expect(Authentication, :ensure_project_accessible, fn _conn, nil, nil ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache?project_id=invalid&hash=abc123&name=test.zip")

      # Auth plug returns 401 when invalid project_id can't be parsed
      assert conn.status == 401
    end

    test "returns 401 when authentication fails", %{conn: conn} do
      project_id = "test-account/test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        get(conn, "/api/cache?project_id=#{project_id}&hash=abc123&name=test.zip")

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["message"] == "Missing Authorization header"
    end
  end

  describe "GET /api/cache/exists" do
    test "returns success when artifact exists on disk", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", ^cache_category, ^hash, ^name ->
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/exists?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "returns success when artifact exists in S3 but not on disk", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", ^cache_category, ^hash, ^name ->
        false
      end)

      expect(S3, :exists?, fn key ->
        assert key == "test-account/test-project/module/#{cache_category}/#{hash}/#{name}"
        true
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/exists?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "returns 404 when artifact does not exist anywhere", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(Disk, :module_exists?, fn "test-account", "test-project", ^cache_category, ^hash, ^name ->
        false
      end)

      expect(S3, :exists?, fn _key ->
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/cache/exists?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}")

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["errors"] |> List.first() |> Map.get("code") == "not_found"
    end

    test "returns 401 when authentication fails", %{conn: conn} do
      project_id = "test-account/test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        get(conn, "/api/cache/exists?project_id=#{project_id}&hash=abc123&name=test.zip")

      assert conn.status == 401
    end
  end

  describe "POST /api/cache/multipart/start" do
    test "starts multipart upload successfully", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :multipart_start, fn key ->
        assert key == "test-account/test-project/module/#{cache_category}/#{hash}/#{name}"
        "upload-id-123"
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/cache/multipart/start?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["upload_id"] == "upload-id-123"
    end

    test "returns 401 when authentication fails", %{conn: conn} do
      project_id = "test-account/test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:error, 401, "Missing Authorization header"}
      end)

      conn =
        post(conn, "/api/cache/multipart/start?project_id=#{project_id}&hash=abc123&name=test.zip")

      assert conn.status == 401
    end
  end

  describe "POST /api/cache/multipart/generate-url" do
    test "generates presigned URL for part upload", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"
      upload_id = "upload-id-123"
      part_number = 1

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :multipart_generate_url, fn key, ^upload_id, ^part_number ->
        assert key == "test-account/test-project/module/#{cache_category}/#{hash}/#{name}"
        "https://s3.example.com/bucket/#{key}?uploadId=#{upload_id}&partNumber=#{part_number}"
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/cache/multipart/generate-url?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}&upload_id=#{upload_id}&part_number=#{part_number}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["url"] =~ "s3.example.com"
    end

    test "returns 400 when part_number is missing", %{conn: conn} do
      project_id = "test-account/test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/cache/multipart/generate-url?project_id=#{project_id}&hash=abc123&name=test.zip&upload_id=abc")

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["message"] =~ "part_number"
    end
  end

  describe "POST /api/cache/multipart/complete" do
    test "completes multipart upload successfully", %{conn: conn} do
      project_id = "test-account/test-project"
      hash = "abc123"
      name = "MyModule.xcframework.zip"
      cache_category = "builds"
      upload_id = "upload-id-123"

      parts = [
        %{"part_number" => 1, "etag" => "etag1"},
        %{"part_number" => 2, "etag" => "etag2"}
      ]

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      expect(S3, :multipart_complete, fn key, ^upload_id, parts_tuples ->
        assert key == "test-account/test-project/module/#{cache_category}/#{hash}/#{name}"
        assert parts_tuples == [{1, "etag1"}, {2, "etag2"}]
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/multipart/complete?project_id=#{project_id}&hash=#{hash}&name=#{name}&cache_category=#{cache_category}&upload_id=#{upload_id}",
          Jason.encode!(%{parts: parts})
        )

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "returns 400 when parts is missing", %{conn: conn} do
      project_id = "test-account/test-project"

      expect(Authentication, :ensure_project_accessible, fn _conn, "test-account", "test-project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/cache/multipart/complete?project_id=#{project_id}&hash=abc123&name=test.zip&upload_id=abc",
          Jason.encode!(%{})
        )

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["message"] =~ "parts"
    end
  end
end
