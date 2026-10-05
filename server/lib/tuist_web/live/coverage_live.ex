defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page: a glance at a branch over the chosen
  period, its latest complete commit and its trend over complete commits
  (`History.trend_points/3`), the files and targets whose coverage moved
  most over the period (`Commits.changed_files/5`,
  `Commits.changed_targets/5`), its five most recent complete commits in the
  period (`History.commit_cursor_page/3`) and its five newest test runs
  there (`Commits.run_cursor_page/3`), each card's View more opening the
  branch's page (`TuistWeb.CoverageDetailLive`) on the matching tab. The
  branch is picked among those whose runs never named a pull request
  (`History.branches/2`), the default branch unless `branch` names another.
  Every figure is a commit's, pooled over the schemes that measured it.
  Coverage has no project settings: the excluded paths and tracked files are
  the same defaults for every project (`Tuist.Tests.Coverage.ExcludedPaths`,
  `Tuist.GitHistory.settings/1`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @widgets ~w(coverage covered_lines executable_lines)

  @recent_commits 5

  @recent_runs 5

  @listed 4

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
      |> assign(:branch, selected_branch(query["branch"], project))
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
    |> assign_recent_commits()
    |> assign_recent_runs()
    |> assign_changes()
  end

  # The files and targets whose coverage moved most over the period: from the
  # oldest complete commit the chart draws to the latest. One more of each
  # than the card shows, so it knows when there are more.
  defp assign_changes(%{assigns: %{selected_project: project, latest: %{git_commit_sha: sha}, points: points}} = socket) do
    case List.first(points) do
      %{git_commit_sha: ^sha} ->
        socket |> assign(:changed_files, []) |> assign(:changed_targets, [])

      %{git_commit_sha: oldest} ->
        [files, targets] =
          Tuist.Tasks.parallel_tasks([
            fn -> Commits.changed_files(project.id, oldest, sha, @listed + 1) end,
            fn -> Commits.changed_targets(project.id, oldest, sha, @listed + 1) end
          ])

        socket
        |> assign(
          :changed_files,
          Enum.map(
            files,
            &Map.merge(&1, %{name: Path.basename(&1.path), detail: parent_dir(&1.path), href: file_href(socket, &1.path)})
          )
        )
        |> assign(:changed_targets, Enum.map(targets, &Map.put(&1, :detail, files_label(&1.files_count))))
    end
  end

  defp assign_changes(socket), do: socket |> assign(:changed_files, []) |> assign(:changed_targets, [])

  # A file opens over the branch and period shown here, and leads back here.
  defp file_href(%{assigns: %{selected_account: account, selected_project: project, branch: branch} = assigns}, path) do
    from =
      if assigns.uri.query in [nil, ""], do: assigns.current_path, else: assigns.current_path <> "?" <> assigns.uri.query

    coverage_file_href(account.name, project.name, path, branch, assigns.current_params, from)
  end

  # The runs that named the branch in the period, newest first, as its page's
  # Test Runs tab lists them (`Commits.run_cursor_page/3`).
  defp assign_recent_runs(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    page = Commits.run_cursor_page(project.id, {:branch, branch}, period_opts(socket) ++ [page_size: @recent_runs])
    assign(socket, :run_rows, Enum.map(page.runs, &Map.put(&1, :id, &1.test_run_id)))
  end

  # The branch's own page, on one of its tabs over the period shown here,
  # leading back here as shown.
  @doc false
  def branch_href(%{selected_account: account, selected_project: project, branch: branch} = assigns, tab) do
    period = Map.filter(assigns.current_params, fn {key, _value} -> String.starts_with?(key, "coverage-") end)

    from =
      if assigns.uri.query in [nil, ""], do: assigns.current_path, else: assigns.current_path <> "?" <> assigns.uri.query

    "/#{account.name}/#{project.name}/tests/coverage/branches/#{encode_path(branch)}?" <>
      URI.encode_query(Map.merge(period, %{"tab" => tab, "from" => from}))
  end

  # A chart point opens its commit's page, which leads back here as shown.
  @doc false
  def commit_href(%{selected_account: account, selected_project: project, current_path: path, uri: uri}, sha) do
    from = if uri.query in [nil, ""], do: path, else: path <> "?" <> uri.query
    "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <> URI.encode_query(%{"from" => from})
  end

  defp files_label(count), do: dngettext("dashboard_tests", "%{count} file", "%{count} files", count)

  # Each commit's change is from the complete commit before it, read below
  # the list when it is the oldest (`History.commit_cursor_page/3`).
  defp assign_recent_commits(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    page =
      History.commit_cursor_page(
        project,
        branch,
        period_opts(socket) ++ [status: "complete", page_size: @recent_commits]
      )

    assign(socket, :commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    %{grouping: grouping, points: points} = History.trend_points(project, branch, period_opts(socket))
    latest = List.last(points)

    socket
    |> assign(:points, points)
    |> assign(:grouping, grouping)
    |> assign(:latest, latest)
    |> assign(:trends, %{
      "coverage" => period_trend(points),
      "covered_lines" => count_trend(points, :covered_lines),
      "executable_lines" => count_trend(points, :executable_lines)
    })
  end

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)

  defp schedule_reload(%{assigns: %{reload_scheduled: true}} = socket), do: socket

  defp schedule_reload(socket) do
    Process.send_after(self(), :reload, @reload_delay)
    assign(socket, :reload_scheduled, true)
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"
end
