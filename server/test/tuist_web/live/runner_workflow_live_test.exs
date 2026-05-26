defmodule TuistWeb.RunnerWorkflowLiveTest do
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

  test "renders the workflow header and analytics widgets", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 90_001,
        account_id: account.id,
        fleet_name: "fleet-w",
        repo: "tuist/tuist",
        workflow_run_id: 900_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "deadbee"
      })

    # Walk the job to completed so the success-rate widget renders a
    # real value (otherwise the success_rate query returns nil and the
    # widget would just say '–').
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
    assert html =~ "Failed jobs"
    assert html =~ "job duration"
    assert html =~ "Docker build"
  end

  test "scopes the Jobs table to the requested workflow", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 91_001,
        account_id: account.id,
        fleet_name: "fleet-w",
        repo: "tuist/tuist",
        workflow_run_id: 910_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Format",
        head_branch: "main",
        head_sha: "abc1234"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 91_002,
        account_id: account.id,
        fleet_name: "fleet-w",
        repo: "tuist/tuist",
        workflow_run_id: 910_020,
        workflow_name: "Release",
        run_attempt: 1,
        job_name: "Bump version",
        head_branch: "main",
        head_sha: "def4567"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")

    assert html =~ "Format"
    refute html =~ "Bump version"
  end

  test "Jobs table search narrows by job_name within the workflow", %{
    conn: conn,
    account: account
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 91_101,
        account_id: account.id,
        fleet_name: "fleet-search",
        repo: "tuist/tuist",
        workflow_run_id: 911_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "aaa"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 91_102,
        account_id: account.id,
        fleet_name: "fleet-search",
        repo: "tuist/tuist",
        workflow_run_id: 911_020,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Format",
        head_branch: "main",
        head_sha: "bbb"
      })

    {:ok, _lv, html} =
      live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server?search=Docker")

    assert html =~ "Docker build"
    refute html =~ ~r{>\s*Format\s*<}
  end

  test "Jobs table paginates when the workflow has more than one page of jobs", %{
    conn: conn,
    account: account
  } do
    # @page_size on the workflow detail is 20. Seed 21 jobs so we
    # get a Prev/Next strip and a real second page.
    Enum.each(1..21, fn i ->
      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 92_000 + i,
          account_id: account.id,
          fleet_name: "fleet-pg",
          repo: "tuist/tuist",
          workflow_run_id: (92_000 + i) * 10,
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "Job #{i}",
          head_branch: "main",
          head_sha: "sha#{i}"
        })
    end)

    {:ok, _lv, page_1} = live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server")

    {:ok, _lv, page_2} =
      live(conn, ~p"/#{account.name}/runners/workflows/tuist/tuist/Server?page=2")

    assert page_1 =~ "Next"
    assert page_1 =~ "Prev"
    refute page_1 =~ ~r{>\s*Job 1\s*<}
    assert page_2 =~ ~r{>\s*Job 1\s*<}
  end

  test "Jobs table sort_by job re-orders the rendered rows", %{conn: conn, account: account} do
    Enum.each(
      [{93_001, "Charlie"}, {93_002, "Alpha"}, {93_003, "Bravo"}],
      fn {id, name} ->
        :ok =
          Jobs.enqueue(%{
            workflow_job_id: id,
            account_id: account.id,
            fleet_name: "fleet-sort-wf",
            repo: "tuist/tuist",
            workflow_run_id: id * 10,
            workflow_name: "Server",
            run_attempt: 1,
            job_name: name,
            head_branch: "main",
            head_sha: "sha-#{id}"
          })
      end
    )

    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{account.name}/runners/workflows/tuist/tuist/Server?sort_by=job&sort_order=asc"
      )

    [alpha_idx, charlie_idx] =
      Enum.map(["Alpha", "Charlie"], fn name ->
        html |> :binary.match(name) |> elem(0)
      end)

    assert alpha_idx < charlie_idx
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
end
