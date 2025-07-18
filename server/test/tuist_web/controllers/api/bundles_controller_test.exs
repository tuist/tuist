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
    test "lists bundles for a project", %{conn: conn, user: user, project: project} do
      # Given
      bundle1 = BundlesFixtures.bundle_fixture(project_id: project.id, git_branch: "main", name: "App1")
      bundle2 = BundlesFixtures.bundle_fixture(project_id: project.id, git_branch: "feature", name: "App2")

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :ok)
      assert length(response["bundles"]) == 2
      
      bundle_names = Enum.map(response["bundles"], & &1["name"])
      assert bundle1.name in bundle_names
      assert bundle2.name in bundle_names
      
      assert response["meta"]["total_count"] == 2
      assert response["meta"]["has_next_page"] == false
      assert response["meta"]["has_previous_page"] == false
    end

    test "filters bundles by git branch", %{conn: conn, user: user, project: project} do
      # Given
      _bundle_main = BundlesFixtures.bundle_fixture(project_id: project.id, git_branch: "main")
      bundle_feature = BundlesFixtures.bundle_fixture(project_id: project.id, git_branch: "feature")

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles?git_branch=feature")

      # Then
      response = json_response(conn, :ok)
      assert length(response["bundles"]) == 1
      assert hd(response["bundles"])["id"] == bundle_feature.id
      assert hd(response["bundles"])["git_branch"] == "feature"
    end

    test "paginates bundles", %{conn: conn, user: user, project: project} do
      # Given - create 3 bundles
      _bundle1 = BundlesFixtures.bundle_fixture(project_id: project.id)
      _bundle2 = BundlesFixtures.bundle_fixture(project_id: project.id)
      _bundle3 = BundlesFixtures.bundle_fixture(project_id: project.id)

      # When - request first page with page_size=2
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles?page=1&page_size=2")

      # Then
      response = json_response(conn, :ok)
      assert length(response["bundles"]) == 2
      assert response["meta"]["total_count"] == 3
      assert response["meta"]["has_next_page"] == true
      assert response["meta"]["has_previous_page"] == false
    end

    test "returns empty list when no bundles exist", %{conn: conn, user: user, project: project} do
      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      response = json_response(conn, :ok)
      assert response["bundles"] == []
      assert response["meta"]["total_count"] == 0
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
  end

  describe "GET /api/projects/:account_handle/:project_handle/bundles/:bundle_id" do
    test "shows a specific bundle", %{conn: conn, user: user, project: project} do
      # Given
      bundle = BundlesFixtures.bundle_fixture(project_id: project.id, name: "TestApp", version: "1.0.0")

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :ok)
      assert response["id"] == bundle.id
      assert response["name"] == "TestApp"
      assert response["version"] == "1.0.0"
      assert response["install_size"] == bundle.install_size
    end

    test "returns 404 when bundle does not exist", %{conn: conn, user: user, project: project} do
      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{UUIDv7.generate()}")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Bundle not found"
    end

    test "returns 404 when bundle belongs to different project", %{conn: conn, user: user, project: project} do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      bundle = BundlesFixtures.bundle_fixture(project_id: other_project.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Bundle not found"
    end

    test "returns forbidden when user is not authorized to show bundle", %{conn: conn, user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      bundle = BundlesFixtures.bundle_fixture(project_id: project.id)

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
