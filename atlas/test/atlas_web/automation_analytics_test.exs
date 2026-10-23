defmodule AtlasWeb.AutomationAnalyticsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AtlasWeb.AutomationAnalytics
  alias Phoenix.LiveView.AsyncResult

  test "shows loading and retryable failure without fabricating numbers" do
    loading =
      render_component(&AutomationAnalytics.execution_overview/1,
        analytics: AsyncResult.loading(),
        metric: "executions",
        days: 30
      )

    assert loading =~ "data-loading"
    refute loading =~ ~s(id="automation-execution-chart")
    failed = AsyncResult.failed(AsyncResult.loading(), {:error, :unavailable})

    html =
      render_component(&AutomationAnalytics.execution_overview/1, analytics: failed, metric: "executions", days: 30)

    assert html =~ "Execution metrics could not be loaded"
    assert html =~ ~s(phx-click="retry_analytics")
  end

  test "preserves missing samples as gaps, measured zero and 0–100 percent bounds" do
    total = %{
      executions: 2,
      succeeded: 0,
      failed: 1,
      rejected: 0,
      cancelled: 0,
      active: 1,
      waiting_approval: 1,
      success_rate: 0.0,
      average_completion_seconds: 0.0
    }

    points = [Map.merge(total, %{date: "2026-01-01", success_rate: nil}), Map.put(total, :date, "2026-01-02")]
    result = %{total: total, previous: total, points: points, from: "2026-01-01", until: "2026-01-02"}

    html =
      render_component(&AutomationAnalytics.execution_overview/1,
        analytics: AsyncResult.ok(result),
        metric: "success_rate",
        days: 7
      )

    assert html =~ "0.0%"
    assert html =~ "0ms"

    data =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#automation-execution-chart > [data-part=data]")
      |> LazyHTML.text()
      |> JSON.decode!()

    assert [%{"data" => [gap, zero], "connectNulls" => false}] = data["series"]
    assert is_nil(gap)
    assert zero == 0.0
    assert data["legend"]["show"] == false
    assert data["xAxis"]["axisLabel"]["formatter"] == "fn:atlasUTCDate"
    assert data["xAxis"]["axisLabel"]["customValues"] == ["2026-01-01", "2026-01-02"]
    refute html =~ ~s(data-part="analytics-range")
    assert data["yAxis"]["max"] == 100
    assert data["yAxis"]["min"] == 0
  end
end
