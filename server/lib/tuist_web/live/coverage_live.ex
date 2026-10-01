defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page: a glance at a branch over the chosen
  period, its latest complete commit and its trend over complete commits
  (`History.trend_points/3`). The branch is picked among those whose runs
  never named a pull request (`History.branches/2`), the default branch
  unless `analytics-branch` names another. Every figure is a commit's,
  pooled over the schemes that measured it; the branch opens on its own page
  (`TuistWeb.CoverageDetailLive`).

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
      |> assign(:branches, [])

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
      |> assign(:branch, branch(query["analytics-branch"], project))
      |> assign(:selected_widget, selected_widget(query["analytics-selected-widget"]))

    # The page is read once, when the socket connects; the disconnected
    # render shows its skeleton.
    {:noreply,
     if(connected?(socket),
       do: socket |> assign(:loading, false) |> assign_page(),
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

    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query)}
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
    {:noreply, socket |> assign(:reload_scheduled, false) |> assign_page()}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_page(%{assigns: %{selected_project: project}} = socket) do
    socket
    |> assign(:branches, History.branches(project))
    |> assign_analytics()
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    points = History.trend_points(project, branch, period_opts(socket))
    latest = List.last(points)

    socket
    |> assign(:points, points)
    |> assign(:latest, latest)
    |> assign(:trends, %{
      "coverage" => period_trend(points),
      "covered_lines" => count_trend(points, :covered_lines),
      "executable_lines" => count_trend(points, :executable_lines)
    })
  end

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

  defp branch(branch, _project) when is_binary(branch) and branch != "", do: branch
  defp branch(_branch, project), do: project.default_branch

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"
end
