defmodule TuistWeb.TestSelectionsLive do
  @moduledoc """
  The project's Test Selection page. The period's figures
  (`Selections.analytics/2`): how many requested tests the impact runs
  selected and skipped, the skip rate and the runs. Then the impact runs,
  one per invocation in the period, newest first (`Selections.list_runs/3`), each opening
  the Selective Testing tab of the test run that reported it
  (`TuistWeb.TestSelection.RunTab`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Selections
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @widgets ~w(selected skipped skip_rate runs)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.test_impact_analysis_enabled?(account, project) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist")
     |> assign(OpenGraph.og_image_assigns("tests"))}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign(:selected_widget, selected_widget(params["analytics-selected-widget"]))
     |> assign_runs(period, params)
     |> assign_async(:analytics, fn -> {:ok, %{analytics: Selections.analytics(project.id, period)}} end)}
  end

  defp assign_runs(%{assigns: %{selected_project: project}} = socket, period, params) do
    search = params["search"] || ""
    fallback? = params["fallback"] == "true"

    {rows, meta} =
      Selections.list_runs(project.id, period, search: search, fallback: fallback?, page: parse_page(params["page"]))

    socket
    |> assign(:search, search)
    |> assign(:fallback?, fallback?)
    |> assign(:runs, rows)
    |> assign(:runs_meta, meta)
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: path(socket) <> "?" <> query)}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    widget = selected_widget(widget)
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:selected_widget, widget)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("search-runs", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: path(socket) <> "?" <> query, replace: true)}
  end

  defp path(%{assigns: %{selected_account: account, selected_project: project}}),
    do: "/#{account.name}/#{project.name}/tests/test-selection"

  @doc """
  An impact run opens the tab that shows it on the test run that reported
  it; one no test run reported has nowhere to go and stays on this page.
  """
  def run_href(%{selected_account: account, selected_project: project}, %{test_run_id: test_run_id})
      when not is_nil(test_run_id),
      do: "/#{account.name}/#{project.name}/tests/test-runs/#{test_run_id}?tab=test-optimizations"

  def run_href(%{uri: uri} = assigns, _run), do: "#{path_from_assigns(assigns)}?#{uri.query}"

  defp path_from_assigns(%{selected_account: account, selected_project: project}),
    do: "/#{account.name}/#{project.name}/tests/test-selection"

  @doc "What an impact run ran: its test plan, or else its scheme."
  def run_scope(%{build_context: context}) do
    case Map.get(context, "test_plan", "") do
      "" -> Map.get(context, "scheme", "")
      test_plan -> test_plan
    end
  end

  @doc false
  def chart_series("runs", analytics) do
    [line_series(dgettext("dashboard_tests", "Selection runs"), "var:noora-chart-p90", analytics.dates, analytics.runs)]
  end

  def chart_series("skip_rate", analytics) do
    [
      line_series(
        dgettext("dashboard_tests", "Skip rate"),
        "var:noora-chart-tertiary",
        analytics.dates,
        analytics.skip_rates
      )
    ]
  end

  # Selected and skipped side by side, stacked per period, whichever of the
  # two widgets is picked.
  def chart_series(_widget, analytics) do
    [
      bar_series(dgettext("dashboard_tests", "Selected"), "var:noora-chart-primary", analytics.dates, analytics.selected),
      bar_series(dgettext("dashboard_tests", "Skipped"), "var:noora-chart-secondary", analytics.dates, analytics.skipped)
    ]
  end

  defp line_series(name, color, dates, values) do
    %{
      name: name,
      color: color,
      type: "line",
      smooth: 0.1,
      symbol: "none",
      data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1)
    }
  end

  defp bar_series(name, color, dates, values) do
    %{
      name: name,
      color: color,
      type: "bar",
      stack: "decisions",
      barMaxWidth: 12,
      data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1)
    }
  end

  @doc false
  def empty_chart?(analytics), do: analytics.totals.runs == 0

  @doc false
  def format_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "selected"

  defp trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp trend_label(_preset), do: dgettext("dashboard_tests", "since last month")
end
