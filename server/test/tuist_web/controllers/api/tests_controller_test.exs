defmodule TuistWeb.API.TestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns test runs for a project", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :list_test_runs, fn _attrs ->
        {[
           %{
             id: test_run_id,
             duration: 5000,
             status: :success,
             is_ci: true,
             is_flaky: false,
             scheme: "App",
             git_branch: "main",
             git_commit_sha: "abc123",
             ran_at: ~N[2026-01-15 10:00:00]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs ->
        [%{test_run_id: test_run_id, total_tests: 42, ran_tests: 40, skipped_tests: 2}]
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests")

      # Then
      response = json_response(conn, :ok)
      assert length(response["test_runs"]) == 1

      run = hd(response["test_runs"])
      assert run["id"] == test_run_id
      assert run["duration"] == 5000
      assert run["status"] == "success"
      assert run["is_ci"] == true
      assert run["is_flaky"] == false
      assert run["scheme"] == "App"
      assert run["git_branch"] == "main"
      assert run["git_commit_sha"] == "abc123"
      assert run["total_test_count"] == 42
      assert run["ran_tests"] == 40
      assert run["skipped_tests"] == 2

      assert response["pagination_metadata"]["has_next_page"] == false
      assert response["pagination_metadata"]["current_page"] == 1
      assert response["pagination_metadata"]["total_count"] == 1
    end

    test "returns empty list when there are no test runs", %{conn: conn, user: user, project: project} do
      # Given
      stub(Tests, :list_test_runs, fn _attrs ->
        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs -> [] end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests")

      # Then
      response = json_response(conn, :ok)
      assert response["test_runs"] == []
      assert response["pagination_metadata"]["total_count"] == 0
    end

    test "filters test runs by git_branch", %{conn: conn, user: user, project: project} do
      # Given
      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs -> [] end)

      expect(Tests, :list_test_runs, fn attrs ->
        assert %{field: :git_branch, op: :==, value: "main"} in attrs.filters

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests?git_branch=main")

      # Then
      assert json_response(conn, :ok)
    end

    test "filters test runs by status", %{conn: conn, user: user, project: project} do
      # Given
      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs -> [] end)

      expect(Tests, :list_test_runs, fn attrs ->
        assert %{field: :status, op: :==, value: "failure"} in attrs.filters

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests?status=failure")

      # Then
      assert json_response(conn, :ok)
    end

    test "filters test runs by scheme", %{conn: conn, user: user, project: project} do
      # Given
      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs -> [] end)

      expect(Tests, :list_test_runs, fn attrs ->
        assert %{field: :scheme, op: :==, value: "MyApp"} in attrs.filters

        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests?scheme=MyApp")

      # Then
      assert json_response(conn, :ok)
    end

    test "uses zero counts when metrics are not found for a run", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      stub(Tests, :list_test_runs, fn _attrs ->
        {[
           %{
             id: test_run_id,
             duration: 1000,
             status: :success,
             is_ci: false,
             is_flaky: false,
             scheme: nil,
             git_branch: nil,
             git_commit_sha: nil,
             ran_at: nil
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      stub(Analytics, :test_runs_metrics, fn _project_id, _test_runs -> [] end)

      # When
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests")

      # Then
      response = json_response(conn, :ok)
      run = hd(response["test_runs"])
      assert run["total_test_count"] == 0
      assert run["ran_tests"] == 0
      assert run["skipped_tests"] == 0
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/tests")

      # Then
      assert json_response(conn, :forbidden)
    end
  end

  describe "POST /api/:account_handle/:project_handle/tests" do
    setup %{conn: conn} do
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "creates a test run with xcode build system by default", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "xcode"
        assert attrs.macos_version == "15.0"
        assert attrs.xcode_version == "16.0"
        assert attrs.duration == 5000
        assert attrs.is_ci == false

        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "xcode",
           test_case_runs: []
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 5000,
            macos_version: "15.0",
            xcode_version: "16.0",
            is_ci: false,
            status: "success",
            test_modules: [
              %{
                name: "MyTests",
                status: "success",
                duration: 5000,
                test_suites: [],
                test_cases: [
                  %{name: "test_example", status: "success", duration: 100}
                ]
              }
            ]
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end

    test "creates a test run with gradle build system", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "gradle"
        assert attrs.macos_version == ""
        assert attrs.xcode_version == ""
        assert attrs.scheme == "my-android-app"
        assert attrs.duration == 3000
        assert attrs.is_ci == true

        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "gradle",
           test_case_runs: []
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 3000,
            macos_version: "",
            xcode_version: "",
            is_ci: true,
            build_system: "gradle",
            status: "failure",
            scheme: "my-android-app",
            git_branch: "main",
            git_commit_sha: "abc123",
            test_modules: [
              %{
                name: ":app",
                status: "failure",
                duration: 3000,
                test_suites: [
                  %{name: "com.example.LoginTest", status: "failure", duration: 2000}
                ],
                test_cases: [
                  %{
                    name: "testLogin",
                    test_suite_name: "com.example.LoginTest",
                    status: "failure",
                    duration: 1500,
                    failures: [
                      %{
                        message: "Expected true but was false",
                        path: "LoginTest.kt",
                        line_number: 42,
                        issue_type: "assertion_failure"
                      }
                    ]
                  },
                  %{
                    name: "testLogout",
                    test_suite_name: "com.example.LoginTest",
                    status: "success",
                    duration: 500
                  }
                ]
              }
            ]
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end

    test "creates a test run without macos_version (not required)", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "gradle"
        assert is_nil(attrs.macos_version)

        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "gradle",
           test_case_runs: []
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 1000,
            is_ci: false,
            build_system: "gradle",
            status: "success",
            test_modules: []
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end

    test "creates a test run with parameterized test arguments", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        [module] = attrs.test_modules
        [test_case] = module.test_cases
        arguments = test_case.arguments

        assert length(arguments) == 2

        [arg1, arg2] = arguments
        assert arg1.name == ".cardUser"
        assert arg1.status == "failure"
        assert arg1.duration == 500
        assert length(arg1.failures) == 1
        assert hd(arg1.failures).message == "Snapshot does not match"
        assert length(arg1.repetitions) == 2

        assert arg2.name == ".cardAdmin"
        assert arg2.status == "success"

        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "xcode",
           test_case_runs: [
             %{
               id: UUIDv7.generate(),
               name: "profile details",
               module_name: "MyTests",
               suite_name: "ProfileTests",
               arguments: [
                 %{id: UUIDv7.generate(), name: ".cardUser"},
                 %{id: UUIDv7.generate(), name: ".cardAdmin"}
               ]
             }
           ]
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 5000,
            is_ci: false,
            status: "failure",
            test_modules: [
              %{
                name: "MyTests",
                status: "failure",
                duration: 5000,
                test_suites: [
                  %{name: "ProfileTests", status: "failure", duration: 5000}
                ],
                test_cases: [
                  %{
                    name: "profile details",
                    test_suite_name: "ProfileTests",
                    status: "failure",
                    duration: 1000,
                    arguments: [
                      %{
                        name: ".cardUser",
                        status: "failure",
                        duration: 500,
                        failures: [
                          %{
                            message: "Snapshot does not match",
                            path: "ProfileTests.swift",
                            line_number: 22,
                            issue_type: "issue_recorded"
                          }
                        ],
                        repetitions: [
                          %{repetition_number: 1, name: "First Run", status: "success", duration: 200},
                          %{repetition_number: 2, name: "Retry 1", status: "failure", duration: 300}
                        ]
                      },
                      %{
                        name: ".cardAdmin",
                        status: "success",
                        duration: 500
                      }
                    ]
                  }
                ]
              }
            ]
          }
        )

      response = json_response(conn, 200)
      assert %{"type" => "test"} = response
      [test_case_run] = response["test_case_runs"]
      assert test_case_run["name"] == "profile details"
      assert length(test_case_run["arguments"]) == 2
      [arg1, arg2] = test_case_run["arguments"]
      assert arg1["name"] == ".cardUser"
      assert arg2["name"] == ".cardAdmin"
    end

    test "returns preloaded test_case_runs when the test already exists", %{
      conn: conn,
      user: user,
      project: project
    } do
      existing_id = UUIDv7.generate()
      existing_run_id = UUIDv7.generate()

      # Regression test for the %Ecto.Association.NotLoaded{} crash: when
      # the test already exists, get_test must preload test_case_runs so
      # the response reflects what is actually stored, not an empty list.
      expect(Tests, :get_test, fn ^existing_id, opts ->
        assert opts[:preload] == [test_case_runs: :arguments]

        {:ok,
         %Test{
           id: existing_id,
           duration: 1000,
           project_id: project.id,
           build_system: "xcode",
           test_case_runs: [
             %Tuist.Tests.TestCaseRun{
               id: existing_run_id,
               name: "testExample",
               module_name: "MyModule",
               suite_name: "MyModuleTests",
               arguments: []
             }
           ]
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            id: existing_id,
            duration: 1000,
            is_ci: false,
            status: "success",
            test_modules: []
          }
        )

      response = json_response(conn, 200)
      assert response["id"] == existing_id
      assert [run] = response["test_case_runs"]
      assert run["id"] == existing_run_id
      assert run["name"] == "testExample"
    end

    test "enqueues a VCS pull request comment", %{conn: conn, user: user, project: project} do
      test_pid = self()

      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "gradle",
           test_case_runs: []
         }}
      end)

      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn args ->
        send(test_pid, {:vcs_comment_enqueued, args})
        :ok
      end)

      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/projects/#{user.account.name}/#{project.name}/tests",
        %{
          duration: 3000,
          is_ci: true,
          build_system: "gradle",
          status: "success",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/42/merge",
          git_remote_url_origin: "https://github.com/tuist/tuist.git",
          test_modules: []
        }
      )

      assert_received {:vcs_comment_enqueued, args}
      assert args.git_commit_sha == "abc123"
      assert args.git_ref == "refs/pull/42/merge"
      assert args.git_remote_url_origin == "https://github.com/tuist/tuist.git"
      assert args.project_id == project.id
    end

    test "embeds vcs_comment_params in ProcessXcresultWorker args when status is processing", %{
      conn: conn,
      user: user,
      project: project
    } do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           account_id: attrs.account_id,
           is_ci: true,
           git_branch: attrs.git_branch,
           git_commit_sha: attrs.git_commit_sha,
           git_ref: attrs.git_ref,
           macos_version: attrs.macos_version,
           xcode_version: attrs.xcode_version,
           model_identifier: attrs.model_identifier,
           scheme: attrs.scheme,
           ci_run_id: attrs.ci_run_id,
           ci_project_handle: attrs.ci_project_handle,
           ci_host: attrs.ci_host,
           ci_provider: attrs.ci_provider,
           build_run_id: attrs.build_run_id,
           shard_plan_id: attrs.shard_plan_id,
           build_system: "xcode",
           status: "processing",
           test_case_runs: []
         }}
      end)

      reject(&Tuist.VCS.enqueue_vcs_pull_request_comment/1)

      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/projects/#{user.account.name}/#{project.name}/tests",
        %{
          duration: 0,
          macos_version: "15.0",
          xcode_version: "16.0",
          is_ci: true,
          status: "processing",
          scheme: "TuistAcceptanceTests",
          git_commit_sha: "abc123",
          git_ref: "refs/pull/42/merge",
          git_remote_url_origin: "https://github.com/tuist/tuist.git",
          shard_index: 1,
          test_modules: []
        }
      )

      assert_enqueued(
        worker: Tuist.Tests.Workers.ProcessXcresultWorker,
        args: %{
          "vcs_comment_params" => %{
            "git_commit_sha" => "abc123",
            "git_ref" => "refs/pull/42/merge",
            "git_remote_url_origin" => "https://github.com/tuist/tuist.git",
            "project_id" => project.id
          }
        }
      )
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns test run details with metrics", %{conn: conn, user: user, project: project} do
      # Given
      test_run_id = UUIDv7.generate()

      test_run = %Test{
        id: test_run_id,
        project_id: project.id,
        status: "success",
        duration: 5000,
        is_ci: true,
        is_flaky: false,
        scheme: "App",
        macos_version: "14.0",
        xcode_version: "15.0",
        model_identifier: "Mac15,6",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: ~N[2026-01-15 10:00:00]
      }

      stub(Tests, :get_test, fn id ->
        assert id == test_run_id
        {:ok, test_run}
      end)

      stub(Analytics, :get_test_run_metrics, fn id ->
        assert id == test_run_id

        %{
          total_count: 42,
          failed_count: 3,
          flaky_count: 1,
          avg_duration: 120
        }
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["id"] == test_run_id
      assert response["status"] == "success"
      assert response["duration"] == 5000
      assert response["is_ci"] == true
      assert response["is_flaky"] == false
      assert response["scheme"] == "App"
      assert response["macos_version"] == "14.0"
      assert response["xcode_version"] == "15.0"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "abc123"
      assert response["total_test_count"] == 42
      assert response["failed_test_count"] == 3
      assert response["flaky_test_count"] == 1
      assert response["avg_test_duration"] == 120
    end

    test "returns 404 when test run does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      stub(Tests, :get_test, fn _id -> {:error, :not_found} end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{UUIDv7.generate()}"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Test run not found."
    end

    test "returns 404 when test run belongs to a different project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      test_run_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id ->
        {:ok, %Test{id: test_run_id, project_id: other_project.id}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}"
        )

      # Then
      response = json_response(conn, :not_found)
      assert response["message"] == "Test run not found."
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/#{UUIDv7.generate()}"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
