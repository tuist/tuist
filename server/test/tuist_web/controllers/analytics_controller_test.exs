defmodule TuistWeb.AnalyticsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Buffer
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")

    stub(Environment, :github_app_configured?, fn -> true end)
    %{user: user}
  end

  describe "POST /api/analytics" do
    test "errors if it authentices as a project from a non-CI environment", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => command_event.legacy_id,
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}"),
               "test_run_url" => nil
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

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}"),
               "test_run_url" => nil
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
      conn = assign(conn, :selected_project, project)

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

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "id" => response["id"],
               "name" => "generate",
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}"),
               "test_run_url" => nil
             }

      assert command_event.is_ci == true
    end

    test "returns newly created command event with xcode_graph", %{
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

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert response == %{
               "name" => "generate",
               "id" => response["id"],
               "project_id" => project.id,
               "url" => url(~p"/#{account.name}/#{project.name}/runs/#{command_event.id}"),
               "test_run_url" => nil
             }

      assert command_event.cacheable_targets == ["TargetA"]
      assert command_event.local_cache_target_hits == ["TargetA"]
      assert command_event.remote_cache_target_hits == []
      assert command_event.test_targets == ["TargetATests"]
      assert command_event.local_test_target_hits == []
      assert command_event.remote_test_target_hits == ["TargetATests"]

      Tuist.Xcode.XcodeGraph.Buffer.flush()
      Tuist.Xcode.XcodeProject.Buffer.flush()
      Tuist.Xcode.XcodeTarget.Buffer.flush()

      xcode_graph =
        ClickHouseRepo.one(from(xg in XcodeGraph, where: xg.command_event_id == ^command_event.id))

      assert xcode_graph.name == "Graph"
      assert xcode_graph.binary_build_duration == 1000

      xcode_projects =
        ClickHouseRepo.all(from(xp in XcodeProject, where: xp.xcode_graph_id == ^xcode_graph.id))

      assert Enum.map(xcode_projects, & &1.name) == ["ProjectA"]

      command_event = ClickHouseRepo.preload(command_event, [:xcode_targets])
      xcode_targets = Enum.sort_by(command_event.xcode_targets, & &1.name)

      assert Enum.map(xcode_targets, & &1.name) == ["TargetA", "TargetATests"]
      assert Enum.map(xcode_targets, & &1.binary_cache_hash) == ["hash-a", nil]
      assert Enum.map(xcode_targets, & &1.binary_cache_hit) == ["local", "miss"]
      assert Enum.map(xcode_targets, & &1.binary_build_duration) == [1000, nil]
      assert Enum.map(xcode_targets, & &1.selective_testing_hash) == [nil, "hash-a-tests"]
      assert Enum.map(xcode_targets, & &1.selective_testing_hit) == ["miss", "remote"]
    end

    test "returns newly created command event with xcode_graph including subhashes", %{
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
                      product: "framework",
                      bundle_id: "com.example.targeta",
                      product_name: "TargetA",
                      destinations: ["iphone", "ipad"],
                      binary_cache_metadata: %{
                        hash: "hash-a",
                        hit: "local",
                        build_duration: 1000,
                        subhashes: %{
                          sources: "abc123sources",
                          resources: "def456resources",
                          dependencies: "ghi789dependencies",
                          environment: "jkl012environment",
                          deployment_target: "mno345deployment",
                          project_settings: "pqr678projectsettings",
                          target_settings: "stu901targetsettings",
                          additional_strings: ["CUSTOM_FLAG_1", "CUSTOM_FLAG_2"]
                        }
                      }
                    },
                    %{
                      name: "ExternalTarget",
                      product: "static_library",
                      bundle_id: "",
                      product_name: "ExternalTarget",
                      destinations: ["mac"],
                      binary_cache_metadata: %{
                        hash: "hash-external",
                        hit: "remote",
                        build_duration: 500,
                        subhashes: %{
                          external: "external123hash"
                        }
                      }
                    }
                  ]
                }
              ]
            }
          }
        )

      response = json_response(conn, :ok)

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      Tuist.Xcode.XcodeGraph.Buffer.flush()
      Tuist.Xcode.XcodeProject.Buffer.flush()
      Tuist.Xcode.XcodeTarget.Buffer.flush()

      command_event = ClickHouseRepo.preload(command_event, [:xcode_targets])
      xcode_targets = Enum.sort_by(command_event.xcode_targets, & &1.name)

      # Verify target names
      assert Enum.map(xcode_targets, & &1.name) == ["ExternalTarget", "TargetA"]

      # Find each target
      target_a = Enum.find(xcode_targets, &(&1.name == "TargetA"))
      external_target = Enum.find(xcode_targets, &(&1.name == "ExternalTarget"))

      # Verify TargetA metadata
      assert target_a.product == "framework"
      assert target_a.bundle_id == "com.example.targeta"
      assert target_a.product_name == "TargetA"
      assert target_a.destinations == ["iphone", "ipad"]

      # Verify TargetA subhashes
      assert target_a.sources_hash == "abc123sources"
      assert target_a.resources_hash == "def456resources"
      assert target_a.dependencies_hash == "ghi789dependencies"
      assert target_a.environment_hash == "jkl012environment"
      assert target_a.deployment_target_hash == "mno345deployment"
      assert target_a.project_settings_hash == "pqr678projectsettings"
      assert target_a.target_settings_hash == "stu901targetsettings"
      assert target_a.additional_strings == ["CUSTOM_FLAG_1", "CUSTOM_FLAG_2"]
      assert target_a.external_hash == ""

      # Verify ExternalTarget metadata
      assert external_target.product == "static_library"
      assert external_target.destinations == ["mac"]

      # Verify ExternalTarget has only external_hash set
      assert external_target.external_hash == "external123hash"
      assert external_target.sources_hash == ""
      assert external_target.resources_hash == ""
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

      # Flush ingestion buffers to ensure the event is available
      Buffer.flush()

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

      assert %{
               "id" => id,
               "name" => "generate",
               "project_id" => project_id,
               "url" => url
             } = response

      assert is_integer(id)
      assert project_id == project.id
      assert String.contains?(url, "/runs/")
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

      assert %{
               "id" => id,
               "name" => "generate",
               "project_id" => project_id,
               "url" => url
             } = response

      assert Tuist.UUIDv7.valid?(id)
      assert project_id == project.id
      assert String.contains?(url, "/runs/")
    end

    test "returns legacy_id when CLI version header is missing but tuist_version is old", %{
      conn: conn,
      user: user
    } do
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

      assert %{
               "id" => id,
               "name" => "generate",
               "project_id" => project_id,
               "url" => url
             } = response

      assert is_integer(id)
      assert project_id == project.id
      assert String.contains?(url, "/runs/")
    end

    test "returns id when CLI version header is missing but tuist_version is new", %{
      conn: conn,
      user: user
    } do
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

      assert %{
               "id" => id,
               "name" => "generate",
               "project_id" => project_id,
               "url" => url
             } = response

      assert is_binary(id)
      assert Tuist.UUIDv7.valid?(id)
      assert project_id == project.id
      assert String.contains?(url, "/runs/")
    end

    test "creates test run automatically when command is test and no test_run_id provided", %{
      conn: conn,
      user: user
    } do
      # Given
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
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
            name: "test",
            command_arguments: ["test", "MyScheme"],
            duration: 5000,
            tuist_version: "4.56.0",
            swift_version: "5.9",
            macos_version: "14.0",
            is_ci: true,
            client_id: "client-id",
            status: "success"
          }
        )

      # Then
      response = json_response(conn, :ok)

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert command_event.name == "test"
      assert command_event.test_run_id

      # Verify the test run was created
      {:ok, test_run} = Tuist.Runs.get_test(command_event.test_run_id)
      assert test_run.duration == 5000
      assert test_run.macos_version == "14.0"
      assert test_run.xcode_version == "5.9"
      assert test_run.is_ci == true
      assert test_run.project_id == project.id
      assert test_run.account_id == account.id
      assert test_run.scheme == "MyScheme"
      assert test_run.status == "success"

      assert response["test_run_url"] ==
               url(~p"/#{account.name}/#{project.name}/tests/test-runs/#{command_event.test_run_id}")
    end

    test "uses provided test_run_id when test command includes test_run_id", %{
      conn: conn,
      user: user
    } do
      # Given
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # Create a test run first
      {:ok, existing_test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: account.id,
          status: "success"
        )

      # When - send test command with existing test_run_id
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "test",
            command_arguments: ["test", "MyScheme"],
            duration: 3000,
            tuist_version: "4.56.0",
            swift_version: "5.9",
            macos_version: "14.0",
            is_ci: true,
            client_id: "client-id",
            test_run_id: existing_test_run.id
          }
        )

      # Then
      response = json_response(conn, :ok)

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert command_event.test_run_id == existing_test_run.id

      assert response["test_run_url"] ==
               url(~p"/#{account.name}/#{project.name}/tests/test-runs/#{existing_test_run.id}")
    end

    test "does not create test run when CLI version is 4.110.0 or higher", %{
      conn: conn,
      user: user
    } do
      # Given
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When - send test command with CLI version >= 4.110.0
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tuist-cli-version", "4.110.0")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "test",
            command_arguments: ["test", "MyScheme"],
            duration: 5000,
            tuist_version: "4.110.0",
            swift_version: "5.9",
            macos_version: "14.0",
            is_ci: true,
            client_id: "client-id",
            status: "success"
          }
        )

      # Then
      response = json_response(conn, :ok)

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      # Test run should NOT be created for CLI version >= 4.110.0
      assert command_event.test_run_id == nil
      assert response["test_run_url"] == nil
    end

    test "does not create test run for non-test commands when test_run_id not provided", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When - send generate command without test_run_id
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/analytics?project_id=#{account.name}/#{project.name}",
          %{
            name: "generate",
            command_arguments: ["generate", "App"],
            duration: 1000,
            tuist_version: "4.56.0",
            swift_version: "5.9",
            macos_version: "14.0",
            is_ci: false,
            client_id: "client-id"
          }
        )

      # Then
      response = json_response(conn, :ok)

      Buffer.flush()

      {:ok, command_event} = CommandEvents.get_command_event_by_id(response["id"])

      assert command_event.test_run_id == nil
      assert command_event.name == "generate"
    end
  end

  describe "POST /api/runs/:run_id/start" do
    test "starts multipart upload - postgres", %{conn: conn} do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      account = project.account
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      account = project.account
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/some-id.json"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"
      part_number = 3
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  ^account,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      project = Repo.preload(project, :account)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
    test "completes a multipart upload returns a raw error", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, account} = Accounts.get_account_by_id(project.account_id)

      command_event =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      upload_id = "1234"

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"},
        %{part_number: 3, etag: "etag3"}
      ]

      expect(Storage, :multipart_complete_upload, fn object_key,
                                                     ^upload_id,
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}],
                                                     ^account ->
        assert String.contains?(object_key, "#{account.name}/#{project.name}/runs/")
        assert String.ends_with?(object_key, "/result_bundle.zip")
        :ok
      end)

      project = Repo.preload(project, :account)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
    test "creates test action events", %{conn: conn} do
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

      stub(Storage, :object_exists?, fn object_key, _actor ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key, _ ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      project = Repo.preload(project, :account)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

      FunWithFlags.enable(:flaky_test_detection, for_actor: project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end

    test "runs with older CLI versions that send modules", %{conn: conn} do
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

      stub(Storage, :object_exists?, fn object_key, _actor ->
        case object_key do
          ^invocation_record_object_key ->
            true

          ^test_plan_object_key ->
            true
        end
      end)

      stub(Storage, :get_object_as_string, fn object_key, _ ->
        case object_key do
          ^invocation_record_object_key ->
            CommandEventsFixtures.invocation_record_fixture()

          ^test_plan_object_key ->
            CommandEventsFixtures.test_plan_object_fixture()
        end
      end)

      project = Repo.preload(project, :account)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
    end

    test "noops when test_summary is missing - postgres", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event =
        [project_id: project.id]
        |> CommandEventsFixtures.command_event_fixture()
        |> Repo.preload(project: :account)

      stub(Storage, :object_exists?, fn _object_key, _actor -> false end)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/runs/:run_id/start" do
    test "returns unauthorized if authenticated subject doesn't have access to the project", %{
      conn: conn
    } do
      # Given - Create two users and their accounts
      user1 = AccountsFixtures.user_fixture(email: "user1@example.com")
      user2 = AccountsFixtures.user_fixture(email: "user2@example.com")

      account1 = Accounts.get_account_from_user(user1)

      # Create a project under user1's account
      project = ProjectsFixtures.project_fixture(account_id: account1.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # Authenticate as user2 (who doesn't have access to user1's project)
      conn = Authentication.put_current_user(conn, user2)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account1.name}/#{project.name}/runs/#{command_event.id}/start",
          type: "result_bundle"
        )

      # Then - Should return forbidden
      assert json_response(conn, :forbidden) == %{
               "message" => "user2 is not authorized to create run"
             }
    end

    test "starts multipart upload using project from URL", %{conn: conn, user: user} do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      # Authenticate with user instead of project token
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{command_event.id}/start",
          type: "result_bundle"
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end

    test "starts multipart upload for a result_bundle_object using project from URL",
         %{conn: conn, user: user} do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/some-id.json"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      # Authenticate with user instead of project token
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{command_event.id}/start",
          type: "result_bundle_object",
          name: "some-id"
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end

    test "starts multipart upload when run doesn't exist (async insertion)", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      # Use a random UUID that doesn't exist in the database
      nonexistent_run_id = UUIDv7.generate()
      upload_id = "12344"

      # The endpoint should construct the object key even without the run existing
      # It uses the UUID directly for the object key
      object_key = "#{account.name}/#{project.name}/runs/#{nonexistent_run_id}/result_bundle.zip"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{nonexistent_run_id}/start",
          type: "result_bundle"
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
      response_data = response["data"]
      assert response_data["upload_id"] == upload_id
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/runs/:run_id/generate-url" do
    test "returns unauthorized if authenticated subject doesn't have access to the project", %{
      conn: conn
    } do
      # Given - Create two users and their accounts
      user1 = AccountsFixtures.user_fixture(email: "user3@example.com")
      user2 = AccountsFixtures.user_fixture(email: "user4@example.com")

      account1 = Accounts.get_account_from_user(user1)

      # Create a project under user1's account
      project = ProjectsFixtures.project_fixture(account_id: account1.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # Authenticate as user2 (who doesn't have access to user1's project)
      conn = Authentication.put_current_user(conn, user2)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account1.name}/#{project.name}/runs/#{command_event.id}/generate-url",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_part: %{
            part_number: 1,
            upload_id: "test-upload",
            content_length: 100
          }
        )

      # Then - Should return forbidden
      assert json_response(conn, :forbidden) == %{
               "message" => "user4 is not authorized to create run"
             }
    end

    test "generates URL for a part of the multipart upload using project from URL", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"
      part_number = 3
      upload_url = "https://url.com"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  _account,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      # Authenticate with user instead of project token
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{command_event.id}/generate-url",
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
      assert response_data["url"] == upload_url
    end

    test "generates URL for multipart upload when run doesn't exist (async insertion)", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      # Use a random UUID that doesn't exist in the database
      nonexistent_run_id = UUIDv7.generate()
      upload_id = "12344"
      part_number = 3
      upload_url = "https://url.com"

      # The endpoint should construct the object key even without the run existing
      # It uses the UUID directly for the object key
      object_key = "#{account.name}/#{project.name}/runs/#{nonexistent_run_id}/result_bundle.zip"

      expect(Storage, :multipart_generate_url, fn ^object_key,
                                                  ^upload_id,
                                                  ^part_number,
                                                  ^account,
                                                  [expires_in: _, content_length: 100] ->
        upload_url
      end)

      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{nonexistent_run_id}/generate-url",
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
      assert response_data["url"] == upload_url
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/runs/:run_id/complete" do
    test "returns unauthorized if authenticated subject doesn't have access to the project", %{
      conn: conn
    } do
      # Given - Create two users and their accounts
      user1 = AccountsFixtures.user_fixture(email: "user5@example.com")
      user2 = AccountsFixtures.user_fixture(email: "user6@example.com")

      account1 = Accounts.get_account_from_user(user1)

      # Create a project under user1's account
      project = ProjectsFixtures.project_fixture(account_id: account1.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # Authenticate as user2 (who doesn't have access to user1's project)
      conn = Authentication.put_current_user(conn, user2)

      parts = [
        %{part_number: 1, etag: "etag1"},
        %{part_number: 2, etag: "etag2"}
      ]

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account1.name}/#{project.name}/runs/#{command_event.id}/complete",
          command_event_artifact: %{type: "result_bundle"},
          multipart_upload_parts: %{
            parts: parts,
            upload_id: "test-upload"
          }
        )

      # Then - Should return forbidden
      assert json_response(conn, :forbidden) == %{
               "message" => "user6 is not authorized to create run"
             }
    end

    test "completes a multipart upload using project from URL", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
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
                                                     [{1, "etag1"}, {2, "etag2"}, {3, "etag3"}],
                                                     _account ->
        :ok
      end)

      # Authenticate with user instead of project token
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{account.name}/#{project.name}/runs/#{command_event.id}/complete",
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
  end

  describe "PUT /api/projects/:account_handle/:project_handle/runs/:run_id/complete_artifacts_uploads" do
    test "returns unauthorized if authenticated subject doesn't have access to the project", %{
      conn: conn
    } do
      # Given - Create two users and their accounts
      user1 = AccountsFixtures.user_fixture(email: "user7@example.com")
      user2 = AccountsFixtures.user_fixture(email: "user8@example.com")

      account1 = Accounts.get_account_from_user(user1)

      # Create a project under user1's account
      project = ProjectsFixtures.project_fixture(account_id: account1.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # Authenticate as user2 (who doesn't have access to user1's project)
      conn = Authentication.put_current_user(conn, user2)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account1.name}/#{project.name}/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then - Should return forbidden
      assert json_response(conn, :forbidden) == %{
               "message" => "user8 is not authorized to update run"
             }
    end

    test "completes artifacts uploads using project from URL", %{
      conn: conn,
      user: user
    } do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # Authenticate with user instead of project token
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account.name}/#{project.name}/runs/#{command_event.id}/complete_artifacts_uploads")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
    end
  end

  describe "Backward compatibility" do
    test "old routes still work with project-scoped authentication", %{conn: conn} do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      account = project.account
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      upload_id = "12344"

      object_key =
        "#{account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"

      expect(Storage, :multipart_start, fn ^object_key, _account ->
        upload_id
      end)

      # Using project authentication (old way)
      conn = Authentication.put_current_project(conn, project)
      conn = assign(conn, :selected_project, project)

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
  end
end
