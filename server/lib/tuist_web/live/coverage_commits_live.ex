defmodule TuistWeb.CoverageCommitsLive do
  @moduledoc """
  A branch's commits in a period, the Code Coverage page's Recent commits
  in full: every commit, measured or not, newest first, a page at a time
  from a cursor (`History.commit_cursor_page/3`), searched by the start of
  a SHA and filtered by status. The branch and the period are picked as on
  the Code Coverage page and kept when moving between the two
  (`with_shared_query/2`).
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

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_tests", "Commits")} · #{account.name}/#{project.name} · Tuist")
     |> assign(OpenGraph.og_image_assigns("tests"))
     |> assign(:branches, [])}
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
      |> assign(:commits_search, (query["commits-search"] || "") |> String.trim() |> String.downcase())
      |> assign(:commits_status, query["commits-status"] || "")

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

    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> drop_cursor(query))}
  end

  def handle_event("search-commits", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("commits-search", search) |> drop_cursor()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  defp assign_page(%{assigns: %{selected_project: project, branch: branch}} = socket, query) do
    page =
      History.commit_cursor_page(
        project,
        branch,
        DatePicker.period_opts(socket.assigns.coverage_period) ++
          [
            search: socket.assigns.commits_search,
            status: socket.assigns.commits_status,
            after: query["after"],
            before: query["before"],
            page_size: @page_size
          ]
      )

    socket
    |> assign(:branches, History.branches(project))
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, Map.take(page, [:has_next_page?, :has_previous_page?, :start_cursor, :end_cursor]))
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  @doc "The statuses the list filters by, with their labels."
  def commit_statuses,
    do: [
      {"complete", dgettext("dashboard_tests", "Complete")},
      {"pending", dgettext("dashboard_tests", "In Progress")},
      {"not-measured", dgettext("dashboard_tests", "Not measured")}
    ]

  # A cursor names a row of one listing; another period, search or status
  # starts over.
  @doc false
  def drop_cursor(query), do: query |> Query.drop("after") |> Query.drop("before")
end
