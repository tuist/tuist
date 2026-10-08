defmodule TuistWeb.RunnerJobRedirectControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

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

  defp run_on_runner(account, workflow_job_id, runner_name) do
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

    claimed_at = DateTime.utc_now()
    :ok = WorkflowJobs.transition_claimed(workflow_job_id, "pod-1", claimed_at)
    :ok = WorkflowJobs.transition_running(workflow_job_id, runner_name, claimed_at)
  end

  test "redirects to the job that ran on the runner", %{conn: conn, account: account} do
    run_on_runner(account, 33_001, "tuist-runner-pool-macos-abc123")

    conn = get(conn, ~p"/#{account.name}/runners/by-runner/tuist-runner-pool-macos-abc123")

    assert redirected_to(conn) == "/#{account.name}/runners/runs/330010/jobs/33001"
  end

  test "404s for a runner that ran no job in the account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.account_fixture()
    run_on_runner(other_account, 33_002, "other-account-runner")

    assert_raise NotFoundError, fn ->
      get(conn, ~p"/#{account.name}/runners/by-runner/other-account-runner")
    end
  end

  test "404s for a user who cannot read the account's runners", %{account: account} do
    run_on_runner(account, 33_003, "private-runner")
    outsider = AccountsFixtures.user_fixture()

    assert_raise NotFoundError, fn ->
      build_conn()
      |> log_in_user(outsider)
      |> get(~p"/#{account.name}/runners/by-runner/private-runner")
    end
  end
end
