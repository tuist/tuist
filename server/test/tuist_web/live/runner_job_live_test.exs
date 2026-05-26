defmodule TuistWeb.RunnerJobLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-runner-job-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "renders metadata for a queued job", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_001,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repo: "tuist/tuist",
        workflow_run_id: 310_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef1234567890"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs/31001")

    assert html =~ "Server › Docker build"
    assert html =~ "tuist/tuist"
    assert html =~ "macos-xcode-26.4"
    assert html =~ "Queued"
    assert html =~ "abcdef123456"
  end

  test "renders timeline durations once a job has run", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_101,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repo: "tuist/cli",
        workflow_run_id: 311_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Unit Tests",
        head_branch: "main",
        head_sha: "1234567"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_101, "tuist-runner-x")
    {:ok, _completed} = Jobs.complete(31_101, "success")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs/31101")

    assert html =~ "CLI › Unit Tests"
    assert html =~ "tuist-runner-x"
    assert html =~ "Success"
  end

  test "raises 404 when the workflow_job_id belongs to another account", %{
    conn: conn,
    account: account
  } do
    other = AccountsFixtures.user_fixture().account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_201,
        account_id: other.id,
        fleet_name: "fleet-x",
        repo: "evil/corp",
        workflow_run_id: 312_010,
        workflow_name: "Evil",
        run_attempt: 1,
        job_name: "hidden",
        head_branch: "main",
        head_sha: "dead"
      })

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/jobs/31201")
    end
  end

  test "raises 404 for a non-integer workflow_job_id", %{conn: conn, account: account} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/jobs/notanumber")
    end
  end
end
