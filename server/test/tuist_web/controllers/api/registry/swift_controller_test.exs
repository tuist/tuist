defmodule TuistWeb.API.Registry.SwiftControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TelemetryTest

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Registry.Swift.Packages.PackageDownloadEvent
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures
  alias TuistWeb.Authentication

  setup [:telemetry_listen]

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    account = user.account

    conn = assign(conn, :current_subject, %AuthenticatedAccount{account: account, scopes: ["account:registry:read"]})

    %{conn: conn, account: account}
  end

  describe "GET /api/registry/swift" do
    test "returns :ok response", %{conn: conn} do
      # When
      conn = get(conn, ~p"/api/registry/swift")

      # Then
      assert conn.status == 200
    end
  end

  describe "GET /api/registry/swift/availability" do
    test "returns :ok response for availability", %{conn: conn} do
      # When
      conn = get(conn, ~p"/api/registry/swift/availability")

      # Then
      assert conn.status == 200
    end
  end

  describe "GET /api/registry/swift/identifiers" do
    test "returns empty array when the package does not exist", %{conn: conn} do
      # When
      conn =
        get(conn, ~p"/api/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire")

      # Then
      assert json_response(conn, :not_found) == %{
               "message" => "The package https://github.com/Alamofire/Alamofire was not found in the registry."
             }
    end

    test "returns empty array when the VCS is unsupported", %{conn: conn} do
      # When
      conn =
        get(conn, ~p"/api/registry/swift/identifiers?url=https://gitlab.com/Alamofire/Alamofire")

      # Then
      assert json_response(conn, :not_found) == %{
               "message" => "The package https://gitlab.com/Alamofire/Alamofire was not found in the registry."
             }
    end

    test "returns the identifier when the package exists", %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      # When
      conn =
        get(conn, ~p"/api/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire")

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == ["Alamofire.Alamofire"]
    end

    test "returns the identifier when the package exists and the repository full handle has a dot in its name",
         %{conn: conn} do
      # Given
      PackagesFixtures.package_fixture(
        scope: "Alamofire",
        name: "Alamofire_swift",
        repository_full_handle: "Alamofire/Alamofire.swift"
      )

      # When
      conn =
        get(
          conn,
          ~p"/api/registry/swift/identifiers?url=https://github.com/Alamofire/Alamofire.swift"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["identifiers"] == ["Alamofire.Alamofire_swift"]
    end

    test "returns bad request when the URL has an invalid path format", %{conn: conn} do
      # When: URL with too many path segments (not owner/repo format)
      invalid_url = "https://github.com/google/utilities/extra/segments"

      conn =
        get(
          conn,
          ~p"/api/registry/swift/identifiers?url=#{invalid_url}"
        )

      # Then
      assert json_response(conn, :bad_request) == %{
               "message" => "Invalid repository URL: #{invalid_url}"
             }
    end
  end

  describe "GET /api/registry/swift/:scope/:name" do
    test "returns package releases", %{conn: conn} do
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

    test "returns package releases when scope and name casing differs", %{
      conn: conn
    } do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")
      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      # When
      conn = get(conn, ~p"/api/registry/swift/Alamofire/Alamofire")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "releases" => %{
                 "5.0.0" => %{
                   "url" => "/api/registry/swift/Alamofire/Alamofire/5.0.0"
                 }
               }
             }
    end
  end

  describe "GET /api/registry/swift/:scope/:name/:version" do
    test "returns package version", %{conn: conn} do
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

    test "errors and halts the connection if the package is not found", %{
      conn: conn,
      account: account
    } do
      # When
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/scope/name/5.0.0")

      # Then
      assert conn.halted == true

      assert json_response(conn, :not_found) == %{
               "message" => "The package scope/name was not found in the registry."
             }
    end

    test "returns not found when the package release does not exist", %{
      conn: conn,
      account: account
    } do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(
        package_id: package.id,
        version: "5.0.1",
        checksum: "Alamofire-checksum"
      )

      # When
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0")

      # Then
      assert conn.status == 404
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name/:version/Package.swift" do
    test "returns Package.swift contents when object exists", %{conn: conn, account: account} do
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
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift")

      # Then
      assert response(conn, 200) =~ package_swift_content
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "returns Package.swift contents for a specific Swift version", %{
      conn: conn,
      account: account
    } do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      stub(
        Storage,
        :object_exists?,
        fn "registry/swift/alamofire/alamofire/5.0.0/Package@swift-5.2.swift", _actor ->
          true
        end
      )

      package_swift_content = "Package.swift@5.2 content"

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        get(
          conn,
          ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2"
        )

      # Then
      assert response(conn, 200) =~ package_swift_content
      assert get_resp_header(conn, "content-type") == ["text/x-swift; charset=utf-8"]
    end

    test "returns Package.swift contents for 5.0.0 version when alternate manifest is Swift version 5",
         %{
           conn: conn,
           account: account
         } do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.0.0")

      stub(
        Storage,
        :object_exists?,
        fn
          "registry/swift/alamofire/alamofire/5.0.0/Package@swift-5.0.0.swift", _actor ->
            false

          "registry/swift/alamofire/alamofire/5.0.0/Package@swift-5.0.swift", _actor ->
            false

          "registry/swift/alamofire/alamofire/5.0.0/Package@swift-5.swift", _actor ->
            true
        end
      )

      package_swift_content = "Package.swift@5 content"

      stub(Storage, :stream_object, fn _object_key, _actor ->
        Stream.map([package_swift_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        get(
          conn,
          ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.0.0"
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

    test "returns Package.swift with alternate manifests in a Link header", %{
      conn: conn,
      account: account
    } do
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
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift")

      # Then
      assert response(conn, 200) =~ package_swift_content

      assert get_resp_header(conn, "link") == [
               ~s(</api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5>; rel="alternate"; filename="Package@swift-5.0.swift"; swift-tools-version="5.0", </api/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift?swift-version=5.2>; rel="alternate"; filename="Package@swift-5.2.swift"; swift-tools-version="5.2")
             ]
    end

    test "returns :not_found when the Package.swift doesn't exist", %{
      conn: conn,
      account: account
    } do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      stub(Storage, :object_exists?, fn "registry/swift/alamofire/alamofire/5.0.0/Package.swift", _actor ->
        false
      end)

      # When
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0/Package.swift")

      # Then
      assert conn.status == 404
    end
  end

  describe "GET /api/accounts/:account_handle/registry/swift/:scope/:name/:version.zip" do
    @describetag telemetry_listen: [:analytics, :registry, :swift, :source_archive_download]
    test "returns version source archive", %{conn: conn, account: account} do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      package_release =
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
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert response(conn, 200) =~ source_archive_content
      assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :registry, :swift, :source_archive_download],
                        measurements: %{},
                        metadata: %{}
                      }}

      [package_download_event] = Repo.all(PackageDownloadEvent)
      assert package_download_event.account_id == account.id
      assert package_download_event.package_release_id == package_release.id
    end

    test "returns :not_found when the source archive doesn't exist", %{
      conn: conn,
      account: account
    } do
      # Given
      PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

      stub(Storage, :object_exists?, fn "registry/swift/alamofire/alamofire/5.0.0/source_archive.zip", _actor ->
        false
      end)

      # When
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert conn.status == 404
    end

    test "returns version source archive when authenticated as project", %{
      conn: conn,
      account: account
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> assign(:current_subject, nil)
        |> Authentication.put_current_project(project)

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
      conn = get(conn, ~p"/api/accounts/#{account.name}/registry/swift/Alamofire/Alamofire/5.0.0.zip")

      # Then
      assert response(conn, 200) =~ source_archive_content
      assert get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]
    end
  end

  describe "POST /api/accounts/:account_handle/registry/swift/login" do
    test "returns :ok when token exists", %{conn: conn, account: account} do
      # When
      response = post(conn, ~p"/api/accounts/#{account.name}/registry/swift/login")

      # Then
      assert response.status == 200
    end

    test "returns :ok response when the token is valid", %{conn: conn, account: account} do
      # When
      conn = post(conn, ~p"/api/accounts/#{account.name}/registry/swift/login")

      # Then
      assert conn.status == 200
    end

    test "returns :unauthorized response when the authenticated account is different", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      # When
      conn = post(conn, ~p"/api/accounts/#{account.name}/registry/swift/login")

      # Then
      assert conn.status == 401
    end
  end
end
