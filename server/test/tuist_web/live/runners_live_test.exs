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
    :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
    :ok = Jobs.record_running(70_001, "runner-x")
    {:ok, _} = Jobs.complete(70_001, "success")

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv)

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

  test "shows empty state when the account has no jobs", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners")
    html = render_async(lv)

    assert html =~ "Workflows"
    assert html =~ "Concurrency"
    assert html =~ "Recent jobs"
    assert html =~ "No jobs yet"
  end

  test "shows only the selected concurrency platform", %{conn: conn, account: account} do
    {:ok, lv, _html} =
      live(conn, ~p"/#{account.name}/runners?concurrency-platform=linux")

    html = render_async(lv)

    assert html =~ "32 vCPU limit"
    assert html =~ "64 GB limit"
    assert html =~ "runners-concurrency-linux-vcpus-chart"
    assert html =~ "runners-concurrency-linux-memory-chart"
    refute html =~ "runners-concurrency-macos-vcpus-chart"
  end

  test "marks limit buckets and renders the configured threshold" do
    [admitted_usage, at_limit, limit] =
      TuistWeb.RunnersLive.concurrency_chart_series([6, 12, 18], 12, "Peak CPU")

    assert admitted_usage.data == [6, nil, nil]
    assert admitted_usage.name == "Peak CPU"
    assert admitted_usage.itemStyle.color == "var:noora-chart-primary"

    assert at_limit.data == [nil, 12, 18]
    assert at_limit.name == "Limit reached"
    assert at_limit.itemStyle.color == "var:noora-chart-destructive"
    assert at_limit.stack == admitted_usage.stack

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

  defp concurrency_after_analytics?(html) do
    {analytics_position, _} = :binary.match(html, "data-part=\"analytics\"")
    {concurrency_position, _} = :binary.match(html, "data-part=\"concurrency-card\"")
    concurrency_position > analytics_position
  end
end
