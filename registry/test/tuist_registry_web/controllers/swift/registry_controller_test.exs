defmodule TuistRegistryWeb.Swift.RegistryControllerTest do
  use TuistRegistryWeb.ConnCase
  use Mimic

  alias TuistRegistry.S3
  alias TuistRegistry.Swift.AlternateManifests
  alias TuistRegistry.Swift.Metadata

  setup :set_mimic_from_context

  setup do
    stub(TuistRegistry.Config, :registry_bucket, fn -> "test-bucket" end)
    stub(TuistRegistry.Config, :registry_enabled?, fn -> true end)
    :ok
  end

  defp registry_json_conn(conn) do
    Plug.Conn.put_req_header(conn, "accept", "application/vnd.swift.registry.v1+json")
  end

  defp registry_zip_conn(conn) do
    Plug.Conn.put_req_header(conn, "accept", "application/vnd.swift.registry.v1+zip")
  end

  defp registry_swift_conn(conn) do
    Plug.Conn.put_req_header(conn, "accept", "application/vnd.swift.registry.v1+swift")
  end

  describe "GET /swift (availability)" do
    test "returns 200 OK with content-version header", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/availability" do
    test "returns 200 OK with content-version header", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/availability")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "POST /swift/login" do
    test "returns 200 OK", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> post("/swift/login")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/identifiers" do
    test "returns identifiers for a known package", %{conn: conn} do
      expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
        {:ok, %{"scope" => "apple", "name" => "swift-argument-parser"}}
      end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/identifiers?url=https://github.com/apple/swift-argument-parser")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert Phoenix.ConnTest.json_response(conn, 200) == %{"identifiers" => ["apple.swift-argument-parser"]}
    end

    test "returns 404 for unknown package", %{conn: conn} do
      expect(Metadata, :get_package, fn _, _ -> {:error, :not_found} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/identifiers?url=https://github.com/example/missing")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end

    test "returns 400 for malformed URL", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/identifiers?url=not-a-url")

      assert conn.status in [400, 404]
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/:scope/:name (list_releases)" do
    test "returns release list", %{conn: conn} do
      expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
        {:ok, %{"releases" => %{"1.0.0" => %{}, "1.1.0" => %{}}}}
      end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/apple/swift-argument-parser")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      body = Phoenix.ConnTest.json_response(conn, 200)
      assert body["releases"] |> Map.keys() |> Enum.sort() == ["1.0.0", "1.1.0"]
      assert body["releases"]["1.0.0"]["url"] == "/swift/apple/swift-argument-parser/1.0.0"
    end

    test "returns 404 when package not found", %{conn: conn} do
      expect(Metadata, :get_package, fn _, _ -> {:error, :not_found} end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/apple/missing")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/:scope/:name/:version (show_release)" do
    test "returns release metadata", %{conn: conn} do
      expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
        {:ok, %{"releases" => %{"1.0.0" => %{"checksum" => "abc123"}}}}
      end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]

      body = Phoenix.ConnTest.json_response(conn, 200)
      assert body["id"] == "apple.swift-argument-parser"
      assert body["version"] == "1.0.0"
      assert hd(body["resources"])["checksum"] == "abc123"
    end

    test "returns 404 for unknown release", %{conn: conn} do
      expect(Metadata, :get_package, fn _, _ ->
        {:ok, %{"releases" => %{}}}
      end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/apple/swift-argument-parser/9.9.9")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/:scope/:name/:version.zip (download_archive)" do
    test "redirects with See Other to presigned S3 URL when artifact exists", %{conn: conn} do
      expect(S3, :exists?, fn _key, _opts -> true end)

      expect(S3, :presign_download_url, fn _key, _opts ->
        {:ok, "https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip?signed=true"}
      end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0.zip")

      assert conn.status == 303
      assert get_resp_header(conn, "content-version") == ["1"]

      assert get_resp_header(conn, "location") == [
               "https://s3.example.com/registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip?signed=true"
             ]
    end

    test "returns 404 when artifact not in S3", %{conn: conn} do
      expect(S3, :exists?, fn _key, _opts -> false end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0.zip")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end

    test "returns 404 when presign fails", %{conn: conn} do
      expect(S3, :exists?, fn _key, _opts -> true end)
      expect(S3, :presign_download_url, fn _key, _opts -> {:error, :unavailable} end)

      conn =
        conn
        |> registry_zip_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0.zip")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/:scope/:name/:version/Package.swift (default manifest)" do
    test "serves manifest body inline with Link header from metadata", %{conn: conn} do
      manifest = "// swift-tools-version: 5.9\nimport PackageDescription\n"

      expect(S3, :get_object, fn _key, _opts -> {:ok, manifest} end)

      stub(Metadata, :get_package, fn _, _ ->
        {:ok,
         %{
           "releases" => %{
             "1.0.0" => %{
               "manifests" => [
                 %{"swift_version" => "5.10", "swift_tools_version" => "5.10"}
               ]
             }
           }
         }}
      end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0/Package.swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert conn.resp_body == manifest

      [link] = get_resp_header(conn, "link")
      assert link =~ ~s(<\/swift\/apple\/swift-argument-parser\/1.0.0\/Package.swift?swift-version=5.10>)
      assert link =~ ~s(rel="alternate")
      assert link =~ ~s(filename="Package@swift-5.10.swift")
    end

    test "serves manifest body inline with no Link header when no alternates", %{conn: conn} do
      manifest = "// swift-tools-version: 5.9\n"

      expect(S3, :get_object, fn _key, _opts -> {:ok, manifest} end)

      stub(Metadata, :get_package, fn _, _ -> {:ok, %{"releases" => %{"1.0.0" => %{}}}} end)
      stub(AlternateManifests, :list, fn _, _, _ -> [] end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0/Package.swift")

      assert conn.status == 200
      assert conn.resp_body == manifest
      assert get_resp_header(conn, "link") == []
    end

    test "omits alternate link when its tools version matches the default manifest", %{conn: conn} do
      manifest = "// swift-tools-version: 6.0\n"

      expect(S3, :get_object, fn _key, _opts -> {:ok, manifest} end)

      stub(Metadata, :get_package, fn _, _ ->
        {:ok,
         %{
           "releases" => %{
             "1.0.0" => %{
               "manifests" => [
                 %{"swift_version" => nil, "swift_tools_version" => "6.0"},
                 %{"swift_version" => "6.0", "swift_tools_version" => "6.0"}
               ]
             }
           }
         }}
      end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0/Package.swift")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert get_resp_header(conn, "link") == []
    end

    test "returns 404 when manifest missing", %{conn: conn} do
      expect(S3, :get_object, fn _key, _opts -> {:error, :not_found} end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/missing/1.0.0/Package.swift")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end

  describe "GET /swift/:scope/:name/:version/Package.swift?swift-version=X.Y" do
    test "serves version-specific manifest body inline", %{conn: conn} do
      manifest = "// swift-tools-version: 5.10\nimport PackageDescription\n"

      expect(S3, :get_object, fn _key, _opts -> {:ok, manifest} end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0/Package.swift?swift-version=5.10")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert get_resp_header(conn, "location") == []
      assert conn.resp_body == manifest
    end

    test "falls back to Package.swift redirect when version-specific not found", %{conn: conn} do
      # All version-specific candidates miss
      stub(S3, :get_object, fn _key, _opts -> {:error, :not_found} end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/swift/apple/swift-argument-parser/1.0.0/Package.swift?swift-version=5.10")

      assert conn.status == 303
      assert get_resp_header(conn, "content-version") == ["1"]

      assert get_resp_header(conn, "location") == [
               "/swift/apple/swift-argument-parser/1.0.0/Package.swift"
             ]
    end
  end

  describe "legacy /api/registry/swift/* prefix" do
    test "serves availability identically and tags the response as deprecated", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/availability")

      assert conn.status == 200
      assert get_resp_header(conn, "content-version") == ["1"]
      assert get_resp_header(conn, "deprecation") == ["true"]
      assert get_resp_header(conn, "sunset") == ["Thu, 31 Dec 2026 23:59:59 GMT"]
    end

    test "serves list_releases with legacy-prefixed release URLs", %{conn: conn} do
      stub(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
        {:ok, %{"releases" => %{"1.0.0" => %{}}}}
      end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/api/registry/swift/apple/swift-argument-parser")

      assert conn.status == 200
      assert get_resp_header(conn, "deprecation") == ["true"]
      body = JSON.decode!(conn.resp_body)
      # Generated URLs must match the inbound prefix. If a SwiftPM client
      # reached us through the legacy path (potentially via the registry
      # router Worker rewriting `tuist.dev/api/registry/swift/...`),
      # resolving a `/swift/...` URL relative to the request would 404.
      assert body["releases"]["1.0.0"]["url"] ==
               "/api/registry/swift/apple/swift-argument-parser/1.0.0"
    end

    test "default Package.swift Link header uses the legacy prefix", %{conn: conn} do
      manifest = "// swift-tools-version: 5.9\n"

      expect(S3, :get_object, fn _key, _opts -> {:ok, manifest} end)

      stub(Metadata, :get_package, fn _, _ ->
        {:ok,
         %{
           "releases" => %{
             "1.0.0" => %{
               "manifests" => [
                 %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
               ]
             }
           }
         }}
      end)

      conn =
        conn
        |> registry_swift_conn()
        |> get("/api/registry/swift/apple/swift-argument-parser/1.0.0/Package.swift")

      assert conn.status == 200
      assert get_resp_header(conn, "deprecation") == ["true"]
      [link] = get_resp_header(conn, "link")

      assert link =~
               ~s(<\/api\/registry\/swift\/apple\/swift-argument-parser\/1.0.0\/Package.swift?swift-version=5.9>)

      refute link =~ ~s(<\/swift\/apple\/)
    end

    test "canonical /swift/* responses do not carry the deprecation header", %{conn: conn} do
      conn =
        conn
        |> registry_json_conn()
        |> get("/swift/availability")

      assert conn.status == 200
      assert get_resp_header(conn, "deprecation") == []
      assert get_resp_header(conn, "sunset") == []
    end
  end

  describe "registry disabled" do
    test "returns 404 with content-version on every endpoint when disabled", %{conn: conn} do
      stub(TuistRegistry.Config, :registry_enabled?, fn -> false end)

      conn =
        conn
        |> registry_json_conn()
        |> get("/swift")

      assert conn.status == 404
      assert get_resp_header(conn, "content-version") == ["1"]
    end
  end
end
