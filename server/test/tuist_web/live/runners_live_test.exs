defmodule TuistWeb.RunnersLiveTest do
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
        name: "runners-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "renders summary cards + both widgets with seeded jobs", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 70_001,
        account_id: account.id,
        fleet_name: "fleet-x",
        repo: "tuist/tuist",
        workflow_run_id: 700_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef0"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners")

    assert html =~ "Total jobs"
    assert html =~ "Avg. job duration"
    assert html =~ "Avg. workflow duration"
    assert html =~ "Recent jobs"
    assert html =~ "Server"
    assert html =~ "Docker build"
  end

  test "shows empty state when the account has no jobs", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners")

    assert html =~ "Workflows"
    assert html =~ "Recent jobs"
    assert html =~ "No jobs yet"
  end
end
