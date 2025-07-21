defmodule TuistWeb.API.BundlesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = assign(conn, :selected_project, project)

    %{conn: conn, user: user, project: project}
  end

  describe "POST /api/projects/:account_handle/:project_handle/bundles" do
    test "creates a bundle and returns its URL", %{conn: conn, user: user, project: project} do
      # Given
      bundle_params = %{
        "bundle" => %{
          "app_bundle_id" => "com.example.app",
          "name" => "Test Bundle",
          "install_size" => 1024,
          "download_size" => 2048,
          "supported_platforms" => ["ios", "ios_simulator"],
          "version" => "1.0.0",
          "artifacts" => [
            %{
              "artifact_type" => "file",
              "path" => "app.ipa",
              "size" => 1024,
              "shasum" => "abc123"
            }
          ]
        }
      }

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/bundles", bundle_params)

      # Then
      assert %{"id" => id} = json_response(conn, :ok)

      {:ok, bundle} = Bundles.get_bundle(id)
      assert bundle.name == "Test Bundle"
      assert bundle.app_bundle_id == "com.example.app"
      assert bundle.project_id == project.id
      assert bundle.supported_platforms == [:ios, :ios_simulator]
      assert bundle.install_size == 1024
      assert bundle.download_size == 2048

      assert Enum.map(bundle.artifacts, & &1.size) == [1024]
    end

    test "creates a bundle with git metadata", %{conn: conn, user: user, project: project} do
      # Given
      bundle_params = %{
        "bundle" => %{
          "app_bundle_id" => "com.example.app",
          "name" => "Test Bundle",
          "install_size" => 1024,
          "download_size" => 2048,
          "supported_platforms" => ["ios", "ios_simulator"],
          "version" => "1.0.0",
          "git_branch" => "feat/my-feature",
          "git_commit_sha" => "commit-sha",
          "git_ref" => "refs/pull/14/merge",
          "artifacts" => []
        }
      }

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/bundles", bundle_params)

      # Then
      assert %{"id" => id} = json_response(conn, :ok)

      {:ok, bundle} = Bundles.get_bundle(id)
      assert bundle.git_branch == "feat/my-feature"
      assert bundle.git_commit_sha == "commit-sha"
      assert bundle.git_ref == "refs/pull/14/merge"
    end

    test "returns error when params are invalid", %{conn: conn, project: project, user: user} do
      # Given incomplete bundle parameters
      bundle_params = %{
        "bundle" => %{
          "app_bundle_id" => "com.example.app",
          "name" => "Test Bundle",
          "install_size" => 1024,
          "download_size" => 1024,
          "supported_platforms" => ["invalid"],
          "version" => "1.0.0",
          "artifacts" => []
        }
      }

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/bundles", bundle_params)

      # When
      response = json_response(conn, :bad_request)

      # Then
      assert response["message"] == "There was an error handling your request."
      assert response["fields"]["supported_platforms"] == ["is invalid"]
    end

    test "returns forbidden when user is not authorized to create a bundle", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign(:selected_project, project)
        |> post(~p"/api/projects/#{organization.account.name}/#{project.name}/bundles", %{})

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "#{user.account.name} is not authorized to create bundle"
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bundles" do
    test "returns a list of bundles sorted by inserted_at desc", %{conn: conn, user: user, project: project} do
      # Given
      _bundle1 = BundlesFixtures.bundle_fixture(
        project: project,
        uploaded_by_user: user,
        name: "Bundle 1",
        git_branch: "main",
        inserted_at: ~U[2023-01-01 10:00:00Z]
      )
      bundle2 = BundlesFixtures.bundle_fixture(
        project: project,
        uploaded_by_user: user,
        name: "Bundle 2",
        git_branch: "feature",
        inserted_at: ~U[2023-01-02 10:00:00Z]
      )

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :ok)
      
      assert %{"data" => bundles, "meta" => meta} = response
      assert length(bundles) == 2
      
      # Should be sorted by inserted_at desc (newest first)
      assert Enum.at(bundles, 0)["name"] == "Bundle 2"
      assert Enum.at(bundles, 1)["name"] == "Bundle 1"
      
      # Check metadata
      assert meta["current_page"] == 1
      assert meta["page_size"] == 50
      assert meta["total_count"] == 2
      assert meta["total_pages"] == 1

      # Check bundle structure
      first_bundle = Enum.at(bundles, 0)
      assert first_bundle["id"] == bundle2.id
      assert first_bundle["name"] == "Bundle 2"
      assert first_bundle["app_bundle_id"] == "dev.tuist.app"
      assert first_bundle["version"] == "1.0.0"
      assert first_bundle["git_branch"] == "feature"
      assert first_bundle["install_size"] == 1024
      assert first_bundle["download_size"] == 1024
      assert is_list(first_bundle["supported_platforms"])
      # List operations don't include artifacts
      refute Map.has_key?(first_bundle, "artifacts")
    end

    test "filters bundles by git_branch when provided", %{conn: conn, user: user, project: project} do
      # Given
      _bundle_main = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: user, git_branch: "main")
      bundle_feature = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: user, git_branch: "feature")

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles?git_branch=feature")

      # Then
      response = json_response(conn, :ok)
      
      assert %{"data" => bundles, "meta" => meta} = response
      assert length(bundles) == 1
      assert meta["total_count"] == 1
      
      assert Enum.at(bundles, 0)["id"] == bundle_feature.id
      assert Enum.at(bundles, 0)["git_branch"] == "feature"
    end

    test "supports pagination parameters", %{conn: conn, user: user, project: project} do
      # Given
      _bundle1 = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: user)
      _bundle2 = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: user)
      _bundle3 = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: user)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles?page=1&page_size=2")

      # Then
      response = json_response(conn, :ok)
      
      assert %{"data" => bundles, "meta" => meta} = response
      assert length(bundles) == 2
      assert meta["current_page"] == 1
      assert meta["page_size"] == 2
      assert meta["total_count"] == 3
      assert meta["total_pages"] == 2
    end

    test "returns empty list when no bundles exist", %{conn: conn, user: user, project: project} do
      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :ok)
      
      assert %{"data" => [], "meta" => meta} = response
      assert meta["total_count"] == 0
    end

    test "returns forbidden when user is not authorized to list bundles", %{conn: conn, user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, project)
        |> get(~p"/api/projects/#{organization.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] == "#{user.account.name} is not authorized to read bundle"
    end

    test "returns unauthorized when user is not authenticated", %{conn: conn, project: project} do
      # When - make request without authentication
      conn = get(conn, ~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :unauthorized)
      assert response["message"] == "You need to be authenticated to access this resource."
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bundles/:bundle_id" do
    test "returns bundle details", %{conn: conn, user: user, project: project} do
      # Given
      bundle = BundlesFixtures.bundle_fixture(
        project: project,
        uploaded_by_user: user,
        name: "Test Bundle",
        git_branch: "main",
        git_commit_sha: "abc123",
        git_ref: "refs/heads/main"
      )

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :ok)
      
      assert response["id"] == bundle.id
      assert response["name"] == "Test Bundle"
      assert response["app_bundle_id"] == "dev.tuist.app"
      assert response["version"] == "1.0.0"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "abc123"
      assert response["git_ref"] == "refs/heads/main"
      assert response["install_size"] == 1024
      assert response["download_size"] == 1024
      assert is_list(response["supported_platforms"])
      assert is_list(response["artifacts"])
      assert is_binary(response["inserted_at"])
      assert is_binary(response["updated_at"])
      assert is_binary(response["uploaded_by_account"])
      assert is_binary(response["url"])
    end

    test "returns bundle with artifacts loaded optimally", %{conn: conn, user: user, project: project} do
      # Given - create a bundle with simple artifacts to test loading
      artifacts = [
        %{
          "artifact_type" => "file",
          "path" => "app.ipa",
          "size" => 4096,
          "shasum" => "ipa789"
        },
        %{
          "artifact_type" => "asset",
          "path" => "icon.png",
          "size" => 1024,
          "shasum" => "icon123"
        }
      ]

      bundle = BundlesFixtures.bundle_fixture(
        project: project,
        uploaded_by_user: user,
        name: "Test Bundle With Artifacts",
        artifacts: artifacts
      )

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :ok)
      
      # Verify artifacts are loaded and accessible
      assert is_list(response["artifacts"])
      assert length(response["artifacts"]) >= 2  # At least our 2 artifacts
      
      # Find our specific artifacts 
      ipa_artifact = Enum.find(response["artifacts"], &(&1["path"] == "app.ipa"))
      icon_artifact = Enum.find(response["artifacts"], &(&1["path"] == "icon.png"))
      
      # Verify the artifacts were loaded with correct data
      assert ipa_artifact["artifact_type"] == "file"
      assert ipa_artifact["size"] == 4096
      assert ipa_artifact["shasum"] == "ipa789"
      
      assert icon_artifact["artifact_type"] == "asset"
      assert icon_artifact["size"] == 1024  
      assert icon_artifact["shasum"] == "icon123"
      
      # Verify the bundle has the URL field
      assert is_binary(response["url"])
      assert String.contains?(response["url"], bundle.id)
    end

    test "returns not found when bundle doesn't exist", %{conn: conn, user: user, project: project} do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{non_existent_id}")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Bundle not found"
    end

    test "returns forbidden when bundle belongs to different project", %{conn: conn, user: user} do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      bundle = BundlesFixtures.bundle_fixture(project: other_project, uploaded_by_user: user)
      
      current_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, current_project)
        |> get(~p"/api/projects/#{current_project.account.name}/#{current_project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] == "Bundle does not belong to this project"
    end

    test "returns forbidden when user is not authorized to view bundle", %{conn: conn, user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      organization_user = AccountsFixtures.user_fixture(account: organization.account, preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      bundle = BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: organization_user)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, project)
        |> get(~p"/api/projects/#{organization.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :forbidden)
      assert response["message"] == "#{user.account.name} is not authorized to read bundle"
    end
  end
end
