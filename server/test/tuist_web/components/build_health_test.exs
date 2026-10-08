defmodule TuistWeb.Components.BuildHealthTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.Components.BuildHealth

  test "failure category filter uses the same values and labels as the column" do
    filter = BuildHealth.category_filter()
    assert filter.field == :failure_category
    assert filter.options == ["verification", "infrastructure_tooling", "unknown"]
    assert BuildHealth.category_label("verification") == "Verification"
    assert BuildHealth.category_label("infrastructure_tooling") == "Infrastructure / tooling"
    assert BuildHealth.category_label("unknown") == "Unclassified"
    assert BuildHealth.category_label("") == "—"
  end

  test "missing and zero task time estimates remain distinct" do
    missing =
      render_component(&BuildHealth.cache_widget/1,
        health:
          AsyncResult.ok(%{totals: %{"cache_work_avoided" => nil, "cache_work_avoided_samples" => 0, "builds" => 4}})
      )

    assert missing =~ "Not reported"
    refute missing =~ "Reporting coverage"

    zero =
      render_component(&BuildHealth.cache_widget/1,
        health: AsyncResult.ok(%{totals: %{"cache_work_avoided" => 0, "cache_work_avoided_samples" => 1, "builds" => 4}})
      )

    refute zero =~ "Not reported"
    assert zero =~ "Cumulative task time saved"
    refute zero =~ "value-caption"
    assert zero =~ "0ms"
    assert zero =~ "not elapsed build time saved"
  end

  test "task time chart preserves gaps and recorded zero estimates" do
    health =
      AsyncResult.ok(%{
        totals: %{"cache_work_avoided" => 0},
        dates: [1_700_000_000, 1_700_086_400],
        series: %{"cache_work_avoided" => [nil, 0]}
      })

    html = render_component(&BuildHealth.cache_chart/1, health: health)
    assert html =~ "gradle-task-time-saved-chart"
    options = html |> Floki.parse_fragment!() |> Floki.find("[data-part=data]") |> Floki.text() |> JSON.decode!()
    assert Enum.map(hd(options["series"])["data"], &List.last/1) == [nil, 0]
    assert html =~ "Cumulative task time saved"
    refute html =~ "No task time estimates reported"

    missing =
      render_component(&BuildHealth.cache_chart/1, health: AsyncResult.ok(%{totals: %{"cache_work_avoided" => nil}}))

    assert missing =~ "No task time estimates reported"
    refute missing =~ "gradle-task-time-saved-chart"
  end

  test "failure details show classification and explanation without a hover interaction" do
    for category <- ["verification", "infrastructure_tooling", "unknown"] do
      html = render_component(&BuildHealth.category_detail/1, category: category)
      assert html =~ "tuist-failure-classification"
      assert html =~ "recorded build data"
      assert html =~ BuildHealth.category_label(category)
      refute html =~ "noora-tooltip"
    end

    for category <- [nil, ""] do
      refute render_component(&BuildHealth.category_detail/1, category: category) =~ "Failure category"
    end
  end

  test "loading and failure states never masquerade as no failures or zero cache savings" do
    for health <- [AsyncResult.loading(), AsyncResult.failed(AsyncResult.loading(), {:exit, :timeout})] do
      cache = render_component(&BuildHealth.cache_widget/1, health: health)
      refute cache =~ "0 of"
      refute cache =~ "Not reported"
      chart = render_component(&BuildHealth.cache_chart/1, health: health)
      refute chart =~ "No task time estimates reported"
      refute chart =~ "gradle-task-time-saved-chart"
    end
  end
end
