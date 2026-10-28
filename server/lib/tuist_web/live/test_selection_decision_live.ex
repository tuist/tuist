defmodule TuistWeb.TestSelectionDecisionLive do
  @moduledoc """
  One decision of a commit's test selection plan: a test, or a test target
  when the plan decided per target. It shows where the test or target is
  declared, whether the plan selected or skipped it and why, the baseline
  run whose evidence the decision rests on, and the repository files that
  evidence says it executed, the changed ones first, each with how it
  changed since the baseline.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests
  alias Tuist.Tests.Selections
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(
        %{"git_commit_sha" => sha, "decision_id" => decision_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_tests", "Test selection is not enabled for this project.")
    end

    with {:ok, selection} <- Selections.get(project.id, sha),
         {:ok, decision} <- Selections.get_decision(selection, decision_id) do
      changed = Selections.changed_files_by_path(selection, decision.covered_paths)

      files =
        decision.covered_paths
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
         "#{decision_title(decision)} · #{dgettext("dashboard_tests", "Test Selection")} · #{account.name}/#{project.name} · Tuist"
       )
       |> assign(OpenGraph.og_image_assigns("tests"))
       |> assign(:selection, selection)
       |> assign(:decision, decision)
       |> assign(:test_case_exists?, test_case_exists?(decision))
       |> assign(:all_files, files)}
    else
      _ -> raise NotFoundError, dgettext("dashboard_tests", "This decision doesn't exist.")
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

  defp test_case_exists?(%{test_case_id: nil}), do: false

  defp test_case_exists?(%{test_case_id: id}) do
    match?({:ok, _}, Tests.get_test_case_by_id(id))
  end

  @doc false
  def commit_href(%{selected_account: account, selected_project: project, selection: selection}),
    do: "/#{account.name}/#{project.name}/tests/test-selection/commits/#{selection.git_commit_sha}"

  @doc false
  def changed_count(%{all_files: files}), do: Enum.count(files, & &1.changed)

  @doc false
  def format_duration(duration), do: Tuist.Utilities.DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
