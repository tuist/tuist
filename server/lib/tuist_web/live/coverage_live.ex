defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page: a glance at the default branch over the
  chosen period — its coverage now and over time — and the branches and pull
  requests that gathered coverage in it. Every figure is a commit's, pooled
  over the schemes that measured it; the default branch, each branch and each
  pull request open on their own page (`TuistWeb.CoverageDetailLive`).

  Its settings live under the project's settings
  (`TuistWeb.ProjectCoverageSettingsLive`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @branches_page_size 10

  @widgets ~w(coverage covered_lines executable_lines)

  # A run's coverage joins its commit's figure a few seconds after the run
  # lands (`Tuist.Tests.Coverage.Workers.CommitWorker`), so the page reloads
  # once after a burst of runs rather than once per run, before the fold.
  @reload_delay to_timeout(second: 15)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Code Coverage")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("tests"))
      |> assign(:reload_scheduled, false)

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    query = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(query))
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign(:branch, project.default_branch)
      |> assign(:selected_widget, selected_widget(query["analytics-selected-widget"]))

    # The page is read once, when the socket connects; the disconnected
    # render shows its skeleton.
    {:noreply,
     if(connected?(socket),
       do: socket |> assign(:loading, false) |> assign_page(query),
       else: assign(socket, :loading, true)
     )}
  end

  def handle_event(
        "coverage_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("coverage-date-range", "custom")
        |> Query.put("coverage-start-date", start_date)
        |> Query.put("coverage-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "coverage-date-range", preset)
      end

    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> drop_branches_cursor(query))}
  end

  def handle_event("search-branches", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("branches-search", search) |> drop_branches_cursor()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
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

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply, schedule_reload(socket)}
  end

  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(:reload_scheduled, false) |> assign_page(socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_page(socket, query) do
    socket
    |> assign_analytics()
    |> assign_branches(query)
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    points = History.branch_points(project, branch, period_opts(socket))
    latest = List.last(points)

    socket
    |> assign(:points, chart_points(points, socket.assigns.coverage_period))
    |> assign(:latest, latest)
    |> assign(:trends, %{
      "coverage" => period_trend(points),
      "covered_lines" => count_trend(points, :covered_lines),
      "executable_lines" => count_trend(points, :executable_lines)
    })
  end

  # The branches and pull requests measured in the period, newest first, a
  # page at a time from a cursor.
  defp assign_branches(%{assigns: %{selected_project: project}} = socket, query) do
    search = query["branches-search"] || ""

    page =
      History.refs(
        project,
        Keyword.merge(period_opts(socket),
          search: search,
          after: query["after"],
          before: query["before"],
          page_size: @branches_page_size
        )
      )

    socket
    |> assign(:branches_search, search)
    |> assign(:branch_rows, Enum.map(page.refs, &Map.put(&1, :id, "ref-" <> &1.name)))
    |> assign(:branches_meta, Map.take(page, [:has_next_page?, :has_previous_page?, :start_cursor, :end_cursor]))
  end

  # A cursor names a row of one listing; another period or search starts over.
  defp drop_branches_cursor(query), do: query |> Query.drop("after") |> Query.drop("before")

  # The period's parameters, so the default branch's page opens on the period
  # shown here.
  @doc false
  def period_query(params), do: Map.filter(params, fn {key, _value} -> String.starts_with?(key, "coverage-") end)

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)

  defp schedule_reload(%{assigns: %{reload_scheduled: true}} = socket), do: socket

  defp schedule_reload(socket) do
    Process.send_after(self(), :reload, @reload_delay)
    assign(socket, :reload_scheduled, true)
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"
end
