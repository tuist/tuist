defmodule TuistWeb.API.RunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Runs.Build
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    stub(VCS, :enqueue_vcs_pull_request_comment, fn _args -> {:ok, %{}} end)
    :ok
  end

  describe "GET /api/projects/:account_handle/:project_handle/runs" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists two project runs", %{conn: conn, user: user, project: project} do
      # Given
      _run_one =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      run_two = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      run_three = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _run_four = CommandEventsFixtures.command_event_fixture()

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/runs?page_size=2")

      # Then
      response = json_response(conn, :ok)

      # Should return the two most recent runs
      run_urls = Enum.map(response["runs"], & &1["url"])
      assert length(run_urls) == 2
      assert Enum.at(run_urls, 0) =~ run_three.id
      assert Enum.at(run_urls, 1) =~ run_two.id
    end

    test "lists second page", %{conn: conn, user: user, project: project} do
      # Given
      date = DateTime.utc_now()

      run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_targets: ["ATests", "BTests", "CTests"],
          local_test_target_hits: ["ATests", "BTests"],
          remote_test_target_hits: ["CTests"],
          cacheable_targets: ["A", "B", "C"],
          local_cache_target_hits: ["A", "B"],
          remote_cache_target_hits: ["C"],
          created_at: date
        )

      _run_two =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, created_at: date)

      _run_three =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, created_at: date)

      _run_four = CommandEventsFixtures.command_event_fixture(created_at: date)

      # When
      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/runs?page=2&page_size=2")

      # Then
      response = json_response(conn, :ok)

      # Check the returned run
      assert length(response["runs"]) == 1
      run = hd(response["runs"])

      # Check all the expected fields except id and url which we'll check separately
      assert run["git_branch"] == nil
      assert run["git_commit_sha"] == nil
      assert run["cacheable_targets"] == ["A", "B", "C"]
      assert run["command_arguments"] == nil
      assert run["duration"] == 0
      assert run["git_ref"] == nil
      assert run["local_cache_target_hits"] == ["A", "B"]
      assert run["local_test_target_hits"] == ["ATests", "BTests"]
      assert run["macos_version"] == "10.15"
      assert run["name"] == "test"
      assert run["preview_id"] == nil
      assert run["remote_cache_target_hits"] == ["C"]
      assert run["remote_test_target_hits"] == ["CTests"]
      assert run["status"] == "success"
      assert run["subcommand"] == nil
      assert run["swift_version"] == "5.2"
      assert run["test_targets"] == ["ATests", "BTests", "CTests"]
      assert run["tuist_version"] == "4.1.0"
      assert run["ran_at"] == DateTime.to_unix(date)
      assert run["ran_by"] == nil

      # Check that URL contains the UUID
      assert run["url"] =~ run_one.id
    end

    test "lists no runs when there are none", %{conn: conn, user: user, project: project} do
      # Given
      # No runs are created

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/runs")

      # Then
      response = json_response(conn, :ok)

      assert response["runs"] == []
    end

    test "filters runs based on git_ref and name", %{conn: conn, user: user, project: project} do
      # Given
      date = DateTime.utc_now()

      run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/main",
          name: "test",
          created_at: date,
          user_id: user.id
        )

      _run_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/feature",
          name: "test",
          created_at: date,
          user_id: user.id
        )

      _run_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/main",
          name: "build",
          created_at: date,
          user_id: user.id
        )

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs?git_ref=refs/heads/main&name=test"
        )

      # Then
      response = json_response(conn, :ok)

      # Check the returned run
      assert length(response["runs"]) == 1
      run = hd(response["runs"])

      # Check all the expected fields
      assert run["git_branch"] == nil
      assert run["git_commit_sha"] == nil
      assert run["cacheable_targets"] == []
      assert run["command_arguments"] == nil
      assert run["duration"] == 0
      assert run["git_ref"] == "refs/heads/main"
      assert run["local_cache_target_hits"] == []
      assert run["local_test_target_hits"] == []
      assert run["macos_version"] == "10.15"
      assert run["name"] == "test"
      assert run["preview_id"] == nil
      assert run["remote_cache_target_hits"] == []
      assert run["remote_test_target_hits"] == []
      assert run["status"] == "success"
      assert run["subcommand"] == nil
      assert run["swift_version"] == "5.2"
      assert run["test_targets"] == []
      assert run["tuist_version"] == "4.1.0"
      assert run["ran_at"] == DateTime.to_unix(date)
      assert run["ran_by"] == %{"handle" => user.account.name}

      # Check that URL contains the UUID
      assert run["url"] =~ run_one.id
    end

    test "returns forbidden response when the user doesn't have access to the project", %{
      conn: conn
    } do
      # Given
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      # When
      conn = get(conn, "/api/projects/#{another_user.account.name}/#{another_project.name}/runs")

      # Then
      assert response(conn, :forbidden)
    end

    test "returns not found response when the project is not found", %{conn: conn, user: user} do
      # Given
      non_existent_project_name = "non-existent-project"
      project_slug = "#{user.account.name}/#{non_existent_project_name}"

      # When
      {404, _, response_json_string} =
        assert_error_sent :not_found, fn ->
          get(conn, "/api/projects/#{user.account.name}/#{non_existent_project_name}/runs")
        end

      assert Jason.decode!(response_json_string) == %{
               "message" => "The project #{project_slug} was not found."
             }
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/runs" do
    test "creates a new build when authenticatd as user", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          type: "build",
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "machine-123",
          scheme: "App",
          status: :failure,
          category: :incremental,
          issues: [
            %{
              type: "error",
              target: "MyApp",
              project: "MyProject",
              title: "Compilation Error",
              signature: "error_signature_123",
              step_type: "swift_compilation",
              path: "/path/to/file.swift",
              message: "Expected ';' after expression",
              starting_line: 10,
              ending_line: 10,
              starting_column: 5,
              ending_column: 15
            },
            %{
              type: "warning",
              target: "MyApp",
              project: "MyProject",
              title: "Unused Variable",
              signature: "warning_signature_456",
              step_type: "swift_compilation",
              path: "/path/to/another_file.swift",
              message: "Variable 'unused' is never used",
              starting_line: 25,
              ending_line: 25,
              starting_column: 8,
              ending_column: 14
            }
          ],
          files: [
            %{
              type: "swift",
              target: "MyApp",
              project: "MyProject",
              path: "File.swift",
              compilation_duration: 100
            },
            %{
              type: "c",
              target: "MyApp",
              project: "MyProject",
              path: "File.m",
              compilation_duration: 200
            }
          ],
          targets: [
            %{
              name: "MyApp",
              project: "MyProject",
              build_duration: 1000,
              compilation_duration: 2000,
              status: :success
            },
            %{
              name: "MyAppTests",
              project: "MyProject",
              build_duration: 1500,
              compilation_duration: 2500,
              status: :failure
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Build |> Tuist.Repo.all() |> Tuist.ClickHouseRepo.preload([:issues, :files, :targets])

      assert build.duration == 1000
      assert build.macos_version == "11.2.3"
      assert build.xcode_version == "12.4"
      assert build.is_ci == false
      assert build.model_identifier == "machine-123"
      assert build.scheme == "App"
      assert build.project_id == project.id
      assert build.account_id == user.account.id
      assert build.status == :failure
      assert build.category == :incremental

      assert build.issues |> Enum.map(&Map.take(&1, [:type, :message, :build_run_id])) |> Enum.sort_by(& &1.message) == [
               %{
                 type: "error",
                 message: "Expected ';' after expression",
                 build_run_id: build.id
               },
               %{
                 type: "warning",
                 message: "Variable 'unused' is never used",
                 build_run_id: build.id
               }
             ]

      assert build.files |> Enum.map(&Map.take(&1, [:type, :path, :build_run_id])) |> Enum.sort_by(& &1.path) == [
               %{
                 type: "c",
                 path: "File.m",
                 build_run_id: build.id
               },
               %{
                 type: "swift",
                 path: "File.swift",
                 build_run_id: build.id
               }
             ]

      assert build.targets
             |> Enum.map(&Map.take(&1, [:name, :project, :build_run_id, :status]))
             |> Enum.sort_by(& &1.name) == [
               %{
                 name: "MyApp",
                 project: "MyProject",
                 build_run_id: build.id,
                 status: "success"
               },
               %{
                 name: "MyAppTests",
                 project: "MyProject",
                 build_run_id: build.id,
                 status: "failure"
               }
             ]

      assert response == %{
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "creates a new build when authenticatd as project", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> assign(:current_project, project)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          type: "build",
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "machine-123",
          scheme: "App"
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert build.duration == 1000
      assert build.macos_version == "11.2.3"
      assert build.xcode_version == "12.4"
      assert build.is_ci == false
      assert build.model_identifier == "machine-123"
      assert build.scheme == "App"
      assert build.project_id == project.id
      assert build.account_id == user.account.id

      assert response == %{
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "returns an existing build run if it already exists", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)
      id = UUIDv7.generate()

      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
        id: id,
        type: "build",
        duration: 1000,
        is_ci: false
      )

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: id,
          type: "build",
          duration: 1000,
          is_ci: false
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert response == %{
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "creates a new build when non-required parameters are missing", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          duration: 1000,
          is_ci: false
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert build.duration == 1000
      assert build.macos_version == nil
      assert build.xcode_version == nil
      assert build.is_ci == false
      assert build.model_identifier == nil
      assert build.scheme == nil
      assert build.project_id == project.id
      assert build.account_id == user.account.id
      assert build.status == :success

      assert response == %{
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "returns :not_found when project doesn't exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      non_existent_project_name = UUIDv7.generate()
      non_existent_account_name = UUIDv7.generate()
      project_slug = "#{non_existent_account_name}/#{non_existent_project_name}"

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")

      # When
      {404, _, response_json_string} =
        assert_error_sent :not_found, fn ->
          post(
            conn,
            ~p"/api/projects/#{non_existent_account_name}/#{non_existent_project_name}/runs",
            id: UUIDv7.generate(),
            duration: 1000,
            is_ci: false
          )
        end

      assert Jason.decode!(response_json_string) == %{
               "message" => "The project #{project_slug} was not found."
             }
    end

    test "returns forbidden when the user doesn't have permissions to create a build", %{
      conn: conn
    } do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.io")
      project = ProjectsFixtures.project_fixture(preload: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          duration: 1000,
          is_ci: false
        )

      # Then
      assert json_response(conn, :forbidden) == %{
               "message" => "tuist is not authorized to create run"
             }
    end
  end
end
