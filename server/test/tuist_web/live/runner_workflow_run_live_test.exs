defmodule TuistWeb.RunnerWorkflowRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.IngestRepo
  alias Tuist.Runners
  alias Tuist.Runners.Job
  alias Tuist.Runners.Jobs
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "run-detail-org-#{System.unique_integer([:positive])}",
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
            fleet_name: "fleet-r",
            repository: "tuist/tuist",
            workflow_name: "Server",
            run_attempt: 1,
            head_branch: "main",
            head_sha: "deadbee"
          },
          attrs
        )
      )
  end

  defp insert_completed(account, attrs) do
    row =
      Map.merge(
        %{
          account_id: account.id,
          fleet_name: "fleet-r",
          repository: "tuist/tuist",
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "build",
          head_branch: "main",
          head_sha: "deadbee",
          status: "completed",
          conclusion: "success",
          enqueued_at: ~U[2026-06-01 10:00:00.000000Z],
          claimed_at: ~U[2026-06-01 10:00:00.000000Z],
          started_at: ~U[2026-06-01 10:00:00.000000Z],
          completed_at: ~U[2026-06-01 10:05:00.000000Z],
          pod_name: "",
          runner_name: "",
          requested_dispatch_label: "",
          updated_at: ~U[2026-06-01 10:05:00.000000Z]
        },
        attrs
      )

    {1, _} = IngestRepo.insert_all(Job, [row])
    :ok
  end

  test "renders the run's jobs, status, and links up to the workflow", %{conn: conn, account: account} do
    enqueue_job(account, %{workflow_job_id: 60_001, workflow_run_id: 600_010, job_name: "Build"})
    enqueue_job(account, %{workflow_job_id: 60_002, workflow_run_id: 600_010, job_name: "Test"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/600010")

    assert html =~ "Build"
    assert html =~ "Test"
    assert html =~ "runner-run-jobs-row-60001"
    # In progress (jobs are still queued).
    assert html =~ "Running"
    # Job rows link to the job detail; header links back to the workflow.
    assert html =~ "/runners/runs/600010/jobs/60001"
    assert html =~ "/runners/workflows/tuist/tuist/Server"
    # Redesigned layout: status header + Run Details metadata grid.
    assert html =~ ~s(id="runner-workflow-run")
    assert html =~ ~s(data-part="header")
    assert html =~ ~s(data-part="run-details-section")
    assert html =~ ~s(data-part="metadata-grid")
  end

  test "shows the Cancel button when in progress and the installation can cancel", %{conn: conn, account: account} do
    stub(Runners, :can_cancel_workflow_runs?, fn _ -> true end)
    enqueue_job(account, %{workflow_job_id: 61_001, workflow_run_id: 610_010, job_name: "Build"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/610010")

    assert html =~ "cancel_run"
    assert html =~ "Cancel"
  end

  test "hides the Cancel button when the installation cannot cancel", %{conn: conn, account: account} do
    stub(Runners, :can_cancel_workflow_runs?, fn _ -> false end)
    enqueue_job(account, %{workflow_job_id: 61_101, workflow_run_id: 611_010, job_name: "Build"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/611010")

    assert html =~ "runner-run-jobs-row-61101"
    refute html =~ "cancel_run"
  end

  test "the cancel_run event cancels the run", %{conn: conn, account: account} do
    stub(Runners, :can_cancel_workflow_runs?, fn _ -> true end)

    test_pid = self()

    stub(Runners, :cancel_workflow_run, fn acct, "tuist/tuist", 612_010 ->
      send(test_pid, {:cancelled, acct.id})
      :ok
    end)

    enqueue_job(account, %{workflow_job_id: 61_201, workflow_run_id: 612_010, job_name: "Build"})

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/runs/612010")

    render_click(lv, "cancel_run", %{})

    assert_received {:cancelled, account_id}
    assert account_id == account.id
  end

  test "renders a rolled-up stale conclusion without mislabelling it skipped", %{conn: conn, account: account} do
    insert_completed(account, %{workflow_job_id: 62_001, workflow_run_id: 620_010, job_name: "Reap", conclusion: "stale"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/620010")

    assert html =~ "Stale"
    refute html =~ "Skipped"
  end

  test "collapses a rerun to its latest attempt", %{conn: conn, account: account} do
    insert_completed(account, %{
      workflow_job_id: 63_101,
      workflow_run_id: 630_010,
      run_attempt: 1,
      job_name: "Attempt One",
      conclusion: "failure"
    })

    insert_completed(account, %{
      workflow_job_id: 63_201,
      workflow_run_id: 630_010,
      run_attempt: 2,
      job_name: "Attempt Two",
      conclusion: "success",
      started_at: ~U[2026-06-01 11:00:00.000000Z],
      completed_at: ~U[2026-06-01 11:03:00.000000Z],
      updated_at: ~U[2026-06-01 11:03:00.000000Z]
    })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/630010")

    # Only the latest attempt's job renders, and the failed first
    # attempt doesn't drag the header down.
    assert html =~ "Attempt Two"
    refute html =~ "Attempt One"
    assert html =~ "Success"
    assert html =~ "#2"
  end

  test "the GitHub link points at github.com by default", %{conn: conn, account: account} do
    enqueue_job(account, %{workflow_job_id: 63_001, workflow_run_id: 630_010, job_name: "Build"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/630010")

    assert html =~ "https://github.com/tuist/tuist/actions/runs/630010"
  end

  test "the GitHub link uses the installation's Enterprise host", %{conn: conn, account: account} do
    stub(Runners, :can_cancel_workflow_runs?, fn _ -> false end)

    {:ok, _installation} =
      VCS.create_github_app_installation(%{
        account_id: account.id,
        installation_id: "ghes-inst-1",
        client_url: "https://github.example.com"
      })

    enqueue_job(account, %{workflow_job_id: 63_101, workflow_run_id: 631_010, job_name: "Build"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/631010")

    assert html =~ "https://github.example.com/tuist/tuist/actions/runs/631010"
    refute html =~ "https://github.com/tuist/tuist/actions/runs/631010"
  end

  test "404s for a run with no jobs for the account", %{conn: conn, account: account} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/runs/999999")
    end
  end

  test "404s for an unauthorised account name", %{conn: conn} do
    %{account: other_account} =
      AccountsFixtures.organization_fixture(
        name: "other-run-org-#{System.unique_integer([:positive])}",
        preload: [:account]
      )

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{other_account.name}/runners/runs/600010")
    end
  end
end
