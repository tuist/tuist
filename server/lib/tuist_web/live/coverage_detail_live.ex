defmodule TuistWeb.CoverageDetailLive do
  @moduledoc """
  One subject's coverage in detail: a commit or a branch. The two read the
  same because a branch is a series of commits with a head, and every
  figure on the page describes that head: what its runs measured, pooled
  over the schemes that measured it.

  Overview holds the totals (a branch's also its coverage over the period); Commits lists the series (a commit has
  none); Targets and Files list everything the head measured; Test Runs the
  runs behind the subject. The project's Code Coverage page
  (`TuistWeb.CoverageLive`) is the glance that sends readers here.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Noora.Filter
  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(overview commits targets files runs)
  @widgets ~w(coverage covered_lines executable_lines)
  @target_sorts ~w(coverage name files)
  @file_sorts ~w(coverage path)
  @page_size 20

  # A run's coverage joins its commit a few seconds after the run lands
  # (`Tuist.Tests.Coverage.Workers.CommitWorker`), so the page reloads once
  # after a burst of runs rather than once per run, before the fold.
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
      |> assign(:available_filters, [])
      |> assign(:active_filters, [])

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    query = Query.query_params(uri)
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:page_path, URI.parse(uri).path)
      |> assign(:current_params, query)
      |> assign_back(query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign(:selected_widget, selected_widget(query["analytics-selected-widget"]))
      |> assign_subject(params)

    # The static render resolves the subject, so a missing one is still a
    # 404, and leaves the rest to the connected one.
    if connected?(socket) do
      {:noreply, socket |> assign(:loading, false) |> assign_tab(query)}
    else
      {:noreply, socket |> assign(:loading, true) |> assign(:tab, tab(socket.assigns.subject, query["tab"]))}
    end
  end

  @doc """
  A file's own page: a branch's over the branch and the period shown here,
  a commit's at that commit, each leading back here.
  """
  def file_href(%{subject: %{kind: :branch, branch: branch}} = assigns, path),
    do:
      coverage_file_href(
        assigns.selected_account.name,
        assigns.selected_project.name,
        path,
        branch,
        URI.decode_query(assigns.uri.query || ""),
        here(assigns)
      )

  def file_href(%{subject: %{kind: :commit, sha: sha}} = assigns, path),
    do:
      coverage_file_href(
        assigns.selected_account.name,
        assigns.selected_project.name,
        path,
        {:commit, sha},
        here(assigns)
      )

  @doc "A commit's page, reached from this one, whose back button leads here."
  def commit_href(%{selected_account: account, selected_project: project} = assigns, sha) do
    "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <>
      URI.encode_query(%{"from" => here(assigns)})
  end

  # This page as it is shown (its tab, period and page), for the pages it
  # links to to lead back to.
  defp here(%{page_path: path, uri: %URI{query: query}}) when query not in [nil, ""], do: path <> "?" <> query
  defp here(%{page_path: path}), do: path

  # A page opened from a branch or a commit leads back to it; any other leads back to the Code Coverage page.
  defp assign_back(%{assigns: %{selected_account: account, selected_project: project}} = socket, query) do
    assign(
      socket,
      :back,
      back_to(query["from"], account.name, project.name) ||
        %{
          label: dgettext("dashboard_tests", "Code Coverage"),
          href: "/#{account.name}/#{project.name}/tests/coverage"
        }
    )
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

    {:noreply,
     push_patch(socket,
       to:
         socket.assigns.current_path <>
           "?" <> (query |> Query.drop("page") |> Query.drop("after") |> Query.drop("before"))
     )}
  end

  def handle_event("search-commits", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("commits-search", search) |> drop_paging()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  def handle_event("search-targets", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("targets-search", search) |> drop_paging()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  def handle_event("search-files", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("files-search", search) |> drop_paging()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  def handle_event("search-runs", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("runs-search", search) |> drop_paging()
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    query = filter_id |> Filter.Operations.add_filter_to_query(socket) |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.current_path <> "?" <> URI.encode_query(query))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    query = params |> Filter.Operations.update_filters_in_query(socket) |> Map.delete("page")

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.current_path <> "?" <> URI.encode_query(query))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
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

  def handle_info({:test_created, test_run}, %{assigns: %{subject: subject}} = socket) do
    if concerns?(subject, test_run), do: {:noreply, schedule_reload(socket)}, else: {:noreply, socket}
  end

  def handle_info(:reload, %{assigns: %{selected_project: project, subject: subject}} = socket) do
    socket = assign(socket, :reload_scheduled, false)

    # A commit whose coverage is gone (past its retention) keeps the page it
    # had rather than crashing it.
    if Commits.measured?(project.id, subject.sha) do
      {:noreply,
       socket
       |> assign_subject(socket.assigns.params)
       |> assign_tab(socket.assigns.current_params)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp concerns?(%{kind: :commit, sha: sha}, %{git_commit_sha: sha}), do: true
  defp concerns?(%{kind: :branch, branch: branch}, %{git_branch: branch}), do: true
  defp concerns?(_subject, _test_run), do: false

  defp schedule_reload(%{assigns: %{reload_scheduled: true}} = socket), do: socket

  defp schedule_reload(socket) do
    Process.send_after(self(), :reload, @reload_delay)
    assign(socket, :reload_scheduled, true)
  end

  # What the page is about, and the head commit every figure describes.
  defp assign_subject(%{assigns: %{live_action: :commit, selected_project: project}} = socket, params) do
    sha = params["git_commit_sha"]
    summary = Commits.summary(project.id, sha)

    if is_nil(summary) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    socket
    |> assign(:params, params)
    |> assign(:subject, %{kind: :commit, name: short_sha(sha), sha: sha, branch: nil})
    |> assign_summary(summary)
  end

  defp assign_subject(%{assigns: %{live_action: :branch, selected_project: project}} = socket, params) do
    branch = params["branch"] |> List.wrap() |> Enum.join("/")

    head =
      History.head_commit(project, branch) ||
        raise NotFoundError,
              dgettext("dashboard_tests", "No run on branch %{branch} gathered coverage.", branch: branch)

    socket
    |> assign(:params, params)
    |> assign(:subject, %{
      kind: :branch,
      name: branch,
      sha: head.git_commit_sha,
      branch: branch
    })
    |> assign_summary(Commits.summary(project.id, head.git_commit_sha))
  end

  defp assign_summary(socket, summary),
    do: assign(socket, :summary, Map.put(summary, :reported, Commits.reported_figure(summary)))

  defp assign_tab(%{assigns: %{subject: subject}} = socket, query) do
    socket = assign(socket, :tab, tab(subject, query["tab"]))

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "commits" -> assign_commits(socket, query)
      "targets" -> assign_targets(socket, query)
      "files" -> assign_files(socket, query)
      "runs" -> assign_runs(socket, query)
    end
  end

  defp tab(subject, value), do: if(value in tabs(subject), do: value, else: "overview")

  defp assign_overview(socket), do: assign_analytics(socket)

  # A branch leads with its coverage over the period, as the Code Coverage
  # page does for the default branch.
  defp assign_analytics(%{assigns: %{selected_project: project, subject: %{kind: :branch, branch: branch}}} = socket) do
    %{grouping: grouping, points: points} = History.trend_points(project, branch, period_opts(socket))

    socket
    |> assign(:points, points)
    |> assign(:grouping, grouping)
    |> assign(:latest, List.last(points))
    |> assign(:trends, %{
      "coverage" => period_trend(points),
      "covered_lines" => count_trend(points, :covered_lines),
      "executable_lines" => count_trend(points, :executable_lines)
    })
  end

  defp assign_analytics(socket), do: socket

  # A branch's commits are read a page at a time from a cursor, however long
  # its history.
  defp assign_commits(%{assigns: %{subject: %{kind: :branch}}} = socket, query) do
    {search, status} = commits_filter(query)
    page = branch_commit_page(socket, query, search: search, status: status)

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, cursor_meta(page))
    |> assign(:commits_ordered_by, page.ordered_by)
    |> assign_commits_filter(search, status)
  end

  # The Commits tab's search, by the start of a SHA, and its status: whether
  # the commit's pipeline signalled it finished, and on a branch, which lists
  # every commit on it, whether any run measured it.
  defp commits_filter(query) do
    search = (query["commits-search"] || "") |> String.trim() |> String.downcase()
    {search, query["commits-status"] || ""}
  end

  defp assign_commits_filter(socket, search, status),
    do: socket |> assign(:commits_search, search) |> assign(:commits_status, status)

  @doc "The statuses the Commits tab filters a branch's commits by, with their labels."
  def commit_statuses,
    do: [
      {"complete", dgettext("dashboard_tests", "Complete")},
      {"incomplete", dgettext("dashboard_tests", "Incomplete")},
      {"in-progress", dgettext("dashboard_tests", "In Progress")},
      {"not-measured", dgettext("dashboard_tests", "Not measured")}
    ]

  # A commit has a few thousand targets at most, all aggregated in one read,
  # so they are searched, sorted and paged here.
  defp assign_targets(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    search = String.trim(query["targets-search"] || "")
    filters = Filter.Operations.decode_filters_from_query(query, target_filters(project))
    sort_by = if query["targets-sort-by"] in @target_sorts, do: query["targets-sort-by"], else: "coverage"
    sort_order = if query["targets-sort-order"] in ~w(asc desc), do: query["targets-sort-order"], else: "asc"

    measured = Commits.targets(project.id, subject.sha)

    targets =
      measured
      |> Enum.filter(&(name_matches?(&1.name, :=~, search) and Enum.all?(filters, fn f -> target_matches?(&1, f) end)))
      |> sort_targets(sort_by, sort_order)

    total_pages = max(1, ceil(length(targets) / @page_size))
    page = min(Query.bounded_page(query["page"]), total_pages)

    socket
    |> assign(
      :target_rows,
      targets |> Enum.slice((page - 1) * @page_size, @page_size) |> Enum.map(&Map.put(&1, :id, "target-" <> &1.name))
    )
    |> assign(:targets_measured?, measured != [])
    |> assign(:targets_meta, %{current_page: page, total_pages: total_pages})
    |> assign(:targets_search, search)
    |> assign(:targets_sort_by, sort_by)
    |> assign(:targets_sort_order, sort_order)
    |> assign(:available_filters, target_filters(project))
    |> assign(:active_filters, filters)
  end

  defp target_filters(project) do
    [
      %Filter.Filter{
        id: "target_name",
        field: :name,
        display_name: target_name_label(project),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  defp target_name_label(%{build_system: :mix}), do: dgettext("dashboard_tests", "Application name")
  defp target_name_label(_project), do: dgettext("dashboard_tests", "Target name")

  defp target_matches?(target, %Filter.Filter{field: :name, operator: operator, value: value}),
    do: name_matches?(target.name, operator, value || "")

  defp name_matches?(_name, _operator, ""), do: true
  defp name_matches?(name, :==, value), do: String.downcase(name) == String.downcase(value)
  defp name_matches?(name, :=~, value), do: name |> String.downcase() |> String.contains?(String.downcase(value))
  defp name_matches?(name, :"!=~", value), do: not name_matches?(name, :=~, value)

  defp sort_targets(targets, sort_by, sort_order) do
    direction = String.to_existing_atom(sort_order)

    case sort_by do
      "name" -> Enum.sort_by(targets, & &1.name, direction)
      "files" -> Enum.sort_by(targets, &{&1.files_count, &1.name}, direction)
      "coverage" -> Enum.sort_by(targets, &{&1.covered_lines / max(&1.executable_lines, 1), &1.name}, direction)
    end
  end

  @doc "The Targets tab's sorts, with their labels, in the order of the table's columns."
  def target_sorts(project),
    do: [
      {"name", coverage_target_label(project)},
      {"coverage", dgettext("dashboard_tests", "Coverage")},
      {"files", dgettext("dashboard_tests", "Files")}
    ]

  @doc "The query that sorts the Targets tab by a column: the other order when it already does, ascending otherwise."
  def targets_sort_patch(%{uri: uri, targets_sort_by: sort_by, targets_sort_order: order}, column) do
    order = if sort_by == column and order == "asc", do: "desc", else: "asc"
    "?" <> (uri.query |> Query.put("targets-sort-by", column) |> Query.put("targets-sort-order", order) |> drop_paging())
  end

  defp assign_files(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    page = Query.bounded_page(query["page"])
    search = String.trim(query["files-search"] || "")
    sort_by = if query["files-sort-by"] in @file_sorts, do: query["files-sort-by"], else: "coverage"
    sort_order = if query["files-sort-order"] in ~w(asc desc), do: query["files-sort-order"], else: "asc"

    {files, count} =
      Commits.list_files(project.id, subject.sha, page, @page_size,
        search: search,
        sort: {String.to_existing_atom(sort_by), String.to_existing_atom(sort_order)}
      )

    total_pages = max(1, ceil(count / @page_size))

    socket
    |> assign(:file_rows, Enum.map(files, &Map.put(&1, :id, &1.path)))
    |> assign(:files_meta, %{current_page: min(page, total_pages), total_pages: total_pages})
    |> assign(:files_measured?, count > 0 or search != "")
    |> assign(:files_search, search)
    |> assign(:files_sort_by, sort_by)
    |> assign(:files_sort_order, sort_order)
  end

  @doc "The Files tab's sorts, with their labels, in the order of the table's columns."
  def file_sorts,
    do: [{"path", dgettext("dashboard_tests", "File")}, {"coverage", dgettext("dashboard_tests", "File coverage")}]

  @doc "The query that sorts the Files tab by a column: the other order when it already does, ascending otherwise."
  def files_sort_patch(%{uri: uri, files_sort_by: sort_by, files_sort_order: order}, column) do
    order = if sort_by == column and order == "asc", do: "desc", else: "asc"
    "?" <> (uri.query |> Query.put("files-sort-by", column) |> Query.put("files-sort-order", order) |> drop_paging())
  end

  # The runs behind the subject, newest first and read a page at a time from
  # a cursor, so a long period costs a page: a commit's, or those that named
  # the branch in the period. Runs from a dirty checkout are listed, marked
  # as discarded, so a scheme missing from a figure has its run to show.
  defp assign_runs(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    search = String.trim(query["runs-search"] || "")
    available_filters = run_filters(project, run_schemes(socket))
    filters = Filter.Operations.decode_filters_from_query(query, available_filters)
    period = if subject.kind == :commit, do: [], else: period_opts(socket)

    page =
      Commits.run_cursor_page(
        project.id,
        run_scope(subject),
        period ++
          run_filter_opts(filters) ++
          [search: search, after: query["after"], before: query["before"], page_size: @page_size, dirty: true]
      )

    socket
    |> assign(:run_rows, Enum.map(page.runs, &Map.put(&1, :id, &1.test_run_id)))
    |> assign(:runs_meta, cursor_meta(page))
    |> assign(:runs_search, search)
    |> assign(:runs_filtered?, search != "" or filters != [])
    |> assign(:available_filters, available_filters)
    |> assign(:active_filters, filters)
  end

  defp run_scope(%{kind: :commit, sha: sha}), do: {:commit, sha}
  defp run_scope(%{kind: :branch, branch: branch}), do: {:branch, branch}

  defp run_schemes(%{assigns: %{selected_project: project, subject: %{kind: :branch, branch: branch}}} = socket),
    do: History.branch_schemes(project, branch, period_opts(socket))

  defp run_schemes(%{assigns: %{summary: summary}}),
    do: (summary.schemes ++ summary.partial_schemes) |> Enum.uniq() |> Enum.sort()

  defp run_filters(project, schemes) do
    [
      %Filter.Filter{
        id: "run_kind",
        field: :partial,
        display_name: dgettext("dashboard_tests", "Run"),
        type: :option,
        options: ["full", "partial"],
        options_display_names: %{
          "full" => dgettext("dashboard_tests", "Full"),
          "partial" => dgettext("dashboard_tests", "Partial")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "run_scheme",
        field: :scheme,
        display_name: scheme_label(project),
        type: :option,
        options: schemes,
        options_display_names: %{},
        operator: :==,
        value: nil,
        searchable: true
      }
    ]
  end

  defp run_filter_opts(filters) do
    Enum.flat_map(filters, fn
      %Filter.Filter{value: nil} ->
        []

      %Filter.Filter{field: :partial, operator: operator, value: value} ->
        [partial: value == "partial" == (operator == :==)]

      %Filter.Filter{field: :scheme, operator: operator, value: value} ->
        [scheme: {operator, value}]
    end)
  end

  defp branch_commit_page(%{assigns: %{selected_project: project, subject: subject}} = socket, query, filter) do
    History.commit_cursor_page(
      project,
      subject.branch,
      period_opts(socket) ++ filter ++ [after: query["after"], before: query["before"], page_size: @page_size]
    )
  end

  defp cursor_meta(page), do: Map.take(page, [:has_next_page?, :has_previous_page?, :start_cursor, :end_cursor])

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)

  @doc false
  def drop_paging(query), do: query |> Query.drop("page") |> Query.drop("after") |> Query.drop("before")

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"

  @doc "What the page's title calls its subject."
  def subject_title(%{kind: :commit, name: name}), do: dgettext("dashboard_tests", "Commit %{name}", name: name)

  def subject_title(%{kind: :branch, name: name}), do: dgettext("dashboard_tests", "Branch %{name}", name: name)

  @doc "The tabs the subject has: a commit is not a series, so it has no commits of its own."
  def tabs(%{kind: :commit}), do: ~w(overview targets files runs)
  def tabs(_subject), do: @tabs

  def tab_label(_project, "overview"), do: dgettext("dashboard_tests", "Overview")
  def tab_label(_project, "commits"), do: dgettext("dashboard_tests", "Commits")
  def tab_label(project, "targets"), do: coverage_targets_label(project)
  def tab_label(_project, "files"), do: dgettext("dashboard_tests", "Files")
  def tab_label(_project, "runs"), do: dgettext("dashboard_tests", "Test Runs")
end
