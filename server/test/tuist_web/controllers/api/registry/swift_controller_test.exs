defmodule TuistWeb.API.Registry.SwiftControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TelemetryTest

  alias Tuist.Registry.Swift.Packages.PackageDownloadEvent
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  setup [:telemetry_listen]

  describe "GET /api/registry/swift/availability" do
    test "returns :ok response for availability" do
      # Given
      conn = build_conn()

      # When
      conn = get(conn, ~p"/api/registry/swift/availability")

      # Then
      assert conn.status == 200
    end
  end

  describe "Unauthenticated endpoints" do
    setup do
      # Create a fresh unauthenticated connection
      conn = build_conn()
      %{unauth_conn: conn}
    end

    test "GET /api/registry/swift/availability returns :ok response", %{unauth_conn: conn} do
      # When
      conn = get(conn, ~p"/api/registry/swift/availability")

      # Then
      assert conn.status == 200
    end

    test "GET /api/registry/swift/identifiers returns not found when package does not exist", %{
      unauth_conn: conn
    } do
      # When
      conn =
        get(conn, ~p"/api/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire")

      # Then
      assert json_response(conn, :not_found) == %{
               "message" => "The package https://github.com/Alamofire/Alamofire was not found in the registry."
             }
    end

    test "GET /api/registry/swift/identifiers returns the identifier when package exists", %{
      unauth_conn: conn
    } do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      # When
      conn =
        get(conn, ~p"/api/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire")

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == ["Alamofire.Alamofire"]
    end

    test "GET /api/registry/swift/:scope/:name returns package releases", %{unauth_conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.1")

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "releases" => %{
                 "5.0.0" => %{
                   "url" => "/api/registry/swift/Alamofire/Alamofire/5.0.0"
                 },
                 "5.0.1" => %{
                   "url" => "/api/registry/swift/Alamofire/Alamofire/5.0.1"
                 }
               }
             }
    end

    test "GET /api/registry/swift/:scope/:name/:version returns package version", %{
      unauth_conn: conn
    } do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(
        package_id: package.id,
        version: "5.0.0",
        checksum: "Alamofire-checksum"
      )

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire/5.0.0")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "version" => "5.0.0",
               "id" => "Alamofire.Alamofire",
               "resources" => [
                 %{
                   "checksum" => "Alamofire-checksum",
                   "name" => "source-archive",
                   "type" => "application/zip"
                 }
               ]
             }
    end

    test "GET /api/registry/swift/:scope/:name/:version/Package.swift returns contents when object exists",
         %{unauth_conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      stub(Storage, :object_exists?, fn "registry/swift/alamofire/alamofire/5.0.0/Package.swift", _actor ->
        true
      end)

      package_swift_content = "Package.swift content"

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift")

      # Then
      assert response(conn, 200) =~ package_swift_content
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "GET /api/registry/swift/:scope/:name/:version/Package.swift redirects when specific Swift version doesn't exist",
         %{unauth_conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      stub(
        Storage,
        :object_exists?,
        fn "registry/swift/alamofire/alamofire/5.0.0/Package@swift-5.2.swift", _actor ->
          false
        end
      )

      # When
      conn =
        get(
          conn,
          ~p"/api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2"
        )

      # Then
      assert redirected_to(conn, 303) ==
               "/api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift"
    end

    test "GET /api/registry/swift/:scope/:name/:version/Package.swift returns alternate manifests in Link header",
         %{unauth_conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      package_release =
        PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      PackagesFixtures.package_manifest_fixture(package_release_id: package_release.id)

      PackagesFixtures.package_manifest_fixture(
        package_release_id: package_release.id,
        swift_version: "5",
        swift_tools_version: "5.0"
      )

      PackagesFixtures.package_manifest_fixture(
        package_release_id: package_release.id,
        swift_version: "5.2",
        swift_tools_version: "5.2"
      )

      stub(Storage, :object_exists?, fn "registry/swift/alamofire/alamofire/5.0.0/Package.swift", _actor ->
        true
      end)

      package_swift_content = "Package.swift content"

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift")

      # Then
      assert response(conn, 200) =~ package_swift_content

      assert get_resp_header(conn, "link") == [
               ~s(</api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5>; rel="alternate"; filename="Package@swift-5.0.swift"; swift-tools-version="5.0", </api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2>; rel="alternate"; filename="Package@swift-5.2.swift"; swift-tools-version="5.2")
             ]
    end

    @tag telemetry_listen: [:analytics, :registry, :swift, :source_archive_download]
    test "GET /api/registry/swift/:scope/:name/:version.zip returns archive without creating download event",
         %{unauth_conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(
        package_id: package.id,
        version: "5.0.0"
      )

      stub(Storage, :object_exists?, fn "registry/swift/alamofire/alamofire/5.0.0/source_archive.zip", _actor ->
        true
      end)

      source_archive_content = "Source archive content"

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([source_archive_content], fn chunk -> chunk end)
      end)

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert response(conn, 200) =~ source_archive_content
      assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :registry, :swift, :source_archive_download],
                        measurements: %{},
                        metadata: %{}
                      }}

      # No download event should be created for unauthenticated requests
      assert Repo.all(PackageDownloadEvent) == []
    end

    test "POST /api/registry/swift/login returns :ok response", %{unauth_conn: conn} do
      # When
      conn = post(conn, ~p"/api/registry/swift/login")

      # Then
      assert conn.status == 200
    end
  end
end
