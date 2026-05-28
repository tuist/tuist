defmodule TuistWeb.RunnerJobLogsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "runner-log-dl-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn = conn |> assign(:selected_account, account) |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  defp enqueue(account, workflow_job_id, workflow_run_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: workflow_run_id,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })
  end

  test "streams the full log as a downloadable text file", %{conn: conn, account: account} do
    enqueue(account, 32_001, 320_010)

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 32_001,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "first log line"
        },
        %{
          workflow_job_id: 32_001,
          account_id: account.id,
          line_number: 2,
          ts: ~U[2026-05-28 12:00:01.000000Z],
          message: "second log line"
        }
      ])

    conn = get(conn, ~p"/#{account.name}/runners/runs/320010/jobs/32001/logs.txt")

    assert response_content_type(conn, :txt) =~ "text/plain"

    {"content-disposition", disposition} = List.keyfind(conn.resp_headers, "content-disposition", 0)
    assert disposition =~ "attachment"
    assert disposition =~ "runner-job-32001.log"

    body = response(conn, 200)
    assert body =~ "first log line"
    assert body =~ "second log line"
  end

  test "404s when the job belongs to another account", %{conn: conn, account: account} do
    other = AccountsFixtures.user_fixture().account
    enqueue(other, 32_101, 321_010)

    assert_raise NotFoundError, fn ->
      get(conn, ~p"/#{account.name}/runners/runs/321010/jobs/32101/logs.txt")
    end
  end
end
