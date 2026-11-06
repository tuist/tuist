defmodule TuistWeb.API.ReportReplayTest do
  @moduledoc """
  A client retries a report whose response it lost. A retry carrying the id of
  a report the server already accepted must get the first response back and
  create nothing, even before the ingestion buffers flush.
  """
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.Gradle.Build
  alias Tuist.MCP.Events.Publisher
  alias Tuist.Tests.Test
  alias Tuist.Tests.Workers.ProcessXcresultWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{conn: Authentication.put_current_user(conn, user), user: user, project: project}
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  defp flush_buffers do
    Tuist.Tests.Test.Buffer.flush()
    Tuist.Tests.TestCaseRun.Buffer.flush()
    Tuist.CommandEvents.Event.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()
    Tuist.Gradle.Build.Buffer.flush()
    Tuist.Gradle.Task.Buffer.flush()
  end

  defp count(schema, project) do
    ClickHouseRepo.aggregate(from(row in schema, where: row.project_id == ^project.id), :count)
  end

  defp test_run_body(attrs) do
    Map.merge(
      %{
        duration: 1000,
        macos_version: "15.0",
        xcode_version: "16.0",
        is_ci: true,
        status: "success",
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1000,
            test_suites: [],
            test_cases: [%{name: "test_example", status: "success", duration: 100}]
          }
        ]
      },
      attrs
    )
  end

  defp command_event_body(attrs) do
    Map.merge(
      %{
        name: "generate",
        command_arguments: ["App"],
        duration: 100,
        tuist_version: "4.200.0",
        swift_version: "6.0",
        macos_version: "15.0",
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
              targets: [%{name: "TargetA", binary_cache_metadata: %{hash: "hash-a", hit: "local"}}]
            }
          ]
        }
      },
      attrs
    )
  end

  defp gradle_build_body(attrs) do
    Map.merge(
      %{
        duration_ms: 400,
        status: "failure",
        tasks: [%{task_path: ":app:compile", outcome: "failed", duration_ms: 300}]
      },
      attrs
    )
  end

  describe "POST /api/projects/:account_handle/:project_handle/tests" do
    test "a retry with the same id returns the first response and creates nothing", %{
      conn: conn,
      user: user,
      project: project
    } do
      path = "/api/projects/#{user.account.name}/#{project.name}/tests"
      body = test_run_body(%{id: UUIDv7.generate()})

      first = conn |> post_json(path, body) |> json_response(:ok)
      retry = build_conn() |> Authentication.put_current_user(user) |> post_json(path, body) |> json_response(:ok)

      assert retry == first
      assert [%{"id" => _}] = first["test_case_runs"]

      flush_buffers()
      assert count(Test, project) == 1
      assert count(Tuist.Tests.TestCaseRun, project) == 1
    end

    test "requests without an id create distinct runs", %{conn: conn, user: user, project: project} do
      path = "/api/projects/#{user.account.name}/#{project.name}/tests"

      first = conn |> post_json(path, test_run_body(%{})) |> json_response(:ok)

      second =
        build_conn()
        |> Authentication.put_current_user(user)
        |> post_json(path, test_run_body(%{}))
        |> json_response(:ok)

      refute first["id"] == second["id"]
      flush_buffers()
      assert count(Test, project) == 2
    end

    test "a retry after scheduling failed schedules the processing once and returns the run", %{
      conn: conn,
      user: user,
      project: project
    } do
      path = "/api/projects/#{user.account.name}/#{project.name}/tests"
      id = UUIDv7.generate()
      body = %{id: id, duration: 0, is_ci: false, status: "processing", test_modules: []}
      attempts = :counters.new(1, [])

      stub(Oban, :insert, fn changeset ->
        :counters.add(attempts, 1, 1)

        if :counters.get(attempts, 1) == 1,
          do: {:error, :database_unavailable},
          else: Mimic.call_original(Oban, :insert, [changeset])
      end)

      assert conn |> post_json(path, body) |> json_response(:service_unavailable) == %{
               "message" => "The test run could not be scheduled for processing"
             }

      retry = build_conn() |> Authentication.put_current_user(user) |> post_json(path, body) |> json_response(:ok)
      assert retry["id"] == id

      again = build_conn() |> Authentication.put_current_user(user) |> post_json(path, body) |> json_response(:ok)
      assert again == retry

      assert [%Oban.Job{args: %{"test_run_id" => ^id}}] = all_enqueued(worker: ProcessXcresultWorker)
      assert :counters.get(attempts, 1) == 2
    end
  end

  describe "POST /api/analytics" do
    test "a retry with the same id returns the first response and creates nothing", %{
      conn: conn,
      user: user,
      project: project
    } do
      path = "/api/analytics?project_id=#{user.account.name}/#{project.name}"
      body = command_event_body(%{id: UUIDv7.generate()})

      first = conn |> post_json(path, body) |> json_response(:ok)
      retry = build_conn() |> Authentication.put_current_user(user) |> post_json(path, body) |> json_response(:ok)

      assert retry == first
      assert first["id"] == body.id

      flush_buffers()
      assert count(Event, project) == 1

      assert ClickHouseRepo.aggregate(
               from(graph in Tuist.Xcode.XcodeGraph, where: graph.command_event_id == ^body.id),
               :count
             ) == 1
    end

    test "requests without an id create distinct command events", %{conn: conn, user: user, project: project} do
      path = "/api/analytics?project_id=#{user.account.name}/#{project.name}"

      first = conn |> post_json(path, command_event_body(%{})) |> json_response(:ok)

      second =
        build_conn()
        |> Authentication.put_current_user(user)
        |> post_json(path, command_event_body(%{}))
        |> json_response(:ok)

      refute first["id"] == second["id"]
      flush_buffers()
      assert count(Event, project) == 2
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/gradle/builds" do
    test "a retry with the same id returns the first response and creates nothing", %{
      conn: conn,
      user: user,
      project: project
    } do
      test_pid = self()
      stub(Publisher, :publish, fn event, _payload, _key -> send(test_pid, {:published, event}) end)

      path = "/api/projects/#{user.account.name}/#{project.name}/gradle/builds"
      body = gradle_build_body(%{id: UUIDv7.generate()})

      first = conn |> post_json(path, body) |> json_response(:created)
      retry = build_conn() |> Authentication.put_current_user(user) |> post_json(path, body) |> json_response(:created)

      assert retry == first
      assert first["id"] == body.id

      flush_buffers()
      assert count(Build, project) == 1
      assert count(Tuist.Gradle.Task, project) == 1
      assert_received {:published, "build.failed"}
      refute_received {:published, "build.failed"}
    end

    test "requests without an id create distinct builds", %{conn: conn, user: user, project: project} do
      path = "/api/projects/#{user.account.name}/#{project.name}/gradle/builds"

      first = conn |> post_json(path, gradle_build_body(%{status: "success"})) |> json_response(:created)

      second =
        build_conn()
        |> Authentication.put_current_user(user)
        |> post_json(path, gradle_build_body(%{status: "success"}))
        |> json_response(:created)

      refute first["id"] == second["id"]
      flush_buffers()
      assert count(Build, project) == 2
    end
  end
end
