defmodule TuistWeb.API.BundlesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.AccountsFixtures
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
end
