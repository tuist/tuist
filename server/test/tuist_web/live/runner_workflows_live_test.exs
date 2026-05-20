defmodule TuistWeb.RunnerWorkflowsLiveTest do
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
        name: "workflows-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "lists per-workflow rollups for the selected account", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 80_001,
        account_id: account.id,
        fleet_name: "fleet-y",
        repo: "tuist/tuist",
        workflow_run_id: 800_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Format",
        head_branch: "main",
        head_sha: "1111111"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 80_002,
        account_id: account.id,
        fleet_name: "fleet-y",
        repo: "tuist/cli",
        workflow_run_id: 800_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Unit Tests",
        head_branch: "main",
        head_sha: "2222222"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows")

    assert html =~ "Server"
    assert html =~ "tuist/tuist"
    assert html =~ "CLI"
    assert html =~ "tuist/cli"
  end

  test "filters by repository via the repository filter", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 81_001,
        account_id: account.id,
        fleet_name: "fleet-y",
        repo: "tuist/server",
        workflow_run_id: 810_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "format",
        head_branch: "main",
        head_sha: "3333333"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 81_002,
        account_id: account.id,
        fleet_name: "fleet-y",
        repo: "tuist/cli",
        workflow_run_id: 810_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "test",
        head_branch: "main",
        head_sha: "4444444"
      })

    {:ok, _lv, html} =
      live(conn, ~p"/#{account.name}/runners/workflows?repository=tuist/cli")

    assert html =~ "CLI"
    refute html =~ ~r{>\s*Server\s*<}
  end

  test "shows empty state when no workflows match", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows")

    assert html =~ "No workflows yet"
  end
end
