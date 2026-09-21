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
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(overview commits targets files runs)
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
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:current_params, query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign_subject(params, query)

    {:noreply, socket |> assign_tab(query) |> assign_file(query["coverage-file"])}
  end

  # The file the page was asked to open: its coverage at the head commit (the
  # reported one when the commit's skipped tests were all carried forward)
  # and the tests behind it, across the commit's runs.
  defp assign_file(socket, path) when path in [nil, ""],
    do: socket |> assign(:coverage_file, nil) |> assign(:coverage_file_tests, nil)

  defp assign_file(%{assigns: %{selected_project: project, subject: subject}} = socket, path) do
    file = Commits.file_detail(project.id, subject.sha, path)

    tests =
      file &&
        Evidence.covering(%{project_id: project.id, test_run_ids: Commits.run_ids(project.id, subject.sha)}, path)

    socket
    |> assign(:coverage_file, file)
    |> assign(:coverage_file_tests, tests)
  end

  @doc false
  def file_href(%{current_path: current_path, uri: uri}, path),
    do: current_path <> "?" <> Query.put(uri.query, "coverage-file", path)

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
    |> assign(:series, Enum.reverse(commits))
  end

  defp assign_subject(%{assigns: %{live_action: :branch}} = socket, params, _query) do
    project = socket.assigns.selected_project
    branch = params["branch"] |> List.wrap() |> Enum.join("/")
    period = period_opts(socket)

    head =
      case History.head_commit(project, branch, period) do
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
    |> assign(:against_default, History.against_default(project, head, period))
    |> assign(:series, History.branch_points(project, branch, period))
  end

  defp assign_tab(socket, query) do
    socket = socket |> assign(:tab, tab(socket, query["tab"])) |> assign_comparison()

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "commits" -> assign_commits(socket, query)
      "targets" -> assign_targets(socket)
      "files" -> assign_files(socket, query)
      "runs" -> assign_runs(socket)
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
    |> assign(:summary, Commits.summary(project.id, subject.sha))
    |> assign(:gates, Gates.settings(project))
    |> assign(:gate_verdict, if(project.coverage_gates_enabled, do: Gates.evaluate(project, comparison)))
  end

  defp assign_overview(%{assigns: %{comparison: comparison, subject: subject} = assigns} = socket) do
    socket
    |> assign(:scheme_rows, Enum.map(comparison.schemes, &Map.put(&1, :id, "scheme-" <> &1.scheme)))
    |> assign(:target_rises, movers(comparison.targets, :desc, "target-rise"))
    |> assign(:target_falls, movers(comparison.targets, :asc, "target-fall"))
    |> assign(:file_rises, movers(comparison.files, :desc, "file-rise"))
    |> assign(:file_falls, movers(comparison.files, :asc, "file-fall"))
    |> assign(:least_covered_files, least_covered_files(assigns.selected_project, subject.sha))
    |> assign(:unmeasured_files, unmeasured_files(assigns.selected_project, subject.sha, @highlight_size))
    |> assign(:patch_rows, patch_rows(comparison.patch))
    |> assign(:skipped_rows, skipped_rows(comparison.patch))
  end

  defp least_covered_files(project, sha) do
    {files, _count} = Commits.list_files(project.id, sha, 1, @highlight_size)
    Enum.map(files, &Map.put(&1, :id, "gap-" <> &1.path))
  end

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
    page =
      History.commit_page(
        project,
        subject.branch,
        Keyword.merge(period_opts(socket), page: Query.bounded_page(query["page"]), page_size: @page_size)
      )

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, %{current_page: page.page, total_pages: page.total_pages})
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  # The runs behind the subject: one commit's, or those of every commit the
  # page holds.
  defp assign_runs(%{assigns: %{selected_project: project}} = socket) do
    runs = Commits.runs(project.id, subject_shas(socket))

    assign(socket, :run_rows, runs |> Enum.reverse() |> Enum.map(&Map.put(&1, :id, &1.test_run_id)))
  end

  defp subject_shas(%{assigns: %{subject: %{kind: :commit, sha: sha}}}), do: [sha]

  defp subject_shas(%{assigns: %{subject: %{kind: :pull_request}, commits: commits}}),
    do: Enum.map(commits, & &1.git_commit_sha)

  defp subject_shas(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    project
    |> History.commit_page(subject.branch, Keyword.put(period_opts(socket), :page_size, 200))
    |> Map.fetch!(:commits)
    |> Enum.filter(& &1.measured)
    |> Enum.map(& &1.git_commit_sha)
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
    |> assign_unmeasured_page(project, subject.sha, query)
  end

  # The two lists page apart, each under its own parameter, so turning one
  # leaves the other where it was.
  defp assign_unmeasured_page(%{assigns: %{summary: summary}} = socket, project, sha, query) do
    count = (summary && summary.unmeasured_files_count) || 0
    total_pages = max(1, ceil(count / @page_size))
    page = min(Query.bounded_page(query["unmeasured-page"]), total_pages)

    socket
    |> assign(:unmeasured_files, unmeasured_files(project, sha, @page_size, (page - 1) * @page_size))
    |> assign(:unmeasured_meta, %{current_page: page, total_pages: total_pages})
  end

  defp unmeasured_files(project, sha, limit, offset \\ 0) do
    project
    |> Commits.unmeasured_files(sha, limit: limit, offset: offset)
    |> Enum.map(&%{id: "unmeasured-" <> &1, path: &1})
  end

  defp patch_rows(%{status: :available, files: files}), do: Enum.map(files, &Map.put(&1, :id, "patch-" <> &1.path))
  defp patch_rows(_patch), do: []

  defp skipped_rows(%{status: :available, skipped: skipped}),
    do: Enum.map(skipped, &Map.put(&1, :id, "skipped-" <> &1.path))

  defp skipped_rows(_patch), do: []

  defp period_opts(%{assigns: %{coverage_period: period}}), do: DatePicker.period_opts(period)

  @doc """
  What the Change widget says it measures against: the commit before it for
  the default branch, whose baseline is its own previous commit, and the
  baseline for a branch of its own, a pull request or a commit.
  """
  def change_description(%{kind: :branch, branch: branch}, %{default_branch: branch}, %{baseline: baseline})
      when not is_nil(baseline) do
    dgettext("dashboard_tests", "Against the previous commit: %{coverage}% at %{sha} on %{branch}.",
      coverage: baseline.coverage,
      sha: short_sha(baseline.commit),
      branch: baseline.branch
    )
  end

  def change_description(_subject, _project, %{baseline: baseline}) when not is_nil(baseline) do
    dgettext("dashboard_tests", "Against the baseline: %{coverage}% at %{sha} on %{branch}.",
      coverage: baseline.coverage,
      sha: short_sha(baseline.commit),
      branch: baseline.branch
    )
  end

  def change_description(%{kind: :branch, branch: branch}, %{default_branch: branch}, _comparison),
    do: dgettext("dashboard_tests", "Difference of the total against the previous commit.")

  def change_description(_subject, _project, _comparison),
    do: dgettext("dashboard_tests", "Difference of the total against the baseline commit.")

  @doc """
  Whether the head has a diff to be judged on. Changed files come from the
  diff against a base branch, which a pull request has and a push to a branch
  does not, so without one the page reads the commit as a whole instead of
  showing a patch nobody can compute.
  """
  def diff?(%{patch: %{status: :unavailable, reason: :no_history}}), do: false
  def diff?(_comparison), do: true

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
