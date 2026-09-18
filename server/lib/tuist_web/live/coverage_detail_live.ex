defmodule TuistWeb.CoverageDetailLive do
  @moduledoc """
  One subject's coverage in detail: a branch, a pull request, or a single
  commit. The three read the same because they are the same thing seen at
  different distances — a branch and a pull request are a series of commits
  with a head, and every figure on the page describes that head commit
  against its baseline.

  Overview holds what the head measured and how it moved, the schemes that
  measured it, where coverage rose and fell most, and the project's gates;
  Commits lists the series (a single commit has none); Targets and Files
  list everything the head measured. The project's Code Coverage page
  (`TuistWeb.CoverageLive`) is the glance at the default branch that sends
  readers here.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(overview commits targets files)
  @page_size 20
  # How many rows the rises and falls hold: a highlight, not a listing.
  @highlight_size 5

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

  def handle_params(params, uri, socket) do
    query = Query.query_params(uri)

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:current_params, query)
      |> assign_subject(params, query)

    {:noreply, assign_tab(socket, query)}
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply,
     socket
     |> assign_subject(socket.assigns.params, socket.assigns.current_params)
     |> assign_tab(socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  # What the page is about, and the head commit every figure describes.
  defp assign_subject(%{assigns: %{live_action: :commit}} = socket, params, _query) do
    sha = params["git_commit_sha"]
    project = socket.assigns.selected_project

    if sha in [nil, ""] or is_nil(Commits.summary(project.id, sha)) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    socket
    |> assign(:params, params)
    |> assign(:subject, %{kind: :commit, name: short_sha(sha), sha: sha, branch: nil, pull_request_number: nil})
    |> assign(:series, [])
  end

  defp assign_subject(%{assigns: %{live_action: :pull_request}} = socket, params, query) do
    project = socket.assigns.selected_project

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

    head = Enum.find(commits, hd(commits), &(&1.git_commit_sha == query["commit"]))

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
    # A pull request's commits are timed by when they were measured, which is
    # what the chart draws them against.
    |> assign(:series, commits |> Enum.reverse() |> Enum.map(&Map.put(&1, :inserted_at, &1.ran_at)))
  end

  defp assign_subject(%{assigns: %{live_action: :branch}} = socket, params, _query) do
    project = socket.assigns.selected_project
    branch = params["branch"] |> List.wrap() |> Enum.join("/")

    head =
      case History.head_commit(project, branch) do
        nil ->
          raise NotFoundError,
                dgettext("dashboard_tests", "No run on branch %{branch} gathered coverage.", branch: branch)

        head ->
          head
      end

    socket
    |> assign(:params, params)
    |> assign(:subject, %{
      kind: :branch,
      name: branch,
      sha: head.git_commit_sha,
      branch: branch,
      pull_request_number: nil
    })
    |> assign(:against_default, History.against_default(project, head))
    |> assign(:series, History.branch_points(project, branch))
  end

  defp assign_tab(socket, query) do
    socket = socket |> assign(:tab, tab(socket, query["tab"])) |> assign_comparison()

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "commits" -> assign_commits(socket, query)
      "targets" -> assign_targets(socket)
      "files" -> assign_files(socket, query)
    end
  end

  defp tab(%{assigns: %{subject: %{kind: :commit}}}, "commits"), do: "overview"
  defp tab(_socket, value) when value in @tabs, do: value
  defp tab(_socket, _value), do: "overview"

  # Every tab reads the head commit against its baseline, which is also what
  # the gates were decided on.
  defp assign_comparison(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    head = Comparison.from_commit(project, subject.sha)
    comparison = Comparison.compare(project, head)

    socket
    |> assign(:head, head)
    |> assign(:comparison, comparison)
    |> assign(:gates, Gates.settings(project))
    |> assign(:gate_verdict, if(project.coverage_gates_enabled, do: Gates.evaluate(project, comparison)))
  end

  defp assign_overview(%{assigns: %{selected_project: project, comparison: comparison, subject: subject}} = socket) do
    socket
    |> assign(:commit_runs, Commits.runs(project.id, subject.sha))
    |> assign(:scheme_rows, Enum.map(comparison.schemes, &Map.put(&1, :id, "scheme-" <> &1.scheme)))
    |> assign(:target_rises, highlights(comparison.targets, :desc, "target-rise"))
    |> assign(:target_falls, highlights(comparison.targets, :asc, "target-fall"))
    |> assign(:file_rises, highlights(comparison.files, :desc, "file-rise"))
    |> assign(:file_falls, highlights(comparison.files, :asc, "file-fall"))
    |> assign(:patch_rows, patch_rows(comparison.patch))
    |> assign(:skipped_rows, skipped_rows(comparison.patch))
  end

  # The rows that moved most in one direction, largest first. A row that did
  # not move, or has nothing to compare with, is not a highlight.
  defp highlights(rows, direction, prefix) do
    rows
    |> Enum.filter(&(is_float(&1.delta) and moved?(&1.delta, direction)))
    |> Enum.sort_by(& &1.delta, direction)
    |> Enum.take(@highlight_size)
    |> Enum.map(fn row ->
      # A target is named, a file is a path; both read as a name here.
      name = Map.get(row, :name) || Map.fetch!(row, :path)
      row |> Map.put(:name, name) |> Map.put(:id, prefix <> "-" <> name)
    end)
  end

  defp moved?(delta, :desc), do: delta > 0
  defp moved?(delta, :asc), do: delta < 0

  defp assign_commits(%{assigns: %{subject: %{kind: :pull_request}, commits: commits}} = socket, query) do
    page = Query.bounded_page(query["page"])
    total_pages = max(1, ceil(length(commits) / @page_size))
    page = min(page, total_pages)

    socket
    |> assign(
      :commit_rows,
      commits
      |> Enum.slice((page - 1) * @page_size, @page_size)
      |> Enum.map(&(&1 |> Map.put(:id, &1.git_commit_sha) |> Map.put(:measured, true) |> Map.put_new(:change, nil)))
    )
    |> assign(:commits_meta, %{current_page: page, total_pages: total_pages})
    |> assign(:commits_ordered_by, :time)
  end

  defp assign_commits(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    page = History.commit_page(project, subject.branch, page: Query.bounded_page(query["page"]), page_size: @page_size)

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, %{current_page: page.page, total_pages: page.total_pages})
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  defp assign_targets(%{assigns: %{comparison: comparison}} = socket) do
    assign(socket, :target_rows, Enum.map(comparison.targets, &Map.put(&1, :id, "target-" <> &1.name)))
  end

  defp assign_files(%{assigns: %{selected_project: project, comparison: comparison, subject: subject}} = socket, query) do
    page = Query.bounded_page(query["page"])
    total_pages = max(1, ceil(length(comparison.files) / @page_size))

    socket
    |> assign(
      :file_rows,
      comparison.files |> Enum.slice((page - 1) * @page_size, @page_size) |> Enum.map(&Map.put(&1, :id, &1.path))
    )
    |> assign(:files_meta, %{current_page: min(page, total_pages), total_pages: total_pages})
    |> assign(:unmeasured_files, unmeasured_files(project, subject.sha))
  end

  defp unmeasured_files(project, sha) do
    project
    |> Commits.unmeasured_files(sha, limit: @page_size)
    |> Enum.map(&%{id: "unmeasured-" <> &1, path: &1})
  end

  defp patch_rows(%{status: :available, files: files}), do: Enum.map(files, &Map.put(&1, :id, "patch-" <> &1.path))
  defp patch_rows(_patch), do: []

  defp skipped_rows(%{status: :available, skipped: skipped}),
    do: Enum.map(skipped, &Map.put(&1, :id, "skipped-" <> &1.path))

  defp skipped_rows(_patch), do: []

  @doc "What the page's title calls its subject."
  def subject_title(%{kind: :commit, name: name}), do: dgettext("dashboard_tests", "Commit %{name}", name: name)

  def subject_title(%{kind: :pull_request, name: name}),
    do: dgettext("dashboard_tests", "Pull request %{name}", name: name)

  def subject_title(%{kind: :branch, name: name}), do: dgettext("dashboard_tests", "Branch %{name}", name: name)

  @doc "The tabs the subject has: a commit is not a series, so it has no commits of its own."
  def tabs(%{kind: :commit}), do: ~w(overview targets files)
  def tabs(_subject), do: @tabs

  def tab_label("overview"), do: dgettext("dashboard_tests", "Overview")
  def tab_label("commits"), do: dgettext("dashboard_tests", "Commits")
  def tab_label("targets"), do: dgettext("dashboard_tests", "Targets")
  def tab_label("files"), do: dgettext("dashboard_tests", "Files")
end
