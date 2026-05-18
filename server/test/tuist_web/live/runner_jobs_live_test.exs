defmodule TuistWeb.RunnerJobsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-runners-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "sets the right title and shows the empty state when no jobs exist", %{
    conn: conn,
    account: account
  } do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs")

    assert html =~ "Jobs · #{account.name} · Tuist"
    assert html =~ "No jobs yet"
  end

  test "lists workflow_jobs for the selected account", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_001,
        account_id: account.id,
        fleet_name: "fleet-default",
        repo: "tuist/tuist",
        workflow_run_id: 990_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abc1234def"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs")

    assert html =~ "Server"
    assert html =~ "Docker build"
    assert html =~ "tuist/tuist"
    assert html =~ "fleet-default"
    assert html =~ "Queued"
  end

  test "filters jobs via the repository filter", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_301,
        account_id: account.id,
        fleet_name: "fleet-a",
        repo: "tuist/server",
        workflow_run_id: 993_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "server-job",
        head_branch: "main",
        head_sha: "5555555"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_302,
        account_id: account.id,
        fleet_name: "fleet-a",
        repo: "tuist/cli",
        workflow_run_id: 993_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "cli-job",
        head_branch: "main",
        head_sha: "6666666"
      })

    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{account.name}/runners/jobs?#{[{"filter_repository_op", "=~"}, {"filter_repository_val", "tuist/cli"}]}"
      )

    assert html =~ "cli-job"
    refute html =~ "server-job"
  end

  test "filters by status via the ?status= query param", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_101,
        account_id: account.id,
        fleet_name: "fleet-a",
        repo: "tuist/tuist",
        workflow_run_id: 991_010,
        run_attempt: 1,
        job_name: "queued-job",
        head_branch: "main",
        head_sha: "1111111"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_102,
        account_id: account.id,
        fleet_name: "fleet-a",
        repo: "tuist/tuist",
        workflow_run_id: 991_020,
        run_attempt: 1,
        job_name: "claimed-job",
        head_branch: "main",
        head_sha: "2222222"
      })

    {:ok, candidate} = Jobs.pick_queued("fleet-a", [])
    :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

    {:ok, _lv, html} =
      live(conn, ~p"/#{account.name}/runners/jobs?status=queued")

    assert html =~ "claimed-job"
    refute html =~ "queued-job"
  end

  test "does not show jobs from other accounts", %{conn: conn, account: account} do
    other = AccountsFixtures.user_fixture().account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_201,
        account_id: other.id,
        fleet_name: "fleet-x",
        repo: "evil/corp",
        workflow_run_id: 992_010,
        run_attempt: 1,
        job_name: "should-be-hidden",
        head_branch: "main",
        head_sha: "deadbef"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs")

    refute html =~ "should-be-hidden"
    refute html =~ "evil/corp"
  end
end
