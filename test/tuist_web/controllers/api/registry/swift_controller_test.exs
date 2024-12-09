defmodule TuistWeb.API.Registry.SwiftControllerTest do
  alias Tuist.Storage
  alias Tuist.Registry.Swift.PackagesFixtures
  alias Tuist.Registry.Swift.PackagesFixtures
  use TuistWeb.ConnCase, async: false
  use Mimic

  describe "GET /api/accounts/:account_handle/registry/swift/availability" do
    test "returns :ok response for availability", %{conn: conn} do
      # When
      conn =
        conn
        |> get(~p"/api/accounts/account_handle/registry/swift/availability")

      # Then
      assert conn.status == 200
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/identifiers" do
    test "returns empty array when the package does not exist", %{conn: conn} do
      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == []
    end

    test "returns empty array when the VCS is unsupported", %{conn: conn} do
      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/identifiers?url=https://gitlab.com/Alamofire/Alamofire"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == []
    end

    test "returns the identifier when the package exists", %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == ["Alamofire.Alamofire"]
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name" do
    test "returns package releases", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.1")

      # When
      conn =
        conn
        |> get(~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "releases" => %{
                 "5.0.0" => %{
                   "url" =>
                     "/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0"
                 },
                 "5.0.1" => %{
                   "url" =>
                     "/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.1"
                 }
               }
             }
    end

    test "returns package releases when scope and name casing differs", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      # When
      conn =
        conn
        |> get(~p"/api/accounts/account_handle/registry/swift/alamofire/alamofire")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "releases" => %{
                 "5.0.0" => %{
                   "url" =>
                     "/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0"
                 }
               }
             }
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name/:version" do
    test "returns package version", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(
        package_id: package.id,
        version: "5.0.0",
        checksum: "Alamofire-checksum"
      )

      # When
      conn =
        conn |> get(~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0")

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

    test "errors and halts the connection if the package is not found", %{conn: conn} do
      # When
      conn =
        conn |> get(~p"/api/accounts/account_handle/registry/swift/scope/name/5.0.0")

      # Then
      assert conn.halted == true

      assert json_response(conn, :not_found) == %{
               "message" => "The package scope/name was not found in the registry."
             }
    end

    test "returns not found when the package release does not exist", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(
        package_id: package.id,
        version: "5.0.1",
        checksum: "Alamofire-checksum"
      )

      # When
      conn =
        conn |> get(~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0")

      # Then
      assert conn.status == 404
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name/:version/Package.swift" do
    test "returns Package.swift contents when object exists", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      Storage
      |> stub(:object_exists?, fn "registry/swift/Alamofire/Alamofire/5.0.0/Package.swift" ->
        true
      end)

      package_swift_content = "Package.swift content"

      Storage
      |> stub(:stream_object, fn _ ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift"
        )

      # Then
      assert response(conn, 200) =~ package_swift_content
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "returns Package.swift contents for a specific Swift version", %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      Storage
      |> stub(
        :object_exists?,
        fn "registry/swift/Alamofire/Alamofire/5.0.0/Package@swift-5.2.swift" ->
          true
        end
      )

      package_swift_content = "Package.swift@5.2 content"

      Storage
      |> stub(:stream_object, fn _ ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2"
        )

      # Then
      assert response(conn, 200) =~ package_swift_content
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "redirects to Package.swift when the manifest for a specific Swift version doesn't exist",
         %{conn: conn} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      Storage
      |> stub(
        :object_exists?,
        fn "registry/swift/Alamofire/Alamofire/5.0.0/Package@swift-5.2.swift" ->
          false
        end
      )

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2"
        )

      # Then
      assert redirected_to(conn, 303) ==
               "/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift"
    end

    test "returns Package.swift with alternate manifests in a Link header", %{conn: conn} do
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

      Storage
      |> stub(:object_exists?, fn "registry/swift/Alamofire/Alamofire/5.0.0/Package.swift" ->
        true
      end)

      package_swift_content = "Package.swift content"

      Storage
      |> stub(:stream_object, fn _ ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift"
        )

      # Then
      assert response(conn, 200) =~ package_swift_content

      assert get_resp_header(conn, "link") == [
               ~s(</api/accounts/tuist/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5>; rel="alternate"; filename="Package@swift-5.swift"; swift-tools-version="5.0", </api/accounts/tuist/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2>; rel="alternate"; filename="Package@swift-5.2.swift"; swift-tools-version="5.2")
             ]
    end

    test "returns :not_found when the Package.swift doesn't exist", %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      Storage
      |> stub(:object_exists?, fn "registry/swift/Alamofire/Alamofire/5.0.0/Package.swift" ->
        false
      end)

      # When
      conn =
        conn
        |> get(
          ~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift"
        )

      # Then
      assert conn.status == 404
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name/:version.zip" do
    test "returns version source archive", %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      Storage
      |> stub(:object_exists?, fn "registry/swift/Alamofire/Alamofire/5.0.0/source_archive.zip" ->
        true
      end)

      source_archive_content = "Source archive content"

      Storage
      |> stub(:stream_object, fn _ ->
        Stream.map([source_archive_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        conn
        |> get(~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert response(conn, 200) =~ source_archive_content
      assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]
    end

    test "returns :not_found when the source archive doesn't exist", %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      Storage
      |> stub(:object_exists?, fn "registry/swift/Alamofire/Alamofire/5.0.0/source_archive.zip" ->
        false
      end)

      # When
      conn =
        conn
        |> get(~p"/api/accounts/account_handle/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert conn.status == 404
    end
  end
end
