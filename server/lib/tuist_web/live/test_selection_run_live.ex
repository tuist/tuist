defmodule TuistWeb.TestSelectionRunLive do
  @moduledoc """
  One selection run: the invocation (scheme or test plan, destination,
  shards, CI job), the impact it applied and its counts, why it fell back to
  running everything when it did, and the tests per reason; then three tabs:

  - Tests: every requested test with its decision, reason, shard, estimated
    duration and outcome in the test run that reported the results, the
    dry-run misses and the selected tests that never reported flagged; each
    opens its page (`TuistWeb.TestSelectionTestLive`).
  - Targets: the requested tests per test target.
  - Shards: per shard, what was planned and what ran.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests.Selections
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(tests targets shards)
  @sort_fields ~w(decision name shard duration)

  def mount(
        %{"selection_run_id" => id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    run =
      case Selections.get_run(project.id, id) do
        {:ok, run} -> run
        {:error, :not_found} -> raise NotFoundError, dgettext("dashboard_tests", "This selection run doesn't exist.")
      end

    [summary, baseline_coverage?] =
      Tuist.Tasks.parallel_tasks([
        fn -> Selections.run_summary(run) end,
        fn -> Selections.coverage?(project.id, run.baseline_sha) end
      ])

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{run_title(run)} · #{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(OpenGraph.og_image_assigns("tests"))
     |> assign(:run, run)
     |> assign(:summary, summary)
     |> assign(:baseline_coverage?, baseline_coverage?)}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    tab = if params["tab"] in @tabs, do: params["tab"], else: "tests"

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:tab, tab)
     |> assign_tab(tab, params)}
  end

  defp assign_tab(%{assigns: %{run: run}} = socket, "tests", params) do
    search = params["tests-search"] || ""
    decision = if params["decision"] in ["selected", "skipped"], do: params["decision"], else: "any"
    flag = if params["flag"] in ["missed", "not_run"], do: params["flag"], else: "any"
    shard = parse_shard(params["shard"], run.shard_count)
    sort_by = if params["tests-sort-by"] in @sort_fields, do: params["tests-sort-by"], else: "decision"
    sort_order = if params["tests-sort-order"] == "desc", do: "desc", else: "asc"

    {rows, meta} =
      Selections.run_tests(run,
        search: search,
        decision: decision,
        flag: flag,
        shard: shard,
        sort_by: sort_by,
        sort_order: sort_order,
        page: parse_page(params["page"])
      )

    socket
    |> assign(:tests_search, search)
    |> assign(:decision_filter, decision)
    |> assign(:flag_filter, flag)
    |> assign(:shard_filter, shard)
    |> assign(:tests_sort_by, sort_by)
    |> assign(:tests_sort_order, sort_order)
    |> assign(:tests, rows)
    |> assign(:tests_meta, meta)
  end

  defp assign_tab(%{assigns: %{run: run}} = socket, "targets", _params),
    do: assign(socket, :targets, Selections.run_targets(run))

  defp assign_tab(%{assigns: %{run: run}} = socket, "shards", _params),
    do: assign(socket, :shards, Selections.run_shards(run))

  def handle_event("search-tests", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("tests-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  def tabs, do: @tabs

  @doc false
  def tab_label("tests", %{run: run}), do: dgettext("dashboard_tests", "Tests (%{count})", count: run.requested_count)

  def tab_label("targets", %{run: run}),
    do: dgettext("dashboard_tests", "Targets (%{count})", count: length(run.requested_targets))

  def tab_label("shards", %{run: run}), do: dgettext("dashboard_tests", "Shards (%{count})", count: run.shard_count)

  @doc false
  def run_title(%{test_plan: plan}) when plan != "", do: plan
  def run_title(%{scheme: scheme}), do: scheme

  @doc false
  def commit_href(%{selected_account: account, selected_project: project, run: run}),
    do: "/#{account.name}/#{project.name}/tests/test-selection/commits/#{run.git_commit_sha}"

  @doc false
  def coverage_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/coverage/commits/#{sha}"

  @doc false
  def test_run_href(%{selected_account: account, selected_project: project, run: run}),
    do: "/#{account.name}/#{project.name}/tests/test-runs/#{run.test_run_id}"

  @doc false
  def test_href(%{selected_account: account, selected_project: project, run: run}, test),
    do: "/#{account.name}/#{project.name}/tests/test-selection/runs/#{run.id}/tests/#{test.test_case_id}"

  @doc false
  def shard_patch(%{uri: uri}, shard_index),
    do:
      "?#{uri.query |> Query.put("tab", "tests") |> Query.put("decision", "selected") |> Query.put("shard", shard_index) |> Query.drop("page")}"

  @doc false
  def column_sort_patch(assigns, column) do
    order =
      cond do
        assigns.tests_sort_by != column -> if column == "duration", do: "desc", else: "asc"
        assigns.tests_sort_order == "asc" -> "desc"
        true -> "asc"
      end

    "?#{assigns.uri.query |> Query.put("tests-sort-by", column) |> Query.put("tests-sort-order", order) |> Query.drop("page")}"
  end

  @doc false
  def decision_filter_label("selected"), do: dgettext("dashboard_tests", "Selected")
  def decision_filter_label("skipped"), do: dgettext("dashboard_tests", "Skipped")
  def decision_filter_label(_decision), do: dgettext("dashboard_tests", "Any")

  @doc false
  def flag_filter_label("missed"), do: dgettext("dashboard_tests", "Misses")
  def flag_filter_label("not_run"), do: dgettext("dashboard_tests", "Planned, not run")
  def flag_filter_label(_flag), do: dgettext("dashboard_tests", "Any")

  @doc false
  def shard_filter_label(nil), do: dgettext("dashboard_tests", "Any")
  def shard_filter_label(index), do: dgettext("dashboard_tests", "Shard %{index}", index: index)

  @doc false
  def format_duration(duration), do: Tuist.Utilities.DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_shard(value, shard_count) do
    case Integer.parse(value || "") do
      {index, ""} when index >= 0 and index < shard_count -> index
      _ -> nil
    end
  end

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
