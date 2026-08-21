defmodule TuistWeb.RunnersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.FlushJobTransitionEventsWorker
  alias Tuist.Runners.WorkflowJobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  # render_async/2 is LiveViewTest's first-party hook for waiting on async assigns.
  # The runners widgets cross analytics-backed async work that can be slower on CI,
  # so keep an explicit timeout until we have a deterministic non-time-based drain.
  @render_async_timeout 1_000

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
        repository: "tuist/tuist",
        workflow_run_id: 700_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef0"
      })

    # Recent jobs card only surfaces completed work, so walk the job
    # through the full state machine before asserting it shows up.
    {:ok, candidate} = Jobs.pick_queued("fleet-x", [])
    claimed_at = DateTime.utc_now()
    :ok = WorkflowJobs.transition_claimed(candidate.workflow_job_id, "pod-1", claimed_at)
    :ok = WorkflowJobs.transition_running(70_001, "runner-x", claimed_at)
    {:ok, _} = Jobs.complete(70_001, "success")

    flush_outbox!()

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)

    assert html =~ "Total jobs"
    assert html =~ "Avg. job duration"
    assert html =~ "Avg. workflow duration"
    assert html =~ "Concurrency"
    assert html =~ "12 vCPU limit"
    assert html =~ "28 GB limit"
    assert html =~ "runners-concurrency-platform-dropdown"
    assert html =~ "runners-concurrency-macos-vcpus-chart"
    assert html =~ "runners-concurrency-macos-memory-chart"
    assert html =~ ~s(class="noora-card__section " data-part="concurrency-chart")
    refute html =~ "runners-concurrency-linux-vcpus-chart"
    refute html =~ "No limit hits"
    refute html =~ "Limit reached in"
    assert concurrency_after_analytics?(html)
    assert html =~ "Recent jobs"
    assert html =~ "Server"
    assert html =~ "Docker build"
  end

  test "charts only succeeded and failed runs", %{conn: conn, account: account} do
    complete_run(account, 70_002, 700_020, "success")
    complete_run(account, 70_003, 700_021, "cancelled")

    flush_outbox!()

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)

    # The cancelled run carries no real duration, so it must not draw a
    # bar. Only the succeeded run remains on each chart.
    for chart_id <- ["runners-recent-workflows-chart", "runners-recent-jobs-chart"] do
      data = chart_series_data(html, chart_id)
      assert length(data) == 1
      assert Enum.all?(data, &(&1["value"] != nil))
    end
  end

  test "lists only succeeded and failed jobs in the recent jobs card", %{conn: conn, account: account} do
    complete_run(account, 70_004, 700_022, "success")
    complete_run(account, 70_006, 700_024, "cancelled")
    skip_run(account, 70_005, 700_023)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)
    table = recent_jobs_table(html)

    assert table =~ "Docker build"
    refute table =~ "Gated job"
    refute table =~ "Skipped"
    refute table =~ "Cancelled"
  end

  test "lists only succeeded and failed runs in the recent workflows card", %{conn: conn, account: account} do
    complete_run(account, 70_007, 700_025, "success")
    complete_run(account, 70_008, 700_026, "cancelled")
    skip_run(account, 70_009, 700_027)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)
    table = recent_workflows_table(html)

    assert table =~ "Success"
    refute table =~ "Skipped"
    refute table =~ "Cancelled"
  end

  test "shows empty state when the account has no jobs", %{conn: conn, account: account} do
    flush_outbox!()

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)

    assert html =~ "Workflows"
    assert html =~ "Concurrency"
    assert html =~ "Recent jobs"
    assert html =~ "No jobs yet"
    assert html =~ "Get started"
    assert Enum.all?(view_more_buttons(html), &disabled?/1)
  end

  test "tells an account whose recent work was all filtered out from one with no jobs", %{
    conn: conn,
    account: account
  } do
    skip_run(account, 70_010, 700_028)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv, @render_async_timeout)

    assert html =~ "Every recent job was skipped or cancelled"
    assert html =~ "Every recent workflow run was skipped or cancelled"
    refute html =~ "No jobs yet"
    # The rows exist behind the Jobs and Workflows pages' own filters,
    # so the way there must stay open and the onboarding link away.
    refute html =~ "Get started"
    assert Enum.all?(view_more_buttons(html), &(not disabled?(&1)))
  end

  test "shows only the selected concurrency platform", %{conn: conn, account: account} do
    flush_outbox!()

    {:ok, lv, _html} =
      live(conn, ~p"/#{account.name}/runners?concurrency-platform=linux")

    html = render_async(lv, @render_async_timeout)

    assert html =~ "32 vCPU limit"
    assert html =~ "64 GB limit"
    assert html =~ "runners-concurrency-linux-vcpus-chart"
    assert html =~ "runners-concurrency-linux-memory-chart"
    refute html =~ "runners-concurrency-macos-vcpus-chart"
  end

  test "marks limit buckets and renders the configured threshold" do
    [usage, limit] = TuistWeb.RunnersLive.concurrency_chart_series([6, 12, 18], 12, "Peak CPU")

    assert usage.name == "Peak CPU"
    assert usage.itemStyle.color == "var:noora-chart-primary"

    assert usage.data == [
             6,
             %{value: 12, itemStyle: %{color: "var:noora-chart-destructive"}},
             %{value: 18, itemStyle: %{color: "var:noora-chart-destructive"}}
           ]

    assert limit.data == [12, 12, 12]
    assert limit.itemStyle.color == "var:noora-chart-destructive"
    assert limit.lineStyle.type == "dashed"

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-7-days").legend.left == "left"

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-24-hours").xAxis.axisLabel.formatter ==
             "fn:toLocaleDateHour"

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-7-days").xAxis.axisLabel.formatter ==
             "fn:toLocaleDate"

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-7-days").xAxis.axisLabel.interval == 23

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-30-days").xAxis.axisLabel.formatter ==
             "fn:toLocaleDate"

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-30-days").xAxis.axisLabel.interval == 47

    assert TuistWeb.RunnersLive.concurrency_chart_options("last-7-days").tooltip.dateFormat == "hour"
  end

  defp complete_run(account, workflow_job_id, workflow_run_id, conclusion) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "fleet-x",
        repository: "tuist/tuist",
        workflow_run_id: workflow_run_id,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef#{workflow_job_id}"
      })

    {:ok, candidate} = Jobs.pick_queued("fleet-x", [])
    claimed_at = DateTime.utc_now()
    :ok = WorkflowJobs.transition_claimed(candidate.workflow_job_id, "pod-#{workflow_job_id}", claimed_at)
    :ok = WorkflowJobs.transition_running(workflow_job_id, "runner-#{workflow_job_id}", claimed_at)
    {:ok, _} = Jobs.complete(workflow_job_id, conclusion)
    flush_outbox!()
  end

  # A job gated out by an `if:` condition never reaches a runner, so
  # GitHub delivers `completed`/`skipped` with no preceding `queued`.
  defp skip_run(account, workflow_job_id, workflow_run_id) do
    :ok =
      Jobs.record_completed(
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          fleet_name: "fleet-x",
          repository: "tuist/tuist",
          workflow_run_id: workflow_run_id,
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "Gated job",
          head_branch: "main",
          head_sha: "abcdef#{workflow_job_id}"
        },
        "skipped"
      )

    flush_outbox!()
  end

  # Noora renders an enabled button with a `navigate` as a link, and a
  # disabled one as a plain `<button disabled>`. Both cards carry one,
  # so anything other than two means the lookup, not the page, changed.
  defp view_more_buttons(html) do
    buttons =
      html
      |> Floki.parse_document!()
      |> Floki.find("a, button")
      |> Enum.filter(&(&1 |> Floki.text() |> String.contains?("View more")))

    assert length(buttons) == 2
    buttons
  end

  defp disabled?({"button", attrs, _}), do: Enum.any?(attrs, fn {name, _} -> name == "disabled" end)
  defp disabled?({"a", _attrs, _}), do: false

  defp recent_jobs_table(html), do: table_text(html, "recent-jobs-table")

  defp recent_workflows_table(html), do: table_text(html, "recent-workflows-table")

  defp table_text(html, part) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-part='#{part}']")
    |> Floki.text()
  end

  defp chart_series_data(html, chart_id) do
    json =
      html
      |> Floki.parse_document!()
      |> Floki.find("##{chart_id} [data-part='data']")
      |> Floki.text()

    json
    |> JSON.decode!()
    |> Map.fetch!("series")
    |> List.first()
    |> Map.fetch!("data")
  end

  defp concurrency_after_analytics?(html) do
    {analytics_position, _} = :binary.match(html, "data-part=\"analytics\"")
    {concurrency_position, _} = :binary.match(html, "data-part=\"concurrency-card\"")
    concurrency_position > analytics_position
  end

  defp flush_outbox! do
    :ok = FlushJobTransitionEventsWorker.perform(%Oban.Job{})
  end
end
