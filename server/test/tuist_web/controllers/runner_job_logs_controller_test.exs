defmodule TuistWeb.RunnerJobLogsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.FlushJobTransitionEventsWorker
  alias Tuist.Storage
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

    # ClickHouse learns about the job through the transition outbox, and
    # this controller reads the archive marker from there.
    :ok = FlushJobTransitionEventsWorker.perform(%Oban.Job{})
  end

  test "404s when the job's log archive has not been built yet", %{conn: conn, account: account} do
    enqueue(account, 32_001, 320_010)

    assert_raise NotFoundError, fn ->
      get(conn, ~p"/#{account.name}/runners/runs/320010/jobs/32001/logs/download")
    end
  end

  test "redirects to a presigned S3 URL once the log archive has been built", %{conn: conn, account: account} do
    enqueue(account, 32_201, 322_010)
    :ok = Jobs.set_log_archived_at(32_201, DateTime.utc_now())

    expect(Storage, :generate_download_url, fn key, actor, opts ->
      assert key == "runners/#{account.id}/32201/runner.log.gz"
      assert actor.id == account.id
      assert opts[:query_params] == [{"response-content-disposition", ~s(attachment; filename="runner-job-32201.log.gz")}]
      "https://s3.example.com/signed-archive-url"
    end)

    conn = get(conn, ~p"/#{account.name}/runners/runs/322010/jobs/32201/logs/download")

    assert redirected_to(conn) == "https://s3.example.com/signed-archive-url"
  end

  test "serves the archive to signed-out visitors when the account is public", %{account: account} do
    {:ok, account} = Accounts.update_account_visibility(account, :public)
    enqueue(account, 32_301, 323_010)
    :ok = Jobs.set_log_archived_at(32_301, DateTime.utc_now())

    stub(Storage, :generate_download_url, fn _key, _actor, _opts -> "https://s3.example.com/public-archive-url" end)

    conn = get(build_conn(), ~p"/#{account.name}/runners/runs/323010/jobs/32301/logs/download")

    assert redirected_to(conn) == "https://s3.example.com/public-archive-url"
  end

  test "redirects signed-out visitors to log in when the account is private", %{account: account} do
    enqueue(account, 32_401, 324_010)
    :ok = Jobs.set_log_archived_at(32_401, DateTime.utc_now())

    conn = get(build_conn(), ~p"/#{account.name}/runners/runs/324010/jobs/32401/logs/download")

    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "404s when the job belongs to another account", %{conn: conn, account: account} do
    other = AccountsFixtures.user_fixture().account
    enqueue(other, 32_101, 321_010)

    assert_raise NotFoundError, fn ->
      get(conn, ~p"/#{account.name}/runners/runs/321010/jobs/32101/logs/download")
    end
  end
end
