defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page: a glance at the default branch over the
  chosen period — its coverage now and over time, the commits behind it with
  the unmeasured ones in place, and where its latest commit is thinnest.
  Every figure is a commit's, pooled over the schemes that measured it.

  Everything with more to say lives one click away: a commit's own page,
  the default branch's page (`TuistWeb.CoverageDetailLive`) behind each
  card's "View more", and every other branch behind "Other branches"
  (`TuistWeb.CoverageBranchesLive`).

  Its settings live under the project's settings
  (`TuistWeb.ProjectCoverageSettingsLive`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  # Every list here is a glance at the head of something longer, which the
  # cards' "View more" leads to.
  @commits_preview_size 5
  @preview_size 5

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Code Coverage")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("tests"))

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

    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> Query.drop(query, "page"))}
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply, assign_page(socket, socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_page(socket, _query) do
    socket
    |> assign_analytics()
    |> assign_commits()
    |> assign_movements()
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    points = History.branch_points(project, branch, period_opts(socket))
    latest = List.last(points)

    socket
    |> assign(:points, chart_points(points, socket.assigns.coverage_period))
    |> assign(:latest, latest)
    |> assign(:trend, period_trend(points))
  end

  defp assign_commits(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    page =
      History.commit_cursor_page(project, branch, Keyword.put(period_opts(socket), :page_size, @commits_preview_size))

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  # Where the coverage is thinnest at the branch's latest commit: the least
  # covered files, and the tracked files no scheme measured at all.
  # The head commit read exactly as its own page reads it: where its targets
  # and files moved against its baseline, where it is thinnest, and which
  # files have no coverage data. The cards are the branch page's own.
  defp assign_movements(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    head = History.head_commit(project, branch, period_opts(socket))

    socket
    |> assign(:head_commit, head)
    |> assign_head_movements(head)
  end

  defp assign_head_movements(socket, nil) do
    socket
    |> assign(:comparison, nil)
    |> assign(:target_rises, [])
    |> assign(:target_falls, [])
    |> assign(:file_rises, [])
    |> assign(:file_falls, [])
    |> assign(:least_covered_files, [])
    |> assign(:unmeasured_files, [])
  end

  defp assign_head_movements(%{assigns: %{selected_project: project}} = socket, head) do
    sha = head.git_commit_sha

    [comparison, {files, _count}, unmeasured] =
      Tuist.Tasks.parallel_tasks([
        fn -> project |> Comparison.from_commit(sha) |> then(&Comparison.compare(project, &1)) end,
        fn -> Commits.list_files(project.id, sha, 1, @preview_size) end,
        fn -> Commits.unmeasured_files(project, sha, limit: @preview_size) end
      ])

    socket
    |> assign(:comparison, comparison)
    |> assign(:target_rises, movers(comparison.targets, :desc, "target-rise"))
    |> assign(:target_falls, movers(comparison.targets, :asc, "target-fall"))
    |> assign(:file_rises, movers(comparison.files, :desc, "file-rise"))
    |> assign(:file_falls, movers(comparison.files, :asc, "file-fall"))
    |> assign(:least_covered_files, Enum.map(files, &Map.put(&1, :id, "gap-" <> &1.path)))
    |> assign(:unmeasured_files, Enum.map(unmeasured, &%{id: "unmeasured-" <> &1, path: &1}))
  end

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)
end
