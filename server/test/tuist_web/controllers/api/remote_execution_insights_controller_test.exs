defmodule TuistWeb.API.RemoteExecutionInsightsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.IngestRepo
  alias Tuist.MCP.Components.Tools.GetRemoteExecutionActivity
  alias Tuist.MCP.Components.Tools.GetRemoteExecutionUsage
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    path = "/api/projects/#{user.account.name}/#{project.name}/remote-execution"
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}

    %{
      conn: Authentication.put_current_user(conn, user),
      user: user,
      project: project,
      path: path,
      args: args
    }
  end

  test "activity returns the scheduler's snapshot and a retryable error when it does not answer", %{
    conn: conn,
    project: project,
    path: path,
    args: args
  } do
    project_id = project.id

    stub(RemoteExecution, :activity, fn %{id: ^project_id} ->
      {:ok,
       %{
         observed_at: ~U[2026-11-17 10:00:05.123456Z],
         running: 1,
         queued: 0,
         actions: [
           %{
             id: Ecto.UUID.generate(),
             state: "running",
             action_digest: "#{String.duplicate("a", 64)}/10",
             invocation_id: "build-1",
             mnemonic: "CppCompile",
             target: "//app:lib",
             vcpus: 4,
             memory_gb: 8,
             since: ~U[2026-11-17 10:00:01.000000Z]
           }
         ],
         invocations: [
           %{
             invocation_id: "build-1",
             command: "build",
             target_patterns: ["//app/..."],
             git_branch: "main",
             git_commit_sha: "",
             is_ci: true,
             started_at: ~U[2026-11-17 09:59:58.000000Z],
             running: 1,
             queued: 0
           }
         ]
       }}
    end)

    response = conn |> get(path <> "/activity") |> json_response(200)
    assert_schema(response, "RemoteExecutionActivity", Spec.spec())

    assert %{
             "observed_at" => "2026-11-17T10:00:05.123Z",
             "running" => 1,
             "queued" => 0,
             "actions" => [
               %{
                 "state" => "running",
                 "invocation_id" => "build-1",
                 "mnemonic" => "CppCompile",
                 "target" => "//app:lib",
                 "vcpus" => 4,
                 "memory_gb" => 8,
                 "since" => "2026-11-17T10:00:01.000Z"
               }
             ],
             "invocations" => [
               %{
                 "invocation_id" => "build-1",
                 "command" => "build",
                 "target_patterns" => ["//app/..."],
                 "is_ci" => true,
                 "started_at" => "2026-11-17T09:59:58.000Z",
                 "running" => 1,
                 "queued" => 0
               }
             ]
           } = response

    refute Map.has_key?(hd(response["actions"]), "id")

    assert %{"structuredContent" => %{"running" => 1}} = GetRemoteExecutionActivity.call(conn, args)

    stub(RemoteExecution, :activity, fn _project -> {:error, :unavailable} end)
    assert conn |> get(path <> "/activity") |> json_response(503)
    assert %{"isError" => true} = GetRemoteExecutionActivity.call(conn, args)
  end

  test "usage covers the requested half-open period of this project only", %{
    conn: conn,
    user: user,
    project: project,
    path: path,
    args: args
  } do
    other = ProjectsFixtures.project_fixture(account_id: user.account.id)

    IngestRepo.insert_all(UsageEvent, [
      event(project, ~N[2026-11-10 09:30:00.000000], 2, 4_000),
      event(project, ~N[2026-11-10 23:59:59.999999], 8, 60_000),
      event(project, ~N[2026-11-11 00:00:00.000000], 2, 1_000),
      event(other, ~N[2026-11-10 12:00:00.000000], 2, 9_000)
    ])

    response =
      conn
      |> get(path <> "/usage", from: "2026-11-09T00:00:00Z", to: "2026-11-11T00:00:00Z")
      |> json_response(200)

    assert_schema(response, "RemoteExecutionUsage", Spec.spec())

    assert %{
             "from" => "2026-11-09T00:00:00Z",
             "to" => "2026-11-11T00:00:00Z",
             "granularity" => "hour",
             "executions" => 2,
             "execution_ms" => 64_000,
             "shapes" => [
               %{"vcpus" => 2, "memory_gb" => 4, "executions" => 1, "execution_ms" => 4_000},
               %{"vcpus" => 8, "memory_gb" => 16, "executions" => 1, "execution_ms" => 60_000}
             ],
             "modes" => [%{"mode" => "scheduled", "executions" => 2}]
           } = response

    assert length(response["series"]) == 48
    assert %{"bucket" => "2026-11-10 09:00", "executions" => 1} = Enum.at(response["series"], 33)

    assert %{"structuredContent" => %{"executions" => 2}} =
             GetRemoteExecutionUsage.call(
               conn,
               Map.merge(args, %{"from" => "2026-11-09T00:00:00Z", "to" => "2026-11-11T00:00:00Z"})
             )

    assert conn |> get(path <> "/usage", from: "2026-11-11T00:00:00Z", to: "2026-11-09T00:00:00Z") |> json_response(400)
    assert conn |> get(path <> "/usage", from: "2024-01-01T00:00:00Z", to: "2026-11-09T00:00:00Z") |> json_response(400)
    assert %{"isError" => true} = GetRemoteExecutionUsage.call(conn, Map.put(args, "from", "yesterday"))
  end

  test "another account's member cannot read the project", %{path: path, args: args} do
    stranger = AccountsFixtures.user_fixture(preload: [:account])
    conn = Authentication.put_current_user(build_conn(), stranger)
    reject(&RemoteExecution.activity/1)

    assert conn |> get(path <> "/activity") |> json_response(403)
    assert conn |> get(path <> "/usage") |> json_response(403)
    assert %{"isError" => true} = GetRemoteExecutionActivity.call(conn, args)
    assert %{"isError" => true} = GetRemoteExecutionUsage.call(conn, args)
  end

  defp event(project, inserted_at, vcpus, duration_ms) do
    %{
      id: UUIDv7.generate(),
      account_id: project.account_id,
      project_id: project.id,
      sandbox_id: UUIDv7.generate(),
      mode: "scheduled",
      vcpus: vcpus,
      memory_mb: vcpus * 2048,
      duration_ms: duration_ms,
      inserted_at: inserted_at
    }
  end
end
