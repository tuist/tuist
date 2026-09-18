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
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  # The commits list is a recent history to glance at, not an archive: five
  # rows a page, ten pages of them.
  @commits_page_size 5
  @commits_limit 50
  # How many rows the cards that only point somewhere else hold.
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

    socket =
      assign_page(socket, query)

    {:noreply, socket}
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

    {:noreply, push_patch(socket, to: "?" <> Query.drop(query, "page"))}
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply, assign_page(socket, socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_page(socket, query) do
    socket
    |> assign_analytics()
    |> assign_commits(query)
    |> assign_gaps()
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    points = History.branch_points(project, branch, period_opts(socket))
    latest = List.last(points)
    first = List.first(points)

    socket
    |> assign(:points, points)
    |> assign(:latest, latest)
    |> assign(:trend, if(latest && first && latest != first, do: Float.round(latest.coverage - first.coverage, 1)))
  end

  defp assign_commits(%{assigns: %{selected_project: project, branch: branch}} = socket, query) do
    page =
      History.commit_page(
        project,
        branch,
        Keyword.merge(period_opts(socket),
          page: Query.bounded_page(query["commits-page"]),
          page_size: @commits_page_size,
          max_commits: @commits_limit
        )
      )

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, %{current_page: page.page, total_pages: page.total_pages, total_count: page.total_count})
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  # Where the coverage is thinnest at the branch's latest commit: the least
  # covered files, and the tracked files no scheme measured at all.
  defp assign_gaps(%{assigns: %{selected_project: project, latest: latest}} = socket) do
    {files, unmeasured} =
      if latest do
        [{files, _count}, unmeasured] =
          Tuist.Tasks.parallel_tasks([
            fn -> Commits.list_files(project.id, latest.git_commit_sha, 1, @preview_size) end,
            fn -> Commits.unmeasured_files(project, latest.git_commit_sha, limit: @preview_size) end
          ])

        {files, unmeasured}
      else
        {[], []}
      end

    socket
    |> assign(:gap_files, Enum.map(files, &Map.put(&1, :id, "gap-" <> &1.path)))
    |> assign(:unmeasured_files, Enum.map(unmeasured, &%{id: "unmeasured-" <> &1, path: &1}))
  end

  defp period_opts(%{assigns: %{coverage_period: {start_datetime, end_datetime}}}) do
    [since: DateTime.to_naive(start_datetime), until: DateTime.to_naive(end_datetime)]
  end
end
