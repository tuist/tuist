defmodule Tuist.MCP.Components.Tools.OnceRunToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetOnceRun
  alias Tuist.MCP.Components.Tools.ListOnceRuns
  alias Tuist.OnceEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :once)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    %{conn: %Plug.Conn{assigns: %{current_user: user}}, user: user, project: project, args: args}
  end

  test "private runs require the project's build-read access", %{user: user, project: project, args: args} do
    id = run(project, host_class: "private-host-secret")
    other_user = AccountsFixtures.user_fixture(preload: [:account])
    sibling = ProjectsFixtures.project_fixture(account_id: user.account.id)

    for assigns <- [
          %{},
          %{current_user: other_user},
          %{current_project: sibling},
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:tests:read"],
              all_projects: true
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:builds:read"],
              all_projects: false,
              project_ids: [sibling.id]
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: other_user.account,
              scopes: ["project:builds:read"],
              all_projects: true
            }
          }
        ],
        {tool, tool_args} <- [{ListOnceRuns, args}, {GetOnceRun, Map.put(args, "run_id", id)}] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               tool.call(%Plug.Conn{assigns: assigns}, tool_args)

      refute text =~ "private-host-secret"
    end

    token = %AuthenticatedAccount{
      account: user.account,
      scopes: ["project:builds:read"],
      all_projects: false,
      project_ids: [project.id]
    }

    assert %{"structuredContent" => %{"host_class" => "private-host-secret"}} =
             GetOnceRun.call(%Plug.Conn{assigns: %{current_subject: token}}, Map.put(args, "run_id", id))
  end

  test "a run ID reused by another project resolves within the requested project only", %{
    conn: conn,
    user: user,
    project: project,
    args: args
  } do
    id = run(project, host_class: "victim-run")
    public = ProjectsFixtures.project_fixture(visibility: :public, build_system: :once)
    run(public, run_id: id, host_class: "attacker-run")

    assert %{"structuredContent" => %{"host_class" => "victim-run"}} =
             GetOnceRun.call(conn, Map.put(args, "run_id", id))

    other = ProjectsFixtures.project_fixture(account_id: user.account.id)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             GetOnceRun.call(conn, %{
               "account_handle" => user.account.name,
               "project_handle" => other.name,
               "run_id" => id
             })

    assert text =~ "not found"
  end

  test "list_once_runs filters by kind and status and paginates", %{conn: conn, project: project, args: args} do
    matching = run(project, kind: "test", exit_status: 1)
    run(project, kind: "test", exit_status: 0)
    run(project, kind: "build", exit_status: 1)

    assert %{"structuredContent" => %{"runs" => [%{"run_id" => ^matching, "kind" => "test"}]}} =
             ListOnceRuns.call(conn, Map.merge(args, %{"kind" => "test", "status" => "failure"}))

    assert %{"structuredContent" => %{"runs" => [_], "pagination_metadata" => %{"total_count" => 3}}} =
             ListOnceRuns.call(conn, Map.merge(args, %{"page" => 2, "page_size" => 2}))

    assert %{"isError" => true} = ListOnceRuns.call(conn, Map.put(args, "kind", "deploy"))
  end

  test "get_once_run returns test totals for test runs", %{conn: conn, project: project, args: args} do
    id = run(project, kind: "test", test_case_count: 3, passed_test_cases: 2, failed_test_cases: 1)

    assert %{"structuredContent" => %{"tests" => %{"test_cases" => 3, "passed" => 2, "failed" => 1}}} =
             GetOnceRun.call(conn, Map.put(args, "run_id", id))
  end

  defp run(project, attrs) do
    attrs = Map.new(attrs)
    run_id = Map.get(attrs, :run_id, UUIDv7.generate())

    {:ok, _} =
      OnceEvents.upsert_run(
        Map.merge(
          %{
            project_id: project.id,
            run_id: run_id,
            kind: "build",
            finalization: "finalized",
            exit_status: 0,
            wall_ms: 1000,
            finalized_at: DateTime.utc_now()
          },
          attrs
        )
      )

    run_id
  end
end
