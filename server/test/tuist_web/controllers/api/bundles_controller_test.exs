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
          "type" => "app",
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
      assert %{
               "id" => id,
               "name" => name,
               "app_bundle_id" => app_bundle_id,
               "version" => version,
               "supported_platforms" => supported_platforms,
               "download_size" => download_size,
               "install_size" => install_size,
               "git_branch" => git_branch,
               "git_commit_sha" => git_commit_sha,
               "git_ref" => git_ref
             } =
               json_response(conn, :ok)

      {:ok, bundle} = Bundles.get_bundle(id)

      assert bundle.name == name
      assert bundle.version == version
      assert bundle.app_bundle_id == app_bundle_id
      assert bundle.project_id == project.id
      assert bundle.supported_platforms == Enum.map(supported_platforms, &String.to_atom(&1))
      assert bundle.install_size == install_size
      assert bundle.download_size == download_size
      assert bundle.git_branch == git_branch
      assert bundle.git_commit_sha == git_commit_sha
      assert bundle.git_ref == git_ref
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
          "type" => "app",
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

    test "creates a bundle without type field", %{conn: conn, user: user, project: project} do
      # Given
      bundle_params = %{
        "bundle" => %{
          "app_bundle_id" => "com.example.app",
          "name" => "Test Bundle No Type",
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
      assert %{
               "id" => id,
               "name" => "Test Bundle No Type",
               "type" => "ipa"
             } = json_response(conn, :ok)

      {:ok, bundle} = Bundles.get_bundle(id)
      assert bundle.type == :ipa
    end

    test "creates a bundle without type field and no download_size defaults to app", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      bundle_params = %{
        "bundle" => %{
          "app_bundle_id" => "com.example.app",
          "name" => "Test Bundle No Type No Download Size",
          "install_size" => 1024,
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
      assert %{
               "id" => id,
               "name" => "Test Bundle No Type No Download Size",
               "type" => "app"
             } = json_response(conn, :ok)

      {:ok, bundle} = Bundles.get_bundle(id)
      assert bundle.type == :app
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
      assert response["message"] =~ "Invalid value"
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
    test "returns a list of bundles sorted by inserted_at desc", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      bundle1 =
        [
          project: project,
          uploaded_by_user: user,
          name: "Bundle 1",
          git_branch: "main",
          inserted_at: ~U[2023-01-01 10:00:00Z]
        ]
        |> BundlesFixtures.bundle_fixture()
        |> Tuist.Repo.preload(project: [:account])

      bundle2 =
        [
          project: project,
          uploaded_by_user: user,
          name: "Bundle 2",
          git_branch: "feature",
          inserted_at: ~U[2023-01-02 10:00:00Z]
        ]
        |> BundlesFixtures.bundle_fixture()
        |> Tuist.Repo.preload(project: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      assert %{"bundles" => bundles, "meta" => meta} = json_response(conn, :ok)

      assert bundles == [
               %{
                 "app_bundle_id" => bundle2.app_bundle_id,
                 "download_size" => bundle2.download_size,
                 "git_branch" => bundle2.git_branch,
                 "git_commit_sha" => bundle2.git_commit_sha,
                 "git_ref" => bundle2.git_ref,
                 "id" => bundle2.id,
                 "inserted_at" => DateTime.to_iso8601(bundle2.inserted_at),
                 "install_size" => bundle2.install_size,
                 "name" => bundle2.name,
                 "supported_platforms" => Enum.map(bundle2.supported_platforms, &Atom.to_string(&1)),
                 "type" => Atom.to_string(bundle2.type),
                 "uploaded_by_account" => bundle2.uploaded_by_account.name,
                 "url" => url(~p"/#{bundle2.project.account.name}/#{bundle2.project.name}/bundles/#{bundle2.id}"),
                 "version" => bundle2.version
               },
               %{
                 "app_bundle_id" => bundle1.app_bundle_id,
                 "download_size" => bundle1.download_size,
                 "git_branch" => bundle1.git_branch,
                 "git_commit_sha" => bundle1.git_commit_sha,
                 "git_ref" => bundle1.git_ref,
                 "id" => bundle1.id,
                 "inserted_at" => DateTime.to_iso8601(bundle1.inserted_at),
                 "install_size" => bundle1.install_size,
                 "name" => bundle1.name,
                 "supported_platforms" => Enum.map(bundle1.supported_platforms, &Atom.to_string(&1)),
                 "type" => Atom.to_string(bundle1.type),
                 "uploaded_by_account" => bundle1.uploaded_by_account.name,
                 "url" => url(~p"/#{bundle1.project.account.name}/#{bundle1.project.name}/bundles/#{bundle1.id}"),
                 "version" => bundle1.version
               }
             ]

      assert meta == %{
               "current_page" => 1,
               "has_next_page" => false,
               "has_previous_page" => false,
               "page_size" => 20,
               "total_count" => 2,
               "total_pages" => 1
             }
    end

    test "filters bundles by git_branch when provided", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      _bundle_main =
        BundlesFixtures.bundle_fixture(
          project: project,
          uploaded_by_user: user,
          git_branch: "main"
        )

      bundle_feature =
        [project: project, uploaded_by_user: user, git_branch: "feature"]
        |> BundlesFixtures.bundle_fixture()
        |> Tuist.Repo.preload(project: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles?git_branch=feature")

      # Then
      assert %{"bundles" => bundles, "meta" => meta} = json_response(conn, :ok)

      assert bundles == [
               %{
                 "app_bundle_id" => bundle_feature.app_bundle_id,
                 "download_size" => bundle_feature.download_size,
                 "git_branch" => bundle_feature.git_branch,
                 "git_commit_sha" => bundle_feature.git_commit_sha,
                 "git_ref" => bundle_feature.git_ref,
                 "id" => bundle_feature.id,
                 "inserted_at" => DateTime.to_iso8601(bundle_feature.inserted_at),
                 "install_size" => bundle_feature.install_size,
                 "name" => bundle_feature.name,
                 "supported_platforms" => Enum.map(bundle_feature.supported_platforms, &Atom.to_string(&1)),
                 "type" => Atom.to_string(bundle_feature.type),
                 "uploaded_by_account" => bundle_feature.uploaded_by_account.name,
                 "url" =>
                   url(
                     ~p"/#{bundle_feature.project.account.name}/#{bundle_feature.project.name}/bundles/#{bundle_feature.id}"
                   ),
                 "version" => bundle_feature.version
               }
             ]

      assert meta == %{
               "current_page" => 1,
               "has_next_page" => false,
               "has_previous_page" => false,
               "page_size" => 20,
               "total_count" => 1,
               "total_pages" => 1
             }
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
      assert %{"bundles" => _bundles, "meta" => meta} = json_response(conn, :ok)

      assert meta == %{
               "current_page" => 1,
               "has_next_page" => true,
               "has_previous_page" => false,
               "page_size" => 2,
               "total_count" => 3,
               "total_pages" => 2
             }
    end

    test "returns empty list when no bundles exist", %{conn: conn, user: user, project: project} do
      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles")

      # Then
      assert %{"bundles" => [], "meta" => meta} = json_response(conn, :ok)

      assert meta == %{
               "current_page" => 1,
               "has_next_page" => false,
               "has_previous_page" => false,
               "page_size" => 20,
               "total_count" => 0,
               "total_pages" => 0
             }
    end

    test "returns forbidden when user is not authorized to list bundles", %{
      conn: conn,
      user: user
    } do
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
      bundle =
        [
          project: project,
          uploaded_by_user: user,
          name: "Test Bundle",
          git_branch: "main",
          git_commit_sha: "abc123",
          git_ref: "refs/heads/main"
        ]
        |> BundlesFixtures.bundle_fixture()
        |> Tuist.Repo.preload(project: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      assert json_response(conn, :ok) == %{
               "app_bundle_id" => bundle.app_bundle_id,
               "download_size" => bundle.download_size,
               "git_branch" => bundle.git_branch,
               "git_commit_sha" => bundle.git_commit_sha,
               "git_ref" => bundle.git_ref,
               "id" => bundle.id,
               "inserted_at" => DateTime.to_iso8601(bundle.inserted_at),
               "install_size" => bundle.install_size,
               "name" => bundle.name,
               "supported_platforms" => Enum.map(bundle.supported_platforms, &Atom.to_string(&1)),
               "type" => Atom.to_string(bundle.type),
               "uploaded_by_account" => bundle.uploaded_by_account.name,
               "url" => url(~p"/#{bundle.project.account.name}/#{bundle.project.name}/bundles/#{bundle.id}"),
               "version" => bundle.version,
               "artifacts" => []
             }
    end

    test "returns bundle with artifacts loaded optimally", %{
      conn: conn,
      user: user,
      project: project
    } do
      artifact_1 = %{
        artifact_type: :file,
        path: "app.ipa",
        size: 4096,
        shasum: "ipa789"
      }

      artifact_2 = %{
        artifact_type: :asset,
        path: "icon.png",
        size: 1024,
        shasum: "icon123"
      }

      artifacts = [
        artifact_1,
        artifact_2
      ]

      bundle =
        [project: project, uploaded_by_user: user, name: "Test Bundle With Artifacts", artifacts: artifacts]
        |> BundlesFixtures.bundle_fixture()
        |> Tuist.Repo.preload(project: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{bundle.id}")

      # Then
      assert json_response(conn, :ok) == %{
               "app_bundle_id" => bundle.app_bundle_id,
               "download_size" => bundle.download_size,
               "git_branch" => bundle.git_branch,
               "git_commit_sha" => bundle.git_commit_sha,
               "git_ref" => bundle.git_ref,
               "id" => bundle.id,
               "inserted_at" => DateTime.to_iso8601(bundle.inserted_at),
               "install_size" => bundle.install_size,
               "name" => bundle.name,
               "supported_platforms" => Enum.map(bundle.supported_platforms, &Atom.to_string(&1)),
               "type" => Atom.to_string(bundle.type),
               "uploaded_by_account" => bundle.uploaded_by_account.name,
               "url" => url(~p"/#{bundle.project.account.name}/#{bundle.project.name}/bundles/#{bundle.id}"),
               "version" => bundle.version,
               "artifacts" => [
                 %{
                   "artifact_type" => Atom.to_string(artifact_1.artifact_type),
                   "children" => nil,
                   "path" => artifact_1.path,
                   "shasum" => artifact_1.shasum,
                   "size" => artifact_1.size
                 },
                 %{
                   "artifact_type" => Atom.to_string(artifact_2.artifact_type),
                   "children" => nil,
                   "path" => artifact_2.path,
                   "shasum" => artifact_2.shasum,
                   "size" => artifact_2.size
                 }
               ]
             }
    end

    test "returns not found when bundle doesn't exist", %{
      conn: conn,
      user: user,
      project: project
    } do
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

    test "returns not found when bundle belongs to different project", %{conn: conn, user: user} do
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
      response = json_response(conn, :not_found)
      assert response["message"] == "Bundle not found"
    end

    test "returns forbidden when user is not authorized to view bundle", %{conn: conn, user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()

      organization_user =
        AccountsFixtures.user_fixture(account: organization.account, preload: [:account])

      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      bundle =
        BundlesFixtures.bundle_fixture(project: project, uploaded_by_user: organization_user)

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

    test "returns validation error when bundle_id is not a valid UUID", %{conn: conn, user: user, project: project} do
      # Given
      invalid_bundle_id = "com.example.app.#{UUIDv7.generate()}"

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{invalid_bundle_id}")

      # Then
      response = json_response(conn, :bad_request)

      # OpenAPI Spex validates the UUID format and returns an error message
      assert response["message"] =~ "Invalid format"
      assert response["message"] =~ ":uuid"
    end

    test "returns validation error when bundle_id is malformed", %{conn: conn, user: user, project: project} do
      # Given
      invalid_bundle_id = "not-a-uuid-at-all"

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/bundles/#{invalid_bundle_id}")

      # Then
      response = json_response(conn, :bad_request)

      assert response["message"] =~ "Invalid format"
      assert response["message"] =~ ":uuid"
    end
  end
end
