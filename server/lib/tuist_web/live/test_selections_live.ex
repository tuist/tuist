defmodule TuistWeb.TestSelectionsLive do
  @moduledoc """
  The project's Test Selection page. The period's figures
  (`Selections.analytics/2`): how many requested tests the selection runs
  selected and skipped, the skip rate, the dry-run misses (would-skip tests
  that failed, the number that decides when to enforce) and the runs. Then
  two tabs: the selection runs, one per invocation, newest first
  (`Selections.list_runs/2`), each opening its page
  (`TuistWeb.TestSelectionRunLive`) and linking to its commit's
  (`TuistWeb.TestSelectionCommitLive`); and the baselines, the
  default-branch commits that measured coverage and whether each can serve
  as one (`Selections.baselines/2`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests.Selections
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @widgets ~w(selected skipped skip_rate missed runs)
  @tabs ~w(runs baselines)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
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
    tab = if params["tab"] in @tabs, do: params["tab"], else: "runs"

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:tab, tab)
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign(:selected_widget, selected_widget(params["analytics-selected-widget"]))
     |> assign_tab(tab, params)
     |> assign_async(:analytics, fn -> {:ok, %{analytics: Selections.analytics(project.id, period)}} end)}
  end

  defp assign_tab(%{assigns: %{selected_project: project}} = socket, "runs", params) do
    search = params["search"] || ""
    mode = if params["mode"] in ["dry_run", "enabled"], do: params["mode"], else: "any"
    fallback? = params["fallback"] == "true"

    {rows, meta} =
      Selections.list_runs(project.id, search: search, mode: mode, fallback: fallback?, page: parse_page(params["page"]))

    socket
    |> assign(:search, search)
    |> assign(:mode, mode)
    |> assign(:fallback?, fallback?)
    |> assign(:runs, rows)
    |> assign(:runs_meta, meta)
  end

  defp assign_tab(%{assigns: %{selected_project: project}} = socket, "baselines", params) do
    {rows, meta} = Selections.baselines(project, page: parse_page(params["page"]))

    socket
    |> assign(:baselines, rows)
    |> assign(:baselines_meta, meta)
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

  def tabs, do: @tabs

  def tab_label("runs"), do: dgettext("dashboard_tests", "Selection runs")
  def tab_label("baselines"), do: dgettext("dashboard_tests", "Baselines")

  @doc false
  def run_href(%{selected_account: account, selected_project: project}, run),
    do: "/#{account.name}/#{project.name}/tests/test-selection/runs/#{run.id}"

  @doc false
  def commit_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/test-selection/commits/#{sha}"

  @doc false
  def coverage_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/coverage/commits/#{sha}"

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

  def chart_series("missed", analytics) do
    [
      line_series(
        dgettext("dashboard_tests", "Misses"),
        "var:noora-chart-destructive",
        analytics.dates,
        analytics.missed
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
  def format_duration(duration), do: Tuist.Utilities.DateFormatter.format_duration_from_milliseconds(duration)

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

  @doc false
  def mode_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  def mode_filter_label(mode), do: mode_label(mode)

  @doc false
  def baseline_status_label("baseline"), do: dgettext("dashboard_tests", "Baseline")
  def baseline_status_label("partial"), do: dgettext("dashboard_tests", "Baseline, some schemes partial")
  def baseline_status_label("no_test_evidence"), do: dgettext("dashboard_tests", "No per-test evidence")
  def baseline_status_label(_status), do: dgettext("dashboard_tests", "Coverage incomplete")

  @doc false
  def baseline_status("baseline"), do: "success"
  def baseline_status("partial"), do: "attention"
  def baseline_status(_status), do: "disabled"
end
