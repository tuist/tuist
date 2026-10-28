defmodule TuistWeb.TestSelectionCommitLive do
  @moduledoc """
  A commit's test selection: its test impact against a baseline (picked
  with `?baseline=`, the newest by default, when its runs used more than
  one) and the selection runs that applied it, on three tabs:

  - Selection runs: every invocation on the commit, each opening its page
    (`TuistWeb.TestSelectionRunLive`).
  - Changed files: what changed between the baseline and the commit, what
    kind of file each is and how many tests it reaches.
  - Affected tests: the tests the change reaches whatever the invocation,
    with the reason and the changed path that matched.

  The header links to the commit's Code Coverage page when one of its runs
  reported coverage, and the impact card to the baseline's.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests.Selections
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(runs files tests)
  @impact_reasons ~w(impacted target_changed failed_at_baseline)

  def mount(
        %{"git_commit_sha" => sha},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    [runs, impacts, coverage?] =
      Tuist.Tasks.parallel_tasks([
        fn -> Selections.runs_for_commit(project.id, sha) end,
        fn -> Selections.impacts_for_commit(project.id, sha) end,
        fn -> Selections.coverage?(project.id, sha) end
      ])

    if runs == [] and impacts == [] do
      raise NotFoundError, dgettext("dashboard_tests", "This commit has no test selection.")
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{short_sha(sha)} · #{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(OpenGraph.og_image_assigns("tests"))
     |> assign(:sha, sha)
     |> assign(:branch, Enum.find_value(runs ++ impacts, & &1.git_branch))
     |> assign(:runs, runs)
     |> assign(:impacts, impacts)
     |> assign(:coverage?, coverage?)}
  end

  def handle_params(_params, uri, %{assigns: %{impacts: impacts}} = socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    tab = if params["tab"] in @tabs, do: params["tab"], else: "runs"
    impact = Enum.find(impacts, &(&1.baseline_sha == params["baseline"])) || List.first(impacts)

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:tab, tab)
     |> assign(:impact, impact)
     |> assign(:impact_reasons, if(impact, do: Selections.impact_reasons(impact), else: %{}))
     |> assign(:baseline_coverage?, impact && Selections.coverage?(impact.project_id, impact.baseline_sha))
     |> assign_tab(tab, impact, params)}
  end

  defp assign_tab(socket, "files", impact, params) do
    search = params["files-search"] || ""
    kind = if params["kind"] in ~w(source test resource tracked ignored), do: params["kind"], else: "any"

    {rows, meta} =
      if impact,
        do: Selections.impact_changed_files(impact, search: search, kind: kind, page: parse_page(params["page"])),
        else: {[], %{current_page: 1, total_pages: 1, total_count: 0}}

    socket
    |> assign(:files_search, search)
    |> assign(:kind_filter, kind)
    |> assign(:files, rows)
    |> assign(:files_meta, meta)
  end

  defp assign_tab(socket, "tests", impact, params) do
    search = params["tests-search"] || ""
    reason = if params["reason"] in @impact_reasons, do: params["reason"], else: "any"

    {rows, meta} =
      if impact,
        do: Selections.impact_tests(impact, search: search, reason: reason, page: parse_page(params["page"])),
        else: {[], %{current_page: 1, total_pages: 1, total_count: 0}}

    socket
    |> assign(:tests_search, search)
    |> assign(:reason_filter, reason)
    |> assign(:tests, rows)
    |> assign(:tests_meta, meta)
  end

  defp assign_tab(socket, "runs", _impact, _params), do: socket

  def handle_event("search-files", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("files-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  def handle_event("search-tests", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("tests-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  def tabs, do: @tabs

  def impact_reasons, do: @impact_reasons

  @doc false
  def tab_label("runs", %{runs: runs}), do: dgettext("dashboard_tests", "Selection runs (%{count})", count: length(runs))

  def tab_label("files", %{impact: impact}),
    do: dgettext("dashboard_tests", "Changed files (%{count})", count: (impact && impact.changed_files_count) || 0)

  def tab_label("tests", %{impact: impact}),
    do: dgettext("dashboard_tests", "Affected tests (%{count})", count: (impact && impact.impacted_tests_count) || 0)

  @doc false
  def run_href(%{selected_account: account, selected_project: project}, run),
    do: "/#{account.name}/#{project.name}/tests/test-selection/runs/#{run.id}"

  @doc false
  def coverage_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/coverage/commits/#{sha}"

  @doc false
  def test_case_href(%{selected_account: account, selected_project: project}, test),
    do: "/#{account.name}/#{project.name}/tests/test-cases/#{test.test_case_id}"

  @doc false
  def kind_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  def kind_filter_label(kind), do: file_kind_label(kind)

  @doc false
  def reason_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  def reason_filter_label(reason), do: reason_label(reason)

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
