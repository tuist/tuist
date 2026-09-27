defmodule TuistWeb.CoverageDetailLive do
  @moduledoc """
  One subject's coverage in detail: a commit, a branch or a pull request.
  The three read the same because a branch and a pull request are a series
  of commits with a head, and every figure on the page describes that head:
  what its runs measured, pooled over the schemes that measured it.

  Overview holds the totals and where the head is thinnest (a branch's also
  its coverage over the period); Commits lists the series (a commit has
  none); Targets and Files list everything the head measured; Test Runs the
  runs behind the subject. The project's Code Coverage page
  (`TuistWeb.CoverageLive`) is the glance that sends readers here.
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

  @tabs ~w(overview commits targets files runs)
  @widgets ~w(coverage covered_lines executable_lines)
  @page_size 20
  # How many rows the overview's files hold: a highlight, not a listing.

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

  @doc false
  def file_href(%{selected_account: account, selected_project: project, subject: subject, tab: tab} = assigns, path) do
    coverage_file_href(account.name, project.name, path, %{commit: subject.sha, tab: tab, from: here(assigns)})
  end

  @doc "A commit's page, reached from this one, whose back button leads here."
  def commit_href(%{selected_account: account, selected_project: project} = assigns, sha) do
    "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <>
      URI.encode_query(%{"from" => here(assigns)})
  end

  # This page as it is shown (its tab, period and page), for the pages it
  # links to to lead back to.
  defp here(%{page_path: path, uri: %URI{query: query}}) when query not in [nil, ""], do: path <> "?" <> query
  defp here(%{page_path: path}), do: path

  # A page opened from a branch, a pull request or a commit leads back to
  # it; any other leads back to the Code Coverage page.
  defp assign_back(%{assigns: %{selected_account: account, selected_project: project}} = socket, query) do
    assign(
      socket,
      :back,
      back_to(query["from"], account.name, project.name) ||
        %{
          label: dgettext("dashboard_tests", "Code coverage"),
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
  defp concerns?(%{kind: :pull_request}, _test_run), do: true
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
    |> assign(:subject, %{kind: :commit, name: short_sha(sha), sha: sha, branch: nil, pull_request_number: nil})
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
      branch: branch,
      pull_request_number: nil
    })
    |> assign_summary(Commits.summary(project.id, head.git_commit_sha))
  end

  defp assign_subject(%{assigns: %{live_action: :pull_request, selected_project: project}} = socket, params) do
    number =
      case Integer.parse(params["pull_request_number"] || "") do
        {number, ""} -> number
        _ -> raise NotFoundError, dgettext("dashboard_tests", "Pull request not found.")
      end

    commits = History.pull_request_commits(project.id, number)

    if commits == [] do
      raise NotFoundError,
            dgettext("dashboard_tests", "No test run of pull request #%{number} gathered coverage.", number: number)
    end

    head = hd(commits)

    socket
    |> assign(:params, params)
    |> assign(:subject, %{
      kind: :pull_request,
      name: "##{number}",
      sha: head.git_commit_sha,
      branch: head.git_branch,
      base_branch: head.base_branch,
      pull_request_number: number
    })
    |> assign(:commits, commits)
    |> assign_summary(Commits.summary(project.id, head.git_commit_sha))
  end

  defp assign_summary(socket, summary),
    do: assign(socket, :summary, Map.put(summary, :reported, Commits.reported_figure(summary)))

  defp assign_tab(%{assigns: %{subject: subject}} = socket, query) do
    socket = assign(socket, :tab, tab(subject, query["tab"]))

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "commits" -> assign_commits(socket, query)
      "targets" -> assign_targets(socket)
      "files" -> assign_files(socket, query)
      "runs" -> assign_runs(socket, query)
    end
  end

  defp tab(subject, value), do: if(value in tabs(subject), do: value, else: "overview")

  defp assign_overview(%{assigns: %{selected_project: project, summary: summary}} = socket) do
    # The tests that ran are only read for the card that breaks the
    # coverage down.
    ran_tests = if coverage_breakdown?(summary), do: Commits.ran_tests_count(project.id, summary.test_run_ids), else: 0

    socket
    |> assign(:ran_tests_count, ran_tests)
    |> assign_analytics()
  end

  # A branch leads with its coverage over the period, as the Code Coverage
  # page does for the default branch.
  defp assign_analytics(%{assigns: %{selected_project: project, subject: %{kind: :branch, branch: branch}}} = socket) do
    points = History.branch_points(project, branch, period_opts(socket))

    socket
    |> assign(:points, chart_points(points, socket.assigns.coverage_period))
    |> assign(:latest, List.last(points))
    |> assign(:trends, %{
      "coverage" => period_trend(points),
      "covered_lines" => count_trend(points, :covered_lines),
      "executable_lines" => count_trend(points, :executable_lines)
    })
  end

  defp assign_analytics(socket), do: socket

  defp assign_commits(%{assigns: %{subject: %{kind: :pull_request}, commits: commits}} = socket, query) do
    {search, status} = commits_filter(query)

    commits =
      Enum.filter(commits, fn commit ->
        in_period?(socket, commit.ran_at) and String.starts_with?(commit.git_commit_sha, search) and
          (status == "" or pull_request_commit_status(commit) == status)
      end)

    total_pages = max(1, ceil(length(commits) / @page_size))
    page = min(Query.bounded_page(query["page"]), total_pages)

    socket
    |> assign(
      :commit_rows,
      commits
      |> Enum.slice((page - 1) * @page_size, @page_size)
      |> Enum.map(&(&1 |> Map.put(:id, &1.git_commit_sha) |> Map.put(:measured, true)))
    )
    |> assign(:commits_meta, %{cursor: false, current_page: page, total_pages: total_pages})
    |> assign(:commits_ordered_by, :time)
    |> assign_commits_filter(search, status)
  end

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

  @doc "The statuses the Commits tab filters a subject's commits by, with their labels."
  def commit_statuses(:pull_request),
    do: [{"complete", dgettext("dashboard_tests", "Complete")}, {"pending", dgettext("dashboard_tests", "Pending")}]

  def commit_statuses(_kind),
    do: [
      {"complete", dgettext("dashboard_tests", "Complete")},
      {"pending", dgettext("dashboard_tests", "Pending")},
      {"not-measured", dgettext("dashboard_tests", "Not measured")}
    ]

  defp pull_request_commit_status(%{complete: true}), do: "complete"
  defp pull_request_commit_status(_commit), do: "pending"

  defp assign_targets(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    targets = Commits.targets(project.id, subject.sha)
    assign(socket, :target_rows, Enum.map(targets, &Map.put(&1, :id, "target-" <> &1.name)))
  end

  defp assign_files(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    page = Query.bounded_page(query["page"])
    {files, count} = Commits.list_files(project.id, subject.sha, page, @page_size)
    total_pages = max(1, ceil(count / @page_size))

    socket
    |> assign(:file_rows, Enum.map(files, &Map.put(&1, :id, &1.path)))
    |> assign(:files_meta, %{current_page: min(page, total_pages), total_pages: total_pages})
  end

  # The runs behind the subject: one commit's, a pull request's commits', or
  # those of a page of the branch's commits, so a long branch never loads
  # more than a page.
  defp assign_runs(%{assigns: %{selected_project: project, subject: %{kind: :branch}}} = socket, query) do
    page = branch_commit_page(socket, query)
    shas = page.commits |> Enum.filter(& &1.measured) |> Enum.map(& &1.git_commit_sha)

    socket
    |> assign_run_rows(Commits.runs(project.id, shas))
    |> assign(:runs_meta, cursor_meta(page))
  end

  defp assign_runs(
         %{assigns: %{selected_project: project, subject: %{kind: :pull_request}, commits: commits}} = socket,
         _query
       ) do
    runs =
      project.id
      |> Commits.runs(Enum.map(commits, & &1.git_commit_sha))
      |> Enum.filter(&in_period?(socket, &1.ran_at))

    socket
    |> assign_run_rows(runs)
    |> assign(:runs_meta, nil)
  end

  defp assign_runs(%{assigns: %{selected_project: project, subject: subject}} = socket, _query) do
    socket
    |> assign_run_rows(Commits.runs(project.id, subject.sha))
    |> assign(:runs_meta, nil)
  end

  defp assign_run_rows(socket, runs),
    do: assign(socket, :run_rows, runs |> Enum.reverse() |> Enum.map(&Map.put(&1, :id, &1.test_run_id)))

  defp branch_commit_page(%{assigns: %{selected_project: project, subject: subject}} = socket, query, filter \\ []) do
    History.commit_cursor_page(
      project,
      subject.branch,
      period_opts(socket) ++ filter ++ [after: query["after"], before: query["before"], page_size: @page_size]
    )
  end

  defp cursor_meta(page),
    do: page |> Map.take([:has_next_page?, :has_previous_page?, :start_cursor, :end_cursor]) |> Map.put(:cursor, true)

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)

  @doc false
  def drop_paging(query), do: query |> Query.drop("page") |> Query.drop("after") |> Query.drop("before")

  # A pull request's commits and runs are all read for the subject, so the
  # period narrows its lists here.
  defp in_period?(socket, at) do
    [since: since, until: until] = period_opts(socket)
    at = if is_struct(at, DateTime), do: DateTime.to_naive(at), else: at
    NaiveDateTime.compare(at, since) != :lt and NaiveDateTime.before?(at, until)
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"

  @doc "What the page's title calls its subject."
  def subject_title(%{kind: :commit, name: name}), do: dgettext("dashboard_tests", "Commit %{name}", name: name)

  def subject_title(%{kind: :pull_request, name: name}),
    do: dgettext("dashboard_tests", "Pull request %{name}", name: name)

  def subject_title(%{kind: :branch, name: name}), do: dgettext("dashboard_tests", "Branch %{name}", name: name)

  @doc "The tabs the subject has: a commit is not a series, so it has no commits of its own."
  def tabs(%{kind: :commit}), do: ~w(overview targets files runs)
  def tabs(_subject), do: @tabs

  def tab_label("overview"), do: dgettext("dashboard_tests", "Overview")
  def tab_label("commits"), do: dgettext("dashboard_tests", "Commits")
  def tab_label("targets"), do: dgettext("dashboard_tests", "Targets")
  def tab_label("files"), do: dgettext("dashboard_tests", "Files")
  def tab_label("runs"), do: dgettext("dashboard_tests", "Test Runs")
end
