defmodule TuistWeb.TestSelectionTestLive do
  @moduledoc """
  One test of a selection run: whether the run selected or skipped it and
  why (the reason and the changed path that matched), the shard it was
  planned on, its outcome in the test run that reported the results, and
  the repository files the baseline's per-test evidence says it executed,
  the changed ones first, each with how it changed since the baseline.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests.Selections
  alias Tuist.Tests.TestImpact
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(
        %{"selection_run_id" => run_id, "test_case_id" => test_case_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    with {:ok, run} <- Selections.get_run(project.id, run_id),
         {:ok, test} <- Selections.get_run_test(run, test_case_id) do
      covered = Selections.baseline_covered_paths(project.id, run.baseline_sha, test)

      covered =
        if test.matched_path == "" or test.matched_path in covered,
          do: covered,
          else: [test.matched_path | covered]

      changed =
        if run.baseline_sha == "",
          do: %{},
          else:
            Selections.impact_changed_files_by_path(
              %TestImpact{project_id: project.id, head_sha: run.git_commit_sha, baseline_sha: run.baseline_sha},
              covered
            )

      files =
        covered
        |> Enum.map(fn path ->
          case Map.get(changed, path) do
            nil -> %{path: path, changed: false, status: nil, kind: unchanged_kind(path)}
            file -> %{path: path, changed: true, status: file.status, kind: file.kind}
          end
        end)
        |> Enum.sort_by(&{not &1.changed, &1.path})

      {:ok,
       socket
       |> assign(
         :head_title,
         "#{test.name} · #{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist"
       )
       |> assign(OpenGraph.og_image_assigns("tests"))
       |> assign(:run, run)
       |> assign(:test, test)
       |> assign(:outcome, visible_outcome(test, run.mode))
       |> assign(:all_files, files)}
    else
      _ -> raise NotFoundError, dgettext("dashboard_tests", "This test isn't part of the selection run.")
    end
  end

  def handle_params(_params, uri, %{assigns: %{all_files: files}} = socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    search = params["files-search"] || ""

    filtered =
      if search == "",
        do: files,
        else: Enum.filter(files, &String.contains?(String.downcase(&1.path), String.downcase(search)))

    total_pages = max(div(length(filtered) + @page_size - 1, @page_size), 1)
    page = min(parse_page(params["page"]), total_pages)

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:files_search, search)
     |> assign(:files, Enum.slice(filtered, (page - 1) * @page_size, @page_size))
     |> assign(:files_page, page)
     |> assign(:files_total_pages, total_pages)}
  end

  def handle_event("search-files", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("files-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: "?" <> query, replace: true)}
  end

  # An unchanged file has no changed-file row to read its kind from; evidence
  # only holds files a test executed, so it is test code or source.
  defp unchanged_kind("Tests/" <> _rest), do: "test"
  defp unchanged_kind(_path), do: "source"

  @doc false
  def run_href(%{selected_account: account, selected_project: project, run: run}),
    do: "/#{account.name}/#{project.name}/tests/test-selection/runs/#{run.id}"

  @doc false
  def commit_href(%{selected_account: account, selected_project: project, run: run}),
    do: "/#{account.name}/#{project.name}/tests/test-selection/commits/#{run.git_commit_sha}"

  @doc false
  def coverage_href(%{selected_account: account, selected_project: project}, sha),
    do: "/#{account.name}/#{project.name}/tests/coverage/commits/#{sha}"

  @doc false
  def changed_count(%{all_files: files}), do: Enum.count(files, & &1.changed)

  @doc false
  def outcome_label("failure"), do: dgettext("dashboard_tests", "Failed")
  def outcome_label("success"), do: dgettext("dashboard_tests", "Passed")
  def outcome_label("skipped"), do: dgettext("dashboard_tests", "Skipped")
  def outcome_label(_outcome), do: dgettext("dashboard_tests", "No result")

  @doc false
  def format_duration(duration), do: Tuist.Utilities.DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
