defmodule TuistWeb.Components.AsyncCardTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.Components.AsyncCard
  alias TuistWeb.Components.ScatterChart

  test "initial and partially resolved results keep the original loading branch" do
    for results <- [
          [AsyncResult.loading(), AsyncResult.loading()],
          [AsyncResult.ok(10), AsyncResult.loading()],
          [AsyncResult.loading(), AsyncResult.ok(20)]
        ] do
      html = render_component(&card/1, results: results)
      assert html =~ ~s(data-state="loading")
      assert html =~ ~s(aria-busy="true")
      assert html =~ ~s(id="original-skeleton")
      assert html =~ ~s(id="card-action")
      refute html =~ ~s(id="stable-chart")
    end
  end

  test "ready and refreshing results use the same chart branch and retain values" do
    for results <- [
          [AsyncResult.ok(10), AsyncResult.ok(20)],
          [AsyncResult.loading(AsyncResult.ok(10)), AsyncResult.ok(20)]
        ] do
      html = render_component(&card/1, results: results)
      assert html =~ ~s(id="stable-chart")
      assert html =~ "10 / 20"
      refute html =~ ~s(id="original-skeleton")
    end

    html =
      render_component(&card/1,
        results: [AsyncResult.loading(AsyncResult.ok(10)), AsyncResult.ok(20)]
      )

    assert html =~ ~s(data-state="refreshing")
    assert html =~ ~s(aria-busy="true")
  end

  test "first-load and refresh failures render an error instead of empty or stale data" do
    for previous <- [AsyncResult.loading(), AsyncResult.ok(10)] do
      results = [AsyncResult.failed(previous, {:exit, :timeout}), AsyncResult.ok(20)]
      html = render_component(&card/1, results: results)
      assert html =~ ~s(data-state="failed")
      assert html =~ "We couldn&#39;t load the data"
      assert html =~ ~s(id="card-action")
      refute html =~ ~s(id="stable-chart")
      refute html =~ ~s(id="original-skeleton")
      refute html =~ "No data"
    end
  end

  test "optional metadata failure does not hide required data" do
    optional = AsyncResult.failed(AsyncResult.loading(), {:exit, :timeout})

    html =
      render_component(&card/1,
        results: [AsyncResult.ok(10), AsyncResult.ok(20)],
        optional: optional
      )

    assert html =~ ~s(data-state="ready")
    assert html =~ ~s(id="stable-chart")
    assert html =~ "Unavailable"
  end

  test "a section keeps synchronous table content visible in every phase" do
    for result <- [
          AsyncResult.loading(),
          AsyncResult.ok(10),
          AsyncResult.failed(AsyncResult.loading(), :timeout)
        ] do
      html = render_component(&mixed_card/1, result: result)
      assert html =~ ~s(id="loaded-table")
      assert html =~ "Existing row"
    end
  end

  test "scatter charts retain successful data on refresh and hide failed data" do
    result = AsyncResult.ok({:scatter, %{series: [], truncated: true, oldest_entry: nil}})

    for chart <- [result, AsyncResult.loading(result), AsyncResult.failed(result, :timeout)] do
      html =
        render_component(&ScatterChart.scatter_chart/1,
          id: "retained-scatter",
          chart: chart,
          period: {~U[2026-10-01 00:00:00Z], ~U[2026-10-03 00:00:00Z]},
          value_format: "{value}%",
          truncation_title: "Some points were omitted"
        )

      if chart.failed do
        refute html =~ ~s(id="retained-scatter")
        refute html =~ "Some points were omitted"
        assert html =~ "Something went wrong"
      else
        assert html =~ ~s(id="retained-scatter")
        assert html =~ "Some points were omitted"
      end
    end
  end

  defp card(assigns) do
    assigns = assign_new(assigns, :optional, fn -> AsyncResult.ok(1) end)

    ~H"""
    <AsyncCard.async_card :let={ready?} icon="chart_arcs" title="Analytics" results={@results}>
      <:actions><button id="card-action">Filter</button></:actions>
      <div :if={!ready?} id="original-skeleton">Loading</div>
      <div :if={ready?} id="stable-chart">
        {Enum.at(@results, 0).result} / {Enum.at(@results, 1).result}
      </div>
      <span :if={@optional.failed}>Unavailable</span>
    </AsyncCard.async_card>
    """
  end

  defp mixed_card(assigns) do
    ~H"""
    <Noora.Card.card icon="chart_arcs" title="Runs">
      <AsyncCard.async_section :let={ready?} results={[@result]}>
        <div :if={!ready?}>Loading</div>
        <div :if={ready?}>{@result.result}</div>
      </AsyncCard.async_section>
      <div id="loaded-table">Existing row</div>
    </Noora.Card.card>
    """
  end
end
