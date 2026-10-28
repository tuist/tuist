defmodule TuistWeb.TestSelectionLive do
  @moduledoc """
  A commit's test selection plan (`Tuist.Tests.Selections`), on three tabs:

  - Overview: what the plan decided (selected, skipped, the skip rate and the
    time the skipped tests took in the baseline), why (decisions per
    reason), and every decision, per test or per test target as the plan
    was made, searched by name, filtered by decision and scheme, sorted and
    paged in ClickHouse; each opens its own page
    (`TuistWeb.TestSelectionDecisionLive`). The header links to the commit's
    Code Coverage page when one of its runs reported coverage, and to the
    baseline's.
  - Modified files: the files that changed between the baseline and the
    commit, what kind of file each is and how many decisions it selected.
  - Test runs: the commit's runs, newest first.
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

  @tabs ~w(overview files runs)
  @sort_fields ~w(decision name duration)

  def mount(
        %{"git_commit_sha" => sha},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    selection =
      case Selections.get(project.id, sha) do
        {:ok, selection} ->
          selection

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_tests", "This commit has no test selection plan.")
      end

    [summary, coverage?, baseline_coverage?, runs] =
      Tuist.Tasks.parallel_tasks([
        fn -> Selections.summary(selection) end,
        fn -> Selections.coverage?(project.id, sha) end,
        fn -> Selections.coverage?(project.id, selection.baseline_commit_sha) end,
        fn -> Selections.test_runs(project.id, sha) end
      ])

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{short_sha(sha)} · #{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(OpenGraph.og_image_assigns("tests"))
     |> assign(:selection, selection)
     |> assign(:summary, summary)
     |> assign(:coverage?, coverage?)
     |> assign(:baseline_coverage?, baseline_coverage?)
     |> assign(:test_runs, runs)}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    tab = if params["tab"] in @tabs, do: params["tab"], else: "overview"

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:tab, tab)
     |> assign_tab(tab, params)}
  end

  defp assign_tab(%{assigns: %{selection: selection}} = socket, "overview", params) do
    search = params["decisions-search"] || ""
    decision = if params["decision"] in ["selected", "skipped"], do: params["decision"], else: "any"
    scheme = if params["scheme"] in socket.assigns.summary.schemes, do: params["scheme"], else: "any"
    sort_by = if params["decisions-sort-by"] in @sort_fields, do: params["decisions-sort-by"], else: "decision"
    sort_order = if params["decisions-sort-order"] == "desc", do: "desc", else: "asc"

    {rows, meta} =
      Selections.decisions(selection,
        search: search,
        decision: decision,
        scheme: scheme,
        sort_by: sort_by,
        sort_order: sort_order,
        page: parse_page(params["page"])
      )

    socket
    |> assign(:decisions_search, search)
    |> assign(:decision_filter, decision)
    |> assign(:scheme_filter, scheme)
    |> assign(:decisions_sort_by, sort_by)
    |> assign(:decisions_sort_order, sort_order)
    |> assign(:decisions, rows)
    |> assign(:decisions_meta, meta)
  end

  defp assign_tab(%{assigns: %{selection: selection}} = socket, "files", params) do
    search = params["files-search"] || ""
    kind = if params["kind"] in ~w(source test resource tracked ignored), do: params["kind"], else: "any"
    {rows, meta} = Selections.changed_files(selection, search: search, kind: kind, page: parse_page(params["page"]))

    socket
    |> assign(:files_search, search)
    |> assign(:kind_filter, kind)
    |> assign(:files, rows)
    |> assign(:files_meta, meta)
  end

  defp assign_tab(socket, "runs", _params), do: socket

  def handle_event("search-decisions", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("decisions-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  def handle_event("search-files", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("files-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  @doc false
  def tab_label("overview", _assigns), do: dgettext("dashboard_tests", "Overview")

  def tab_label("files", %{selection: selection}),
    do: dgettext("dashboard_tests", "Modified files (%{count})", count: selection.changed_files_count)

  def tab_label("runs", %{test_runs: runs}), do: dgettext("dashboard_tests", "Test runs (%{count})", count: length(runs))

  def tabs, do: @tabs

  @doc false
  def decision_href(%{selected_account: account, selected_project: project, selection: selection}, decision),
    do:
      "/#{account.name}/#{project.name}/tests/test-selection/commits/#{selection.git_commit_sha}/decisions/#{decision.id}"

  @doc false
  def coverage_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/coverage/commits/#{sha}"

  @doc false
  def column_sort_patch(assigns, column) do
    order =
      cond do
        assigns.decisions_sort_by != column -> if column == "duration", do: "desc", else: "asc"
        assigns.decisions_sort_order == "asc" -> "desc"
        true -> "asc"
      end

    "?#{assigns.uri.query |> Query.put("decisions-sort-by", column) |> Query.put("decisions-sort-order", order) |> Query.drop("page")}"
  end

  @doc false
  def decisions_title(%{scope: "target"}), do: dgettext("dashboard_tests", "Test targets")
  def decisions_title(_selection), do: dgettext("dashboard_tests", "Tests")

  @doc false
  def decision_filter_label("selected"), do: dgettext("dashboard_tests", "Selected")
  def decision_filter_label("skipped"), do: dgettext("dashboard_tests", "Skipped")
  def decision_filter_label(_decision), do: dgettext("dashboard_tests", "Any")

  @doc false
  def kind_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  def kind_filter_label(kind), do: file_kind_label(kind)

  @doc false
  def format_duration(duration), do: Tuist.Utilities.DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
