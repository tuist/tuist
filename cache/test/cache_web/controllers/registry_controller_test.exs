defmodule CacheWeb.RegistryControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.Registry.Metadata
  alias Cache.S3
  alias Cache.S3Transfers

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :registry_github_token, "test-token")
    on_exit(fn -> Application.delete_env(:cache, :registry_github_token) end)
    stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
    :ok
  end

  describe "GET /api/registry/swift (availability)" do
    test "returns 200 OK with content-version header", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /api/registry/swift/availability" do
    test "returns 200 OK with content-version header", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/availability")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "POST /api/registry/swift/login" do
    test "returns 200 OK", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> post("/api/registry/swift/login")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /api/registry/swift/identifiers" do
    test "returns identifiers for valid repository url", %{conn: conn} do
      url = "https://github.com/apple/swift-argument-parser"

      expect(Metadata, :get_package, fn "apple", "swift-argument-parser" -> {:ok, %{}} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/identifiers?url=#{URI.encode_www_form(url)}")

      assert conn.status == 200
      response = json_response(conn, :ok)
      assert response["identifiers"] == ["apple.swift-argument-parser"]
    end

    test "returns 400 for invalid repository url", %{conn: conn} do
      url = "https://github.com/invalid"

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/identifiers?url=#{URI.encode_www_form(url)}")

      assert conn.status == 400
      response = json_response(conn, :bad_request)
      assert response["message"] == "Invalid repository URL: #{url}"
    end

    test "returns 404 for unsupported vcs", %{conn: conn} do
      url = "https://gitlab.com/tuist/tuist"

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/identifiers?url=#{URI.encode_www_form(url)}")

      assert conn.status == 404
      response = json_response(conn, :not_found)
      assert response["message"] == "The package #{url} was not found in the registry."
    end

    test "returns 404 when package is missing", %{conn: conn} do
      url = "https://github.com/apple/swift-argument-parser"

      expect(Metadata, :get_package, fn "apple", "swift-argument-parser" -> {:error, :not_found} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/identifiers?url=#{URI.encode_www_form(url)}")

      assert conn.status == 404
      response = json_response(conn, :not_found)
      assert response["message"] == "The package #{url} was not found in the registry."
    end
  end

  describe "GET /api/registry/swift/:scope/:name (list_releases)" do
    test "returns releases when package exists", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"

      metadata = %{
        "scope" => scope,
        "name" => name,
        "releases" => %{
          "1.0.0" => %{"checksum" => "abc123"},
          "1.1.0" => %{"checksum" => "def456"}
        }
      }

      expect(Metadata, :get_package, fn ^scope, ^name -> {:ok, metadata} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      response = json_response(conn, :ok)

      assert response["releases"] == %{
               "1.0.0" => %{"url" => "/api/registry/swift/apple/swift-argument-parser/1.0.0"},
               "1.1.0" => %{"url" => "/api/registry/swift/apple/swift-argument-parser/1.1.0"}
             }
    end

    test "returns 404 when package not found", %{conn: conn} do
      scope = "unknown"
      name = "nonexistent"

      expect(Metadata, :get_package, fn ^scope, ^name -> {:error, :not_found} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]

      response = json_response(conn, :not_found)
      assert response["message"] == "The package #{scope}/#{name} was not found in the registry."
    end
  end

  describe "GET /api/registry/swift/:scope/:name/:version (show_release)" do
    test "returns release info when version exists", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      metadata = %{
        "scope" => scope,
        "name" => name,
        "releases" => %{
          "1.0.0" => %{"checksum" => "abc123def456"}
        }
      }

      expect(Metadata, :get_package, fn ^scope, ^name -> {:ok, metadata} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      response = json_response(conn, :ok)

      assert response == %{
               "id" => "apple.swift-argument-parser",
               "version" => "1.0.0",
               "resources" => [
                 %{
                   "name" => "source-archive",
                   "type" => "application/zip",
                   "checksum" => "abc123def456"
                 }
               ]
             }
    end

    test "normalizes version before lookup", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"

      metadata = %{
        "scope" => scope,
        "name" => name,
        "releases" => %{
          "1.0.0" => %{"checksum" => "abc123"}
        }
      }

      expect(Metadata, :get_package, fn ^scope, ^name -> {:ok, metadata} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/v1")

      assert conn.status == 200

      response = json_response(conn, :ok)
      assert response["version"] == "1.0.0"
    end

    test "returns 404 when version not found", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "9.9.9"

      metadata = %{
        "scope" => scope,
        "name" => name,
        "releases" => %{
          "1.0.0" => %{"checksum" => "abc123"}
        }
      }

      expect(Metadata, :get_package, fn ^scope, ^name -> {:ok, metadata} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end

    test "returns 404 when package not found", %{conn: conn} do
      scope = "unknown"
      name = "nonexistent"
      version = "1.0.0"

      expect(Metadata, :get_package, fn ^scope, ^name -> {:error, :not_found} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]

      response = json_response(conn, :not_found)
      assert response["message"] == "The package #{scope}/#{name} was not found in the registry."
    end
  end

  describe "GET /api/registry/swift/:scope/:name/:version.zip (download_archive)" do
    test "serves from disk when file exists locally", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "source_archive.zip" -> true end)

      expect(Disk, :registry_local_accel_path, fn ^scope, ^name, ^version, "source_archive.zip" ->
        "/internal/local/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}.zip")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
             ]

      assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]
    end

    test "falls back to S3 when file not on disk", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "source_archive.zip" -> false end)

      expect(S3, :exists?, fn _key, _opts -> true end)

      expect(S3Transfers, :enqueue_registry_download, fn _key -> {:ok, %{}} end)

      expect(S3, :presign_download_url, fn _key, _opts ->
        {:ok, "https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip?signed=true"}
      end)

      expect(S3, :remote_accel_path, fn _url ->
        "/internal/remote/https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip?signed=true"
      end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}.zip")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end

    test "returns 404 when S3 presign fails", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "source_archive.zip" -> false end)

      expect(S3, :exists?, fn _key, _opts -> true end)

      expect(S3Transfers, :enqueue_registry_download, fn _key -> {:ok, %{}} end)

      expect(S3, :presign_download_url, fn _key, _opts -> {:error, :not_found} end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}.zip")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end

    test "returns 404 when S3 object is missing", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "source_archive.zip" -> false end)

      expect(S3, :exists?, fn _key, _opts -> false end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}.zip")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /api/registry/swift/:scope/:name/:version/Package.swift (show_manifest)" do
    test "serves manifest from disk when file exists", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      metadata = %{
        "scope" => scope,
        "name" => name,
        "releases" => %{
          "1.0.0" => %{
            "checksum" => "abc123",
            "manifests" => [
              %{"swift_version" => nil, "swift_tools_version" => "5.7"},
              %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
            ]
          }
        }
      }

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "Package.swift" -> true end)

      expect(Disk, :registry_local_accel_path, fn ^scope, ^name, ^version, "Package.swift" ->
        "/internal/local/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift"
      end)

      expect(Metadata, :get_package, fn ^scope, ^name -> {:ok, metadata} end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      assert get_resp_header(conn, "x-accel-redirect") == [
               "/internal/local/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift"
             ]

      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]

      [link_header] = get_resp_header(conn, "link")
      assert link_header =~ "rel=\"alternate\""
      assert link_header =~ "swift-version=5.9"
    end

    test "redirects to default manifest when swift-version specified but not found", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "Package@swift-5.8.swift" -> false end)

      expect(S3, :exists?, fn _key, _opts -> false end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift?swift-version=5.8")

      assert conn.status == 303
      assert get_resp_header(conn, "content-version") == ["1"]

      assert get_resp_header(conn, "location") == [
               "/api/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift"
             ]
    end

    test "falls back to S3 when manifest not on disk", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "Package.swift" -> false end)

      expect(S3, :exists?, fn _key, _opts -> true end)

      expect(Metadata, :get_package, fn ^scope, ^name -> {:error, :not_found} end)

      expect(S3Transfers, :enqueue_registry_download, fn _key -> {:ok, %{}} end)

      expect(S3, :presign_download_url, fn _key, _opts ->
        {:ok, "https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift?signed=true"}
      end)

      expect(S3, :remote_accel_path, fn _url ->
        "/internal/remote/https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift?signed=true"
      end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "returns 404 when manifest not found anywhere", %{conn: conn} do
      scope = "apple"
      name = "swift-argument-parser"
      version = "1.0.0"

      expect(Disk, :registry_exists?, fn ^scope, ^name, ^version, "Package.swift" -> false end)

      expect(S3, :exists?, fn _key, _opts -> false end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  defp registry_json_conn(conn) do
    put_req_header(conn, "accept", "application/vnd.swift.registry.v1+json")
  end

  defp registry_zip_conn(conn) do
    put_req_header(conn, "accept", "application/vnd.swift.registry.v1+zip")
  end

  defp registry_swift_conn(conn) do
    put_req_header(conn, "accept", "application/vnd.swift.registry.v1+swift")
  end
end
