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
      assert run["command_arguments"] == ""
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
      assert run["subcommand"] == ""
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
      assert run["command_arguments"] == ""
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
      assert run["subcommand"] == ""
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
    test "creates a new build when authenticated as user", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
          configuration: "Release",
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
      assert build.configuration == "Release"
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
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "creates a new build when authenticatd as project", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "returns an existing build run if it already exists", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "handles race condition when concurrent request creates build first", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)
      id = UUIDv7.generate()

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      existing_build =
        Tuist.Repo.insert!(%Build{
          id: id,
          duration: 1000,
          project_id: project.id,
          account_id: user.account.id,
          is_ci: false,
          status: :success
        })

      call_count = :counters.new(1, [:atomics])

      stub(Tuist.Runs, :get_build, fn ^id ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)
        if count == 0, do: nil, else: existing_build
      end)

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

      response = json_response(conn, :ok)
      assert response["id"] == id
      assert Tuist.Repo.get(Build, id)
    end

    test "creates a new build when non-required parameters are missing", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "build",
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
      assert build.configuration == nil
      assert build.project_id == project.id
      assert build.account_id == user.account.id
      assert build.status == :success
      assert build.ci_run_id == nil
      assert build.ci_project_handle == nil
      assert build.ci_host == nil
      assert build.ci_provider == nil

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }

      response
    end

    test "creates a new build with GitHub CI metadata", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
          is_ci: true,
          ci_run_id: "1234567890",
          ci_project_handle: "tuist/tuist",
          ci_provider: "github"
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert build.duration == 1000
      assert build.is_ci == true
      assert build.ci_run_id == "1234567890"
      assert build.ci_project_handle == "tuist/tuist"
      assert build.ci_host == nil
      assert build.ci_provider == :github
      assert build.project_id == project.id
      assert build.account_id == user.account.id

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new build with GitLab CI metadata including a custom host", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          type: "build",
          duration: 1500,
          is_ci: true,
          ci_run_id: "987654321",
          ci_project_handle: "group/project",
          ci_host: "gitlab.example.com",
          ci_provider: "gitlab"
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert build.duration == 1500
      assert build.is_ci == true
      assert build.ci_run_id == "987654321"
      assert build.ci_project_handle == "group/project"
      assert build.ci_host == "gitlab.example.com"
      assert build.ci_provider == :gitlab

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1500,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new build with cacheable tasks and calculates counts correctly", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When - randomize order of cacheable tasks
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          id: UUIDv7.generate(),
          type: "build",
          duration: 1000,
          is_ci: false,
          cacheable_tasks: [
            %{
              type: "clang",
              status: "hit_remote",
              key: "cache_key_4"
            },
            %{
              type: "swift",
              status: "hit_local",
              key: "cache_key_1"
            },
            %{
              type: "swift",
              status: "hit_remote",
              key: "cache_key_5"
            },
            %{
              type: "swift",
              status: "miss",
              key: "cache_key_3"
            },
            %{
              type: "clang",
              status: "hit_local",
              key: "cache_key_2"
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      assert build.cacheable_tasks_count == 5
      assert build.cacheable_task_local_hits_count == 2
      assert build.cacheable_task_remote_hits_count == 2

      {cacheable_tasks, _meta} =
        Tuist.Runs.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}],
          order_by: [:key],
          order_directions: [:asc]
        })

      expected_tasks = [
        %{type: "swift", status: "hit_local", key: "cache_key_1", build_run_id: build.id},
        %{type: "clang", status: "hit_local", key: "cache_key_2", build_run_id: build.id},
        %{type: "swift", status: "miss", key: "cache_key_3", build_run_id: build.id},
        %{type: "clang", status: "hit_remote", key: "cache_key_4", build_run_id: build.id},
        %{type: "swift", status: "hit_remote", key: "cache_key_5", build_run_id: build.id}
      ]

      actual_tasks = Enum.map(cacheable_tasks, &Map.take(&1, [:type, :status, :key, :build_run_id]))

      assert actual_tasks == expected_tasks

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new build with empty cacheable tasks array", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
          is_ci: false,
          cacheable_tasks: []
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      # Verify counts are 0 for empty array
      assert build.cacheable_tasks_count == 0
      assert build.cacheable_task_local_hits_count == 0
      assert build.cacheable_task_remote_hits_count == 0

      # Verify no cacheable tasks are created in ClickHouse
      {cacheable_tasks, _meta} =
        Tuist.Runs.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}]
        })

      assert cacheable_tasks == []

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new build with CAS outputs", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
          is_ci: false,
          cas_outputs: [
            %{
              node_id: "MyTarget",
              checksum: "abc123def456",
              size: 1024,
              duration: 1500,
              compressed_size: 512,
              operation: "download",
              type: "swiftmodule"
            },
            %{
              node_id: "AnotherTarget",
              checksum: "xyz789",
              size: 2048,
              duration: 2000,
              compressed_size: 1024,
              operation: "upload",
              type: "swift-dependencies"
            },
            %{
              node_id: "ThirdTarget",
              checksum: "def456ghi",
              size: 4096,
              duration: 500,
              compressed_size: 2048,
              operation: "download",
              type: "object"
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      {cas_outputs, _meta} =
        Tuist.Runs.list_cas_outputs(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}],
          order_by: [:node_id],
          order_directions: [:asc]
        })

      expected_outputs = [
        %{
          node_id: "AnotherTarget",
          checksum: "xyz789",
          size: 2048,
          duration: 2000,
          compressed_size: 1024,
          operation: "upload",
          type: "swift-dependencies",
          build_run_id: String.downcase(build.id)
        },
        %{
          node_id: "MyTarget",
          checksum: "abc123def456",
          size: 1024,
          duration: 1500,
          compressed_size: 512,
          operation: "download",
          type: "swiftmodule",
          build_run_id: String.downcase(build.id)
        },
        %{
          node_id: "ThirdTarget",
          checksum: "def456ghi",
          size: 4096,
          duration: 500,
          compressed_size: 2048,
          operation: "download",
          type: "object",
          build_run_id: String.downcase(build.id)
        }
      ]

      actual_outputs =
        Enum.map(
          cas_outputs,
          &Map.take(&1, [:node_id, :checksum, :size, :duration, :compressed_size, :operation, :type, :build_run_id])
        )

      assert actual_outputs == expected_outputs

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "returns :not_found when project doesn't exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
            type: "build",
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
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account])

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "build",
          id: UUIDv7.generate(),
          duration: 1000,
          is_ci: false
        )

      # Then
      assert json_response(conn, :forbidden) == %{
               "message" => "tuist is not authorized to create run"
             }
    end

    test "creates a build when type is not passed (legacy CLI pre-4.107.0)", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
      assert build.is_ci == false
      assert build.project_id == project.id
      assert build.account_id == user.account.id

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new build with cacheable tasks that have cas_output_node_ids", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
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
          is_ci: false,
          cacheable_tasks: [
            %{
              type: "swift",
              status: "hit_local",
              key: "cache_key_1",
              cas_output_node_ids: ["node_id_1", "node_id_2"]
            },
            %{
              type: "clang",
              status: "hit_remote",
              key: "cache_key_2",
              cas_output_node_ids: ["node_id_3"]
            },
            %{
              type: "swift",
              status: "miss",
              key: "cache_key_3",
              cas_output_node_ids: []
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      [build] = Tuist.Repo.all(Build)

      {cacheable_tasks, _meta} =
        Tuist.Runs.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}],
          order_by: [:key],
          order_directions: [:asc]
        })

      expected_tasks = [
        %{
          type: "swift",
          status: "hit_local",
          key: "cache_key_1",
          cas_output_node_ids: ["node_id_1", "node_id_2"],
          build_run_id: build.id
        },
        %{
          type: "clang",
          status: "hit_remote",
          key: "cache_key_2",
          cas_output_node_ids: ["node_id_3"],
          build_run_id: build.id
        },
        %{
          type: "swift",
          status: "miss",
          key: "cache_key_3",
          cas_output_node_ids: [],
          build_run_id: build.id
        }
      ]

      actual_tasks =
        Enum.map(
          cacheable_tasks,
          &Map.take(&1, [:type, :status, :key, :cas_output_node_ids, :build_run_id])
        )

      assert actual_tasks == expected_tasks

      assert response == %{
               "type" => "build",
               "id" => build.id,
               "duration" => 1000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}")
             }
    end

    test "creates a new test run when authenticated as user", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 5000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          model_identifier: "MacBookPro18,3",
          scheme: "MyAppTests",
          status: "success",
          git_commit_sha: "abc123",
          git_branch: "main",
          git_ref: "refs/heads/main",
          test_modules: []
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.duration == 5000
      assert test_run.macos_version == "14.0"
      assert test_run.xcode_version == "15.0"
      assert test_run.is_ci == true
      assert test_run.model_identifier == "MacBookPro18,3"
      assert test_run.scheme == "MyAppTests"
      assert test_run.status == "success"
      assert test_run.git_commit_sha == "abc123"
      assert test_run.git_branch == "main"
      assert test_run.git_ref == "refs/heads/main"
      assert test_run.project_id == project.id
      assert test_run.account_id == user.account.id

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 5000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with test modules, suites, and cases", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 10_000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          status: "failure",
          test_modules: [
            %{
              name: "MyAppTests",
              status: "failure",
              duration: 5000,
              test_suites: [
                %{
                  name: "CalculatorTests",
                  status: "failure",
                  duration: 2000
                }
              ],
              test_cases: [
                %{
                  name: "testAddition",
                  test_suite_name: "CalculatorTests",
                  status: "success",
                  duration: 500,
                  failures: []
                },
                %{
                  name: "testDivision",
                  test_suite_name: "CalculatorTests",
                  status: "failure",
                  duration: 1500,
                  failures: [
                    %{
                      message: ~s{XCTAssertEqual failed: ("0") is not equal to ("1")},
                      path: "Tests/CalculatorTests.swift",
                      line_number: 42,
                      issue_type: "assertion_failure"
                    }
                  ]
                }
              ]
            },
            %{
              name: "MyAppUITests",
              status: "success",
              duration: 5000,
              test_suites: [
                %{
                  name: "UITests",
                  status: "success",
                  duration: 5000
                }
              ],
              test_cases: [
                %{
                  name: "testLaunch",
                  test_suite_name: "UITests",
                  status: "success",
                  duration: 5000,
                  failures: []
                }
              ]
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.duration == 10_000
      assert test_run.status == "failure"
      assert test_run.project_id == project.id
      assert test_run.account_id == user.account.id

      # Verify test modules were stored
      {test_modules, _meta} =
        Tuist.Runs.list_test_module_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test_run.id}],
          order_by: [:name],
          order_directions: [:asc]
        })

      assert length(test_modules) == 2
      [module1, module2] = test_modules

      assert module1.name == "MyAppTests"
      assert module1.status == "failure"
      assert module1.duration == 5000

      assert module2.name == "MyAppUITests"
      assert module2.status == "success"
      assert module2.duration == 5000

      # Verify test cases were stored
      {test_cases, _meta} =
        Tuist.Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test_run.id}],
          order_by: [:name],
          order_directions: [:asc]
        })

      assert length(test_cases) == 3

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 10_000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with skipped status", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 0,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          scheme: "MyAppTests",
          status: "skipped",
          test_modules: []
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.duration == 0
      assert test_run.status == "skipped"
      assert test_run.scheme == "MyAppTests"
      assert test_run.project_id == project.id
      assert test_run.account_id == user.account.id

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 0,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with skipped tests", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 3000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          status: "success",
          test_modules: [
            %{
              name: "MyAppTests",
              status: "success",
              duration: 3000,
              test_suites: [
                %{
                  name: "FeatureTests",
                  status: "skipped",
                  duration: 0
                }
              ],
              test_cases: [
                %{
                  name: "testFeatureDisabled",
                  test_suite_name: "FeatureTests",
                  status: "skipped",
                  duration: 0,
                  failures: []
                }
              ]
            }
          ]
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.status == "success"

      {test_cases, _meta} =
        Tuist.Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test_run.id}]
        })

      assert length(test_cases) == 1
      [test_case] = test_cases
      assert test_case.status == "skipped"

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 3000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with associated build_run_id", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # First create a build run
      build_id = UUIDv7.generate()

      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
        id: build_id,
        type: "build",
        duration: 1000,
        is_ci: false
      )

      # When - create a test run with build_run_id
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 5000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          status: "success",
          build_run_id: build_id,
          test_modules: []
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.build_run_id == build_id
      assert test_run.duration == 5000
      assert test_run.status == "success"

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 5000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with GitHub CI metadata", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 5000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          status: "success",
          ci_run_id: "19683527895",
          ci_project_handle: "tuist/tuist",
          ci_provider: "github",
          test_modules: []
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.duration == 5000
      assert test_run.is_ci == true
      assert test_run.ci_run_id == "19683527895"
      assert test_run.ci_project_handle == "tuist/tuist"
      assert test_run.ci_host == ""
      assert test_run.ci_provider == "github"
      assert test_run.project_id == project.id
      assert test_run.account_id == user.account.id

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 5000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end

    test "creates a new test run with GitLab CI metadata including a custom host", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account], email: "tuist@tuist.dev")
      project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

      # When
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/runs",
          type: "test",
          duration: 8000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          status: "failure",
          ci_run_id: "987654321",
          ci_project_handle: "group/project",
          ci_host: "gitlab.example.com",
          ci_provider: "gitlab",
          test_modules: []
        )

      # Then
      response = json_response(conn, :ok)
      {:ok, test_run} = Tuist.Runs.get_test(response["id"])

      assert test_run.duration == 8000
      assert test_run.is_ci == true
      assert test_run.ci_run_id == "987654321"
      assert test_run.ci_project_handle == "group/project"
      assert test_run.ci_host == "gitlab.example.com"
      assert test_run.ci_provider == "gitlab"

      assert response == %{
               "type" => "test",
               "id" => test_run.id,
               "duration" => 8000,
               "project_id" => project.id,
               "url" => url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
             }
    end
  end
end
