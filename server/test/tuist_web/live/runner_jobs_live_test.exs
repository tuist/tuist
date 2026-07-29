defmodule TuistWeb.RunnerJobsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Catalog
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
        fleet_name: Catalog.pool_name(%{platform: :macos, xcode_version: "26.4"}),
        repository: "tuist/tuist",
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
    # Fleet column was replaced with a Platform badge derived from
    # the fleet_name prefix.
    assert html =~ "macOS"
    assert html =~ "Queued"
  end

  test "filters jobs via the repository filter", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_301,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "tuist/server",
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
        repository: "tuist/cli",
        workflow_run_id: 993_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "cli-job",
        head_branch: "main",
        head_sha: "6666666"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs?repository=tuist/cli")

    assert html =~ "cli-job"
    refute html =~ ~r{>\s*server-job\s*<}
  end

  test "filters by status via the status filter", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_101,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "tuist/tuist",
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
        repository: "tuist/tuist",
        workflow_run_id: 991_020,
        run_attempt: 1,
        job_name: "claimed-job",
        head_branch: "main",
        head_sha: "2222222"
      })

    {:ok, candidate} = Jobs.pick_queued("fleet-a", [])
    :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{account.name}/runners/jobs?#{[{"filter_status_op", "=="}, {"filter_status_val", "queued"}]}"
      )

    assert html =~ "claimed-job"
    refute html =~ "queued-job"
  end

  test "updates live status counts when a job is enqueued in the same account", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/jobs")

    # Initial state — no queued jobs visible.
    assert html =~ "Running"
    assert html =~ "Queued"

    # Subscribe in our test process so we can synchronise on the same
    # broadcast the LiveView is listening to. Once we see the message
    # we know `handle_info` has fired on the LV process too.
    Tuist.PubSub.subscribe(Jobs.topic(account.id))

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_301,
        account_id: account.id,
        fleet_name: "fleet-broadcast",
        repository: "tuist/tuist",
        workflow_run_id: 993_010,
        run_attempt: 1,
        job_name: "broadcast-job",
        head_branch: "main",
        head_sha: "aaaaaa1"
      })

    assert_receive {:runner_jobs_status_changed, %{status: "queued"}}, 1_000

    # The LV re-runs `assign_jobs` from the same broadcast, so the new
    # row appears in the table without any client-side reload.
    assert render(lv) =~ "broadcast-job"
  end

  test "search narrows the table by job name", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_401,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "tuist/tuist",
        workflow_run_id: 994_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_402,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "tuist/tuist",
        workflow_run_id: 994_020,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Format",
        head_branch: "main",
        head_sha: "def"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/jobs?search=Docker")

    assert html =~ "Docker build"
    refute html =~ ~r{>\s*Format\s*<}
  end

  test "?sort_by=job switches the table order", %{conn: conn, account: account} do
    # Insert three jobs in non-alphabetical order so the natural
    # enqueued-desc ordering and the job-asc ordering disagree.
    Enum.each(
      [{99_501, "Charlie"}, {99_502, "Alpha"}, {99_503, "Bravo"}],
      fn {id, name} ->
        :ok =
          Jobs.enqueue(%{
            workflow_job_id: id,
            account_id: account.id,
            fleet_name: "fleet-sort",
            repository: "tuist/tuist",
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
      live(conn, ~p"/#{account.name}/runners/jobs?sort_by=job&sort_order=asc")

    # Alpha must appear before Charlie in the rendered HTML when
    # sorting asc by job name.
    [alpha_idx, charlie_idx] =
      Enum.map(["Alpha", "Charlie"], fn name ->
        html |> :binary.match(name) |> elem(0)
      end)

    assert alpha_idx < charlie_idx
  end

  test "pagination Prev/Next appears once the result count exceeds @page_size", %{
    conn: conn,
    account: account
  } do
    # The Jobs page size is 20. Seed 21 jobs so the table spills onto
    # a second page and the pagination controls render.
    Enum.each(1..21, fn i ->
      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 99_600 + i,
          account_id: account.id,
          fleet_name: "fleet-page",
          repository: "tuist/tuist",
          workflow_run_id: (99_600 + i) * 10,
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "Job #{i}",
          head_branch: "main",
          head_sha: "sha#{i}"
        })
    end)

    {:ok, _lv, page_1_html} = live(conn, ~p"/#{account.name}/runners/jobs")
    {:ok, _lv, page_2_html} = live(conn, ~p"/#{account.name}/runners/jobs?page=2")

    assert page_1_html =~ "Next"
    assert page_1_html =~ "Prev"

    # The two pages render different rows — the second page must
    # contain the oldest job, which never fits on page one.
    refute page_1_html =~ ~r{>\s*Job 1\s*<}
    assert page_2_html =~ ~r{>\s*Job 1\s*<}
  end

  test "does not show jobs from other accounts", %{conn: conn, account: account} do
    other = AccountsFixtures.user_fixture().account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 99_201,
        account_id: other.id,
        fleet_name: "fleet-x",
        repository: "evil/corp",
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
