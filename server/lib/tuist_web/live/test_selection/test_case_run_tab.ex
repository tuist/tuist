defmodule TuistWeb.TestSelection.TestCaseRunTab do
  @moduledoc """
  One test's part in the coverage selection of the test run it ran in, in
  the test case run's Selective Testing tab: why the selection kept it (the
  reason and the changed path that matched), the shard it was planned on, and the repository files the baseline's per-test evidence
  says it executed, the changed ones first, each with how it changed since
  the baseline. Its query parameters are prefixed with `selection-`.
  """
  use TuistWeb, :html
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.TestSelection.Components

  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Tests.Selections
  alias Tuist.Tests.TestImpact
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @page_size 20

  @doc """
  The selection run the test case run's test run came from and the test's
  row in it, or `nil` when there is none.
  """
  def load(project, account, %{test_run_id: test_run_id, test_case_id: test_case_id})
      when not is_nil(test_run_id) and not is_nil(test_case_id) do
    with true <- Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account),
         %{} = run <- Selections.run_for_test_run(project.id, test_run_id),
         {:ok, test} <- Selections.get_run_test(run, test_case_id) do
      %{run: run, test: test}
    else
      _ -> nil
    end
  end

  def load(_project, _account, _test_case_run), do: nil

  @doc """
  Loads the files the test executed in the baseline, once, and the page of
  them the query `params` ask for.
  """
  def assign_files(socket, %{run: run, test: test}, params) do
    socket =
      if socket.assigns[:selection_all_files],
        do: socket,
        else: Phoenix.Component.assign(socket, :selection_all_files, executed_files(run, test))

    files = socket.assigns.selection_all_files
    search = params["selection-search"] || ""

    filtered =
      if search == "",
        do: files,
        else: Enum.filter(files, &String.contains?(String.downcase(&1.path), String.downcase(search)))

    total_pages = max(div(length(filtered) + @page_size - 1, @page_size), 1)
    page = min(parse_page(params["selection-page"]), total_pages)

    Phoenix.Component.assign(socket,
      selection_files: Enum.slice(filtered, (page - 1) * @page_size, @page_size),
      selection_files_search: search,
      selection_files_page: page,
      selection_files_total_pages: total_pages
    )
  end

  defp executed_files(run, test) do
    covered = Selections.baseline_covered_paths(run.project_id, run.baseline_sha, test)

    covered =
      if test.matched_path == "" or test.matched_path in covered,
        do: covered,
        else: [test.matched_path | covered]

    changed =
      if run.baseline_sha == "",
        do: %{},
        else:
          Selections.impact_changed_files_by_path(
            %TestImpact{project_id: run.project_id, head_sha: run.git_commit_sha, baseline_sha: run.baseline_sha},
            covered
          )

    covered
    |> Enum.map(fn path ->
      case Map.get(changed, path) do
        nil -> %{path: path, changed: false, status: nil, kind: unchanged_kind(path)}
        file -> %{path: path, changed: true, status: file.status, kind: file.kind}
      end
    end)
    |> Enum.sort_by(&{not &1.changed, &1.path})
  end

  # An unchanged file has no changed-file row to read its kind from; evidence
  # only holds files a test executed, so it is test code or source.
  defp unchanged_kind("Tests/" <> _rest), do: "test"
  defp unchanged_kind(_path), do: "source"

  @doc "The query that searches the executed files for `search`."
  def search_query(uri, search), do: uri.query |> Query.put("selection-search", search) |> Query.drop("selection-page")

  attr :selection, :map, required: true
  attr :all_files, :list, required: true
  attr :files, :list, required: true
  attr :search, :string, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :uri, :any, required: true
  attr :project, :map, required: true
  attr :account, :map, required: true
  attr :test_run_id, :string, required: true

  def test_selection(assigns) do
    assigns = assign(assigns, run: assigns.selection.run, test: assigns.selection.test)

    ~H"""
    <div class="tuist-coverage-selection" data-part="test-selection">
      <.card
        title={dgettext("dashboard_tests", "Why it was selected")}
        icon="filter_question"
        data-part="selection-reason-card"
      >
        <:actions>
          <.button
            label={dgettext("dashboard_tests", "View selection")}
            variant="secondary"
            size="small"
            navigate={
              "/#{@account.name}/#{@project.name}/tests/test-runs/#{@test_run_id}?tab=test-optimizations"
            }
          />
        </:actions>
        <.card_section data-part="selection-verdict-section">
          <.alert
            id="test-selection-test-reason"
            type="secondary"
            status={if @test.decision == "selected", do: "information", else: "success"}
            size="large"
            title={"#{decision_label(@test.decision)}: #{reason_label(@test.reason)}"}
            description={reason_description(@test.reason, @test.matched_path)}
          />
        </.card_section>
        <.card_section data-part="selection-details-section">
          <dl data-part="details">
            <div>
              <dt>{dgettext("dashboard_tests", "Baseline")}</dt>
              <dd>
                <.link_button
                  :if={@run.baseline_sha != ""}
                  navigate={"/#{@account.name}/#{@project.name}/tests/coverage/commits/#{@run.baseline_sha}"}
                  label={short_sha(@run.baseline_sha)}
                  variant="secondary"
                  size="large"
                  underline
                />
                <span :if={@run.baseline_sha == ""}>{dgettext("dashboard_tests", "None")}</span>
              </dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Matched path")}</dt>
              <dd>{if @test.matched_path != "", do: @test.matched_path, else: "–"}</dd>
            </div>
            <div :if={@test.decision == "selected" and @run.shard_count > 1}>
              <dt>{dgettext("dashboard_tests", "Shard")}</dt>
              <dd>{format_number(@test.shard_index)}</dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Est. duration")}</dt>
              <dd>
                {DateFormatter.format_duration_from_milliseconds(@test.estimated_duration_ms)}
              </dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Changed files it executed")}</dt>
              <dd>
                {dgettext("dashboard_tests", "%{changed} of %{total}",
                  changed: Enum.count(@all_files, & &1.changed),
                  total: length(@all_files)
                )}
              </dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.card
        title={dgettext("dashboard_tests", "Files it executed in the baseline")}
        icon="file"
        data-part="selection-files-card"
      >
        <.card_section data-part="selection-table-section">
          <div data-part="filters">
            <.form
              for={%{}}
              id="search-selection-files-form"
              phx-change="search-selection-files"
              phx-debounce="200"
            >
              <.text_input
                type="search"
                id="search-selection-files"
                name="search"
                placeholder={dgettext("dashboard_tests", "Search by path...")}
                show_suffix={false}
                data-part="search"
                value={@search}
              />
            </.form>
          </div>
          <div :if={@files != []} data-part="selection-table">
            <.table id="selection-executed-files-table" rows={@files} row_key={& &1.path}>
              <:col :let={file} label={dgettext("dashboard_tests", "File")}>
                <.text_and_description_cell
                  label={Path.basename(file.path)}
                  description={parent_dir(file.path)}
                />
              </:col>
              <:col :let={file} label={dgettext("dashboard_tests", "Since the baseline")}>
                <.status_badge_cell
                  :if={file.changed}
                  status={file_status(file.status)}
                  label={file_status_label(file.status)}
                />
                <.status_badge_cell
                  :if={!file.changed}
                  status="disabled"
                  label={dgettext("dashboard_tests", "Unchanged")}
                />
              </:col>
              <:col :let={file} label={dgettext("dashboard_tests", "Kind")}>
                <.badge_cell
                  label={file_kind_label(file.kind)}
                  color={file_kind_color(file.kind)}
                  style="light-fill"
                />
              </:col>
            </.table>
            <.pagination_group
              :if={@total_pages > 1}
              current_page={@page}
              number_of_pages={@total_pages}
              page_patch={fn page -> "?#{Query.put(@uri.query, "selection-page", page)}" end}
            />
          </div>
          <.coverage_empty
            :if={@files == []}
            title={
              if @all_files == [],
                do: dgettext("dashboard_tests", "The baseline recorded no files for it"),
                else: dgettext("dashboard_tests", "No file matches")
            }
            image="table"
            data-part="empty-selection-files"
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
