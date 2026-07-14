defmodule TuistWeb.RunnerWorkflowLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "workflow-detail-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  defp enqueue_job(account, attrs) do
    :ok =
      Jobs.enqueue(
        Map.merge(
          %{
            account_id: account.id,
            fleet_name: "fleet-w",
            repository: "tuist/tuist",
            run_attempt: 1,
            head_branch: "main",
            head_sha: "deadbee"
          },
          attrs
        )
      )
  end

  test "renders the workflow header, analytics widgets, and the runs table", %{conn: conn, account: account} do
    enqueue_job(account, %{
      workflow_job_id: 90_001,
      workflow_run_id: 900_010,
      workflow_name: "Server",
      job_name: "Docker build"
    })

    # Walk the job to completed so the success-rate widget renders a
    # real value (otherwise the success_rate query returns nil).
    {:ok, candidate} = Jobs.pick_queued("fleet-w", [])
    :ok = Jobs.record_claimed(candidate, "pod-w", DateTime.utc_now())
    :ok = Jobs.record_running(90_001, "runner-w")
    {:ok, _} = Jobs.complete(90_001, "success")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")

    assert html =~ ~s(data-part="back-button")
    assert html =~ "Server"
    assert html =~ "tuist/tuist"
    assert html =~ "Total jobs"
    assert html =~ "queue time"
    # The table is now a list of runs, not jobs.
    assert html =~ ~s(data-part="runner-workflow-runs-card")
    assert html =~ "runner-workflow-runs-row-900010"
  end

  test "lists runs scoped to the requested workflow", %{conn: conn, account: account} do
    enqueue_job(account, %{
      workflow_job_id: 91_001,
      workflow_run_id: 910_010,
      workflow_name: "Server",
      head_branch: "server-branch"
    })

    enqueue_job(account, %{
      workflow_job_id: 91_002,
      workflow_run_id: 910_020,
      workflow_name: "Release",
      head_branch: "release-branch"
    })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")

    assert html =~ "server-branch"
    refute html =~ "release-branch"
  end

  test "an in-progress run renders a Running badge", %{conn: conn, account: account} do
    enqueue_job(account, %{workflow_job_id: 91_500, workflow_run_id: 915_000, workflow_name: "Server", head_branch: "wip"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")

    assert html =~ "runner-workflow-runs-row-915000"
    assert html =~ "Running"
    # The whole row links to the run detail.
    assert html =~ "/runners/runs/915000"
  end

  test "paginates when the workflow has more than one page of runs", %{conn: conn, account: account} do
    # @page_size on the workflow detail is 20; 21 distinct runs → a
    # Prev/Next strip, 20 rows on page 1 and 1 on page 2.
    Enum.each(1..21, fn i ->
      enqueue_job(account, %{
        workflow_job_id: 92_000 + i,
        workflow_run_id: (92_000 + i) * 10,
        workflow_name: "Server",
        head_branch: "branch-#{i}"
      })
    end)

    {:ok, _lv, page_1} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")
    {:ok, _lv, page_2} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server?page=2")

    assert page_1 =~ "Next"
    assert page_1 =~ "Prev"
    assert run_row_count(page_1) == 20
    assert run_row_count(page_2) == 1
  end

  test "404s for an unauthorised account name", %{conn: conn} do
    %{account: other_account} =
      AccountsFixtures.organization_fixture(
        name: "other-org-#{System.unique_integer([:positive])}",
        preload: [:account]
      )

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{other_account.name}/runners/workflows/tuist/tuist/Server")
    end
  end

  defp run_row_count(html) do
    length(String.split(html, "runner-workflow-runs-row-")) - 1
  end
end
