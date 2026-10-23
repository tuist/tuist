defmodule TuistWeb.RunnerJobRedirectControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "runner-redirect-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn = conn |> assign(:selected_account, account) |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  defp enqueue(account, workflow_job_id) do
    :ok =
      WorkflowJobs.upsert_queued(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: workflow_job_id * 10,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })
  end

  defp mint_runner(account, workflow_job_id, runner_name) do
    claimed_at = DateTime.utc_now()
    :ok = WorkflowJobs.transition_claimed(workflow_job_id, "pod-#{runner_name}", claimed_at)
    :ok = WorkflowJobs.transition_running(workflow_job_id, runner_name, claimed_at)

    {:ok, _} =
      RunnerSessions.open(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        pod_name: "pod-#{runner_name}",
        runner_name: runner_name,
        started_at: claimed_at
      })
  end

  test "redirects to the job that ran on the runner", %{conn: conn, account: account} do
    enqueue(account, 33_001)
    mint_runner(account, 33_001, "tuist-runner-pool-macos-abc123")

    conn = get(conn, ~p"/#{account.name}/runners/by-runner/tuist-runner-pool-macos-abc123")

    assert redirected_to(conn) == "/#{account.name}/runners/runs/330010/jobs/33001"
  end

  test "redirects to the job GitHub ran after a later mint overwrote the rows' runner names",
       %{conn: conn, account: account} do
    enqueue(account, 33_004)
    enqueue(account, 33_005)
    mint_runner(account, 33_004, "runner-ran-other")
    # GitHub ran 33_005 on the runner minted for 33_004.
    :mismatch = RunnerSessions.record_execution("runner-ran-other", 33_005, account.id)
    :ok = WorkflowJobs.record_execution("runner-ran-other", 33_005, account.id)
    # A later mint for either job overwrites the runner_name on its row.
    Repo.update_all(from(j in WorkflowJob, where: j.workflow_job_id in [33_004, 33_005]),
      set: [runner_name: "runner-later"]
    )

    conn = get(conn, ~p"/#{account.name}/runners/by-runner/runner-ran-other")

    assert redirected_to(conn) == "/#{account.name}/runners/runs/330050/jobs/33005"
  end

  test "404s for a runner that ran no job in the account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.account_fixture()
    enqueue(other_account, 33_002)
    mint_runner(other_account, 33_002, "other-account-runner")

    assert_raise NotFoundError, fn ->
      get(conn, ~p"/#{account.name}/runners/by-runner/other-account-runner")
    end
  end

  test "404s for a user who cannot read the account's runners", %{account: account} do
    enqueue(account, 33_003)
    mint_runner(account, 33_003, "private-runner")
    outsider = AccountsFixtures.user_fixture()

    assert_raise NotFoundError, fn ->
      build_conn()
      |> log_in_user(outsider)
      |> get(~p"/#{account.name}/runners/by-runner/private-runner")
    end
  end
end
