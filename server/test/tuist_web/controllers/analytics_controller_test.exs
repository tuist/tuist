defmodule TuistWeb.AnalyticsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.Xcode.Clickhouse.XcodeGraph
  alias Tuist.Xcode.Clickhouse.XcodeProject
  alias Tuist.Xcode.Postgres.XcodeGraph, as: PGXcodeGraph
  alias Tuist.Xcode.Postgres.XcodeProject, as: PGXcodeProject
  alias Tuist.Xcode.Postgres.XcodeTarget, as: PGXcodeTarget
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")

    stub(Environment, :github_app_configured?, fn -> true end)
    %{user: user}
  end

  describe "POST /api/analytics" do
    test "returns newly created command event - postgres", %{conn: conn, user: user} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      ran_at_string = "2025-02-28T15:51:12Z"

      {:ok, ran_at, _} =
        DateTime.from_iso8601(ran_at_string)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            ran_at: ran_at_string,
            params: %{
              cacheable_targets: ["target1", "target2"],
              local_cache_target_hits: ["target1"],
              remote_cache_target_hits: ["target2"]
            },
            is_ci: false,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.ran_at == ran_at
      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
      assert command_event.cacheable_targets == ["target1", "target2"]
    end

    test "errors if it authentices as a project from a non-CI environment", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn = Authentication.put_current_project(conn, project)

      ran_at_string = "2025-02-28T15:51:12Z"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            ran_at: ran_at_string,
            params: %{
              cacheable_targets: ["target1", "target2"],
              local_cache_target_hits: ["target1"],
              remote_cache_target_hits: ["target2"]
            },
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      assert json_response(conn, :bad_request) == %{
               "message" =>
                 "Project authentication using a project-scoped token is not supported from non-CI environments. If you are running this from a CI environment, you can use the environment variable CI=1 to indicate so."
             }
    end

    test "returns newly created command event when the date is missing - postgres", %{conn: conn, user: user} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      date = ~U[2025-02-28 15:51:12Z]

      stub(DateTime, :utc_now, fn -> date end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            is_ci: false,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert command_event.ran_at == date
    end

    test "returns newly created preview command event - postgres", %{conn: conn, user: user} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      preview = AppBuildsFixtures.app_build_fixture(project: project, display_name: "App")

      expect(VCS, :post_vcs_pull_request_comment, fn _ ->
        :ok
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "share",
            subcommand: "",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            preview_id: preview.id,
            is_ci: false,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response["name"] == "share"
      assert command_event.preview_id == preview.id
    end

    test "returns newly created command event when cacheable analytics are missing", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => command_event.id,
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.is_ci == false
      assert command_event.client_id == "client-id"
    end

    test "returns newly created command event with status failure and error message", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id",
            status: "failure",
            error_message: "An error occurred"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.status == :failure
      assert command_event.error_message == "An error occurred"
      assert command_event.user_id == user.id
    end

    test "returns newly created command event when CI and authenticated as a project", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{
              cacheable_targets: ["target1", "target2"],
              local_cache_target_hits: ["target1"],
              remote_cache_target_hits: ["target2"]
            },
            is_ci: true,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "id" => response["id"],
               "name" => "generate",
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.is_ci == true
    end

    test "returns newly created command event with xcode_graph - postgres", %{
      conn: conn,
      user: user
    } do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id",
            xcode_graph: %{
              name: "Graph",
              binary_build_duration: 1000,
              projects: [
                %{
                  name: "ProjectA",
                  path: ".",
                  targets: [
                    %{
                      name: "TargetA",
                      binary_cache_metadata: %{hash: "hash-a", hit: "local", build_duration: 1000}
                    },
                    %{
                      name: "TargetATests",
                      selective_testing_metadata: %{hash: "hash-a-tests", hit: "remote"}
                    }
                  ]
                }
              ]
            }
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.cacheable_targets == ["TargetA"]
      assert command_event.local_cache_target_hits == ["TargetA"]
      assert command_event.remote_cache_target_hits == []
      assert command_event.test_targets == ["TargetATests"]
      assert command_event.local_test_target_hits == []
      assert command_event.remote_test_target_hits == ["TargetATests"]

      xcode_graph =
        Repo.one(from(xg in PGXcodeGraph, where: xg.command_event_id == ^command_event.id))

      assert xcode_graph.name == "Graph"
      assert xcode_graph.binary_build_duration == 1000

      xcode_projects =
        Repo.all(from(xp in PGXcodeProject, where: xp.xcode_graph_id == ^xcode_graph.id))

      assert Enum.map(xcode_projects, & &1.name) == ["ProjectA"]

      xcode_project = hd(xcode_projects)

      xcode_targets =
        Repo.all(
          from(xt in PGXcodeTarget,
            where: xt.xcode_project_id == ^xcode_project.id,
            order_by: xt.name
          )
        )

      assert Enum.map(xcode_targets, & &1.name) == ["TargetA", "TargetATests"]
      assert Enum.map(xcode_targets, & &1.binary_cache_hash) == ["hash-a", nil]
      assert Enum.map(xcode_targets, & &1.binary_cache_hit) == [:local, nil]
      assert Enum.map(xcode_targets, & &1.binary_build_duration) == [1000, nil]
      assert Enum.map(xcode_targets, & &1.selective_testing_hash) == [nil, "hash-a-tests"]
      assert Enum.map(xcode_targets, & &1.selective_testing_hit) == [nil, :remote]
    end

    test "returns newly created command event with xcode_graph - clickhouse", %{
      conn: conn,
      user: user
    } do
      stub(Environment, :clickhouse_configured?, fn -> true end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> true end)

      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            subcommand: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id",
            xcode_graph: %{
              name: "Graph",
              binary_build_duration: 1000,
              projects: [
                %{
                  name: "ProjectA",
                  path: ".",
                  targets: [
                    %{
                      name: "TargetA",
                      binary_cache_metadata: %{hash: "hash-a", hit: "local", build_duration: 1000}
                    },
                    %{
                      name: "TargetATests",
                      selective_testing_metadata: %{hash: "hash-a-tests", hit: "remote"}
                    }
                  ]
                }
              ]
            }
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
             }

      assert command_event.cacheable_targets == ["TargetA"]
      assert command_event.local_cache_target_hits == ["TargetA"]
      assert command_event.remote_cache_target_hits == []
      assert command_event.test_targets == ["TargetATests"]
      assert command_event.local_test_target_hits == []
      assert command_event.remote_test_target_hits == ["TargetATests"]

      xcode_graph =
        ClickHouseRepo.one(from(xg in XcodeGraph, where: xg.command_event_id == ^command_event.id))

      assert xcode_graph.name == "Graph"
      assert xcode_graph.binary_build_duration == 1000

      xcode_projects =
        ClickHouseRepo.all(from(xp in XcodeProject, where: xp.xcode_graph_id == ^xcode_graph.id))

      assert Enum.map(xcode_projects, & &1.name) == ["ProjectA"]

      xcode_targets = Tuist.Xcode.xcode_targets_for_command_event(command_event.id)

      assert Enum.map(xcode_targets, & &1.name) == ["TargetA", "TargetATests"]
      assert Enum.map(xcode_targets, & &1.binary_cache_hash) == ["hash-a", nil]
      assert Enum.map(xcode_targets, & &1.binary_cache_hit) == [:local, :miss]
      assert Enum.map(xcode_targets, & &1.binary_build_duration) == [1000, nil]
      assert Enum.map(xcode_targets, & &1.selective_testing_hash) == [nil, "hash-a-tests"]
      assert Enum.map(xcode_targets, & &1.selective_testing_hit) == [:miss, :remote]
    end

    test "returns newly created command event with build_run_id - postgres", %{conn: conn, user: user} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      {:ok, build_run} = RunsFixtures.build_fixture(project_id: project.id, user_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "build",
            subcommand: "build",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id",
            build_run_id: build_run.id
          }
        )

      response = json_response(conn, :ok)

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])
      command_event = Repo.preload(command_event, :build_run)

      assert response == %{
               "name" => "build",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/builds/build-runs/#{build_run.id}")
             }

      assert command_event.build_run.id == build_run.id
      command_event_with_build_run = Repo.preload(command_event, :build_run)
      assert command_event_with_build_run.build_run.id == build_run.id
    end

    test "returns command event URL with runs route when build_run_id is not provided", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "build",
            subcommand: "build",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            params: %{},
            is_ci: false,
            client_id: "client-id"
          }
        )

      response = json_response(conn, :ok)
      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response["url"] == url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}")
    end

    test "returns legacy_id as id for CLI versions below 4.56", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tuist-cli-version", "4.55.0")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "4.55.0",
            swift_version: "5.0",
            macos_version: "10.15",
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      # For CLI < 4.56, the id field should be a legacy_id (integer)
      assert is_integer(response["id"])
      assert response["name"] == "generate"
      assert response["project_id"] == project.id
      assert String.contains?(response["url"], "/runs/")
      refute Map.has_key?(response, "uuid")
    end

    test "returns id as id for CLI versions 4.56 and above", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tuist-cli-version", "4.56.0")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "4.56.0",
            swift_version: "5.0",
            macos_version: "10.15",
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      # For CLI >= 4.56, the id field should be a UUID (string)
      assert is_binary(response["id"])
      assert String.match?(response["id"], ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      assert response["name"] == "generate"
      assert response["project_id"] == project.id
      assert String.contains?(response["url"], "/runs/")
      refute Map.has_key?(response, "uuid")
    end

    test "returns id as id when CLI version header is missing", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            command_arguments: ["App"],
            duration: 100,
            tuist_version: "1.0.0",
            swift_version: "5.0",
            macos_version: "10.15",
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      # When CLI version header is missing, should default to new behavior (UUID)
      assert is_binary(response["id"])
      assert String.match?(response["id"], ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      assert response["name"] == "generate"
      assert response["project_id"] == project.id
      assert String.contains?(response["url"], "/runs/")
      refute Map.has_key?(response, "uuid")
    end
  end

  describe "POST /api/runs/:run_id/start" do
    test "starts multipart upload - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_start, fn ^object_key ->
        upload_id
      end)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/start",
          type: "result_bundle"
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end

    test "starts multipart upload for a result_bundle_object - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/some-id.json"

      expect(Storage, :multipart_start, fn ^object_key ->
        upload_id
      end)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/start",
          type: "result_bundle_object",
          name: "some-id"
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end
  end

  describe "POST /api/runs/:run_id/generate-url" do
    test "generates URL for a part of the multipart upload - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"
      part_number = 3
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/generate-url",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_part: %{
            part_number: part_number,
            upload_id: upload_id,
            content_length: 100
          }
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["url"] == "https://url.com"
    end
  end

  describe "POST /api/runs/:run_id/complete" do
    test "completes a multipart upload returns a raw error - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "1234"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      expect(Storage, :multipart_complete_upload, fn ^object_key,
                                                     ^upload_id,
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/complete",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_parts: %{
            parts: parts,
            upload_id: upload_id
          }
        )

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end

    test "completes a multipart upload returns a raw error - clickhouse", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> true end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> true end)

      project = ProjectsFixtures.project_fixture()
      account = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "1234"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      expect(Storage, :multipart_complete_upload, fn ^object_key,
                                                     ^upload_id,
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}] ->
        :ok
      end)

      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/runs/#{command_event.id}/complete",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_parts: %{
            parts: parts,
            upload_id: upload_id
          }
        )

      response = json_response(conn, :no_content)
      assert response == %{}
    end
  end

  describe "PUT /api/runs/:run_id/complete_artifacts_uploads" do
    test "creates test action events - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        [project_id: project.id]
        |> CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(
          name: "MainApp",
          path: "App",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(name: "AppTests", xcode_project_id: xcode_project.id)

      xcode_project_two =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework1",
          path: "Framework1",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_two =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework1Tests",
          xcode_project_id: xcode_project_two.id
        )

      xcode_project_three =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework2",
          path: "Framework2",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_three =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework2Tests",
          xcode_project_id: xcode_project_three.id
        )

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      stub(Storage, :object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      conn = Authentication.put_current_project(conn, project)

      FunWithFlags.enable(:flaky_test_detection, for_actor: project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        from(
          t in TestCaseRun,
          where: t.command_event_id == ^command_event.id
        )
        |> Repo.all()
        |> Repo.preload(:test_case)
        |> Enum.map(& &1.test_case.identifier)
        |> Enum.sort()

      # Postgres tests don't have XcodeGraphs, so no test case runs are created
      assert Enum.empty?(test_case_runs) == true
    end

    test "runs with older CLI versions that send modules - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        [project_id: project.id]
        |> CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(
          name: "MainApp",
          path: "App",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target =
        XcodeFixtures.xcode_target_fixture(name: "AppTests", xcode_project_id: xcode_project.id)

      xcode_project_two =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework1",
          path: "Framework1",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_two =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework1Tests",
          xcode_project_id: xcode_project_two.id
        )

      xcode_project_three =
        XcodeFixtures.xcode_project_fixture(
          name: "Framework2",
          path: "Framework2",
          xcode_graph_id: xcode_graph.id
        )

      _xcode_target_three =
        XcodeFixtures.xcode_target_fixture(
          name: "Framework2Tests",
          xcode_project_id: xcode_project_three.id
        )

      base_path =
        "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"

      invocation_record_object_key =
        "#{base_path}/invocation_record.json"

      test_plan_object_key =
        "#{base_path}/0~_nJcMfmYtL75ZA_SPkjI1RYzgbEkjbq_o2hffLy4RQuPOW81Uu0xIwZX0ntR4Tof5xv2Jwe8opnwD7IVBQ_VOQ==.json"

      stub(Storage, :object_exists?, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      conn = Authentication.put_current_project(conn, project)

      FunWithFlags.enable(:flaky_test_detection, for_actor: project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads",
          modules: [
            %{
              name: "AppTests",
              project_identifier: "App/MainApp.xcodeproj",
              hash: "app-module_hash"
            },
            %{
              name: "Framework1Tests",
              project_identifier: "Framework1/Framework1.xcodeproj",
              hash: "framework1-module_hash"
            },
            %{
              name: "Framework2Tests",
              project_identifier: "Framework2/Framework2.xcodeproj",
              hash: "framework2-module_hash"
            }
          ]
        )

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        from(
          t in TestCaseRun,
          where: t.command_event_id == ^command_event.id
        )
        |> Repo.all()
        |> Repo.preload(:test_case)
        |> Enum.map(& &1.test_case.identifier)
        |> Enum.sort()

      # Postgres tests don't have XcodeGraphs, so no test case runs are created
      assert Enum.empty?(test_case_runs) == true
    end

    test "noops when test_summary is missing - postgres", %{conn: conn} do
      stub(Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)

      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        [project_id: project.id]
        |> CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      stub(Storage, :object_exists?, fn _ -> false end)
      conn = Authentication.put_current_project(conn, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}

      test_case_runs =
        Repo.all(from(t in TestCaseRun, where: t.command_event_id == ^command_event.id))

      assert Enum.empty?(test_case_runs) == true
    end
  end
end
