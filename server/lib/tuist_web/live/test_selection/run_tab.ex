defmodule TuistWeb.TestSelection.RunTab do
  @moduledoc """
  The impact run a test run points to, in the test run's Selective Testing
  tab: the outcome, the counts and the baseline; then these
  tabs:

  - Tests: every requested test with its decision, the rule that decided it,
    the shard and the estimated duration; each opens its test case run's
    Selective Testing tab (`TuistWeb.TestSelection.TestCaseRunTab`).
    Skipped tests, by coverage or in a module skipped by hash, are derived
    from the baseline run.
  - Modules: the tests per module. The test run page fills it with its
    module-level selective testing table instead when it has one.
  - Changed files: what changed since the baseline, whether each file is
    tracked and how many tests it selected.
  - Shards, for a run a shard plan distributed: per shard, what was planned
    and what ran.
  - Debug: the trace of the rules that decided it and the tracked files.

  A fallback shows the outcome and the Debug tab only.

  Its query parameters are prefixed with `selection-` so they don't clash
  with the test run page's own.
  """
  use TuistWeb, :html
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.TestSelection.Components

  alias Tuist.Tests.Selections
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @tabs ~w(tests modules files shards debug)
  @sort_fields ~w(decision name shard duration)

  @doc "What the tab shows before its data is loaded."
  def assign_defaults(socket) do
    Phoenix.Component.assign(socket,
      selection_summary: nil,
      selection_diff: nil,
      selection_plan: nil,
      selection_baseline_coverage?: false,
      selection_tab: "tests",
      selection_filters: %{},
      selection_tests: [],
      selection_tests_meta: %{},
      selection_files: [],
      selection_files_meta: %{},
      selection_targets: [],
      selection_shards: []
    )
  end

  @doc """
  Loads what the tab shows for `selection_run`, the impact run the test run
  `test_run_id` points to, from the page's query `params`. The run's
  summary, diff and shard plan are loaded once and kept.
  """
  def assign_data(socket, selection_run, test_run_id, params) do
    socket =
      if socket.assigns.selection_summary do
        socket
      else
        [summary, diff, plan, baseline_coverage?] =
          Tuist.Tasks.parallel_tasks([
            fn -> Selections.run_summary(selection_run, test_run_id) end,
            fn -> Selections.get_diff(selection_run) end,
            fn -> Selections.shard_plan(selection_run) end,
            fn -> Selections.coverage?(selection_run.project_id, selection_run.baseline_sha) end
          ])

        Phoenix.Component.assign(socket,
          selection_summary: summary,
          selection_diff: diff,
          selection_plan: plan,
          selection_baseline_coverage?: baseline_coverage?
        )
      end

    tabs = tabs(selection_run, socket.assigns.selection_plan)
    tab = if params["selection-tab"] in tabs, do: params["selection-tab"], else: hd(tabs)

    socket
    |> Phoenix.Component.assign(:selection_tab, tab)
    |> assign_tab(tab, selection_run, test_run_id, params)
  end

  defp assign_tab(socket, "tests", run, test_run_id, params) do
    search = params["selection-search"] || ""
    decision = if params["selection-decision"] in ~w(selected skipped), do: params["selection-decision"], else: "any"
    reason = if params["selection-reason"] in reasons(), do: params["selection-reason"], else: "any"
    flag = if params["selection-flag"] in ~w(not_run), do: params["selection-flag"], else: "any"
    shard = parse_shard(params["selection-shard"], socket.assigns.selection_plan)
    sort_by = if params["selection-sort-by"] in @sort_fields, do: params["selection-sort-by"], else: "decision"
    sort_order = if params["selection-sort-order"] == "desc", do: "desc", else: "asc"

    {rows, meta} =
      Selections.run_tests(run, test_run_id,
        search: search,
        decision: decision,
        reason: reason,
        flag: flag,
        shard: shard,
        sort_by: sort_by,
        sort_order: sort_order,
        page: parse_page(params["selection-page"])
      )

    Phoenix.Component.assign(socket,
      selection_tests: rows,
      selection_tests_meta: meta,
      selection_filters: %{
        search: search,
        decision: decision,
        reason: reason,
        flag: flag,
        shard: shard,
        sort_by: sort_by,
        sort_order: sort_order
      }
    )
  end

  defp assign_tab(socket, "files", run, _test_run_id, params) do
    search = params["selection-search"] || ""
    tracked = if params["selection-tracked"] == "true", do: "true", else: "any"

    {rows, meta} =
      case socket.assigns.selection_diff do
        nil ->
          {[], %{current_page: 1, total_pages: 1, total_count: 0}}

        diff ->
          Selections.changed_files(socket.assigns.selected_project, run, diff,
            search: search,
            tracked: tracked == "true",
            page: parse_page(params["selection-page"])
          )
      end

    Phoenix.Component.assign(socket,
      selection_files: rows,
      selection_files_meta: meta,
      selection_filters: %{search: search, tracked: tracked}
    )
  end

  defp assign_tab(socket, "modules", run, _test_run_id, _params),
    do: Phoenix.Component.assign(socket, :selection_targets, Selections.run_targets(run))

  defp assign_tab(socket, "shards", run, test_run_id, _params),
    do:
      Phoenix.Component.assign(
        socket,
        :selection_shards,
        Selections.run_shards(run, socket.assigns.selection_plan, test_run_id)
      )

  defp assign_tab(socket, "debug", _run, _test_run_id, _params), do: socket

  @doc "The query that searches the current tab for `search`."
  def search_query(uri, search), do: uri.query |> Query.put("selection-search", search) |> Query.drop("selection-page")

  defp tabs(%{outcome: "fallback"}, _plan), do: ["debug"]
  defp tabs(_run, nil), do: List.delete(@tabs, "shards")
  defp tabs(_run, _plan), do: @tabs

  attr :selection_run, :map, required: true
  attr :summary, :map, required: true
  attr :diff, :any, required: true
  attr :plan, :any, required: true
  attr :baseline_coverage?, :boolean, required: true
  attr :tab, :string, required: true
  attr :uri, :any, required: true
  attr :project, :map, required: true
  attr :account, :map, required: true
  attr :filters, :map, default: %{}
  attr :tests, :list, default: []
  attr :tests_meta, :map, default: %{}
  attr :files, :list, default: []
  attr :files_meta, :map, default: %{}
  attr :targets, :list, default: []
  attr :shards, :list, default: []
  attr :modules_count, :integer, default: nil

  slot :modules,
    doc: "Replaces the Modules tab's table, for a test run with module-level selective testing data."

  def coverage_selection(assigns) do
    ~H"""
    <div class="tuist-coverage-selection" data-part="coverage-selection">
      <.card
        title={dgettext("dashboard_tests", "Coverage selection")}
        icon="filter"
        data-part="selection-summary-card"
      >
        <.card_section
          :if={Selections.fallback?(@selection_run)}
          data-part="selection-verdict-section"
        >
          <.alert
            id="test-selection-fallback"
            type="secondary"
            status="warning"
            size="large"
            title={
              dgettext("dashboard_tests", "Fell back to default selective testing: %{reason}",
                reason: fallback_label(@selection_run.reason)
              )
            }
            description={
              Enum.join(
                Enum.reject(
                  [fallback_description(@selection_run.reason), @selection_run.matched_path],
                  &(&1 == "")
                ),
                " "
              )
            }
          />
        </.card_section>
        <.card_section
          :if={!Selections.fallback?(@selection_run)}
          data-part="selection-widgets-section"
        >
          <div data-part="widgets">
            <.widget
              id="widget-selection-selected"
              title={dgettext("dashboard_tests", "Selected tests")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Tests the selection kept, out of all requested, including those in skipped modules."
                )
              }
              value={"#{format_number(@summary.selected)} / #{format_number(@summary.requested)}"}
            />
            <.widget
              id="widget-selection-skipped"
              title={dgettext("dashboard_tests", "Skipped tests")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Tests skipped out of all requested: those in skipped modules and those the changes since the baseline don't reach."
                )
              }
              value={"#{format_number(@summary.skipped)} / #{format_number(@summary.requested)}"}
            />
            <.widget
              id="widget-selection-skip-rate"
              title={dgettext("dashboard_tests", "Skip rate")}
              description={
                dgettext("dashboard_tests", "The share of requested tests that were skipped.")
              }
              value={"#{@summary.skip_rate}%"}
            />
            <.widget
              id="widget-selection-skipped-modules"
              title={dgettext("dashboard_tests", "Skipped modules")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Test modules selective testing found unchanged and skipped whole, out of all requested modules."
                )
              }
              value={"#{format_number(@summary.skipped_modules)} / #{format_number(@summary.modules)}"}
            />
            <.widget
              id="widget-selection-not-affected"
              title={dgettext("dashboard_tests", "Not affected")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Tests in the remaining modules skipped because the changes since the baseline don't reach them."
                )
              }
              value={format_number(@summary.unaffected)}
            />
            <.widget
              id="widget-selection-time-saved"
              title={dgettext("dashboard_tests", "Est. time saved")}
              description={
                dgettext(
                  "dashboard_tests",
                  "The skipped tests' durations in the baseline run, one after another."
                )
              }
              value={format_duration(@summary.skipped_duration)}
            />
            <.widget
              id="widget-selection-not-run"
              title={dgettext("dashboard_tests", "Planned, not run")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Selected tests the test run reported no result for: removed or renamed since the baseline, or lost with a shard."
                )
              }
              value={if @summary.reported, do: format_number(@summary.not_run), else: "–"}
            />
          </div>
        </.card_section>
        <.card_section data-part="selection-details-section">
          <dl data-part="details">
            <div>
              <dt>{dgettext("dashboard_tests", "Baseline")}</dt>
              <dd>
                <.link_button
                  :if={has_baseline?(@selection_run) and @baseline_coverage?}
                  navigate={
                    "/#{@account.name}/#{@project.name}/tests/coverage/commits/#{@selection_run.baseline_sha}"
                  }
                  label={short_sha(@selection_run.baseline_sha)}
                  variant="secondary"
                  size="large"
                  underline
                />
                <span :if={has_baseline?(@selection_run) and !@baseline_coverage?}>
                  {short_sha(@selection_run.baseline_sha)}
                </span>
                <span :if={!has_baseline?(@selection_run)}>
                  {dgettext("dashboard_tests", "None")}
                </span>
              </dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.tab_menu_horizontal :if={!Selections.fallback?(@selection_run)}>
        <.tab_menu_horizontal_item
          :for={tab <- tabs(@selection_run, @plan)}
          selected={@tab == tab}
          label={tab_label(tab, assigns)}
          patch={"?#{@uri.query |> Query.put("selection-tab", tab) |> drop_tab_params()}"}
          replace={true}
        />
      </.tab_menu_horizontal>

      {tab_card(assigns)}
    </div>
    """
  end

  @doc "What the Selective Testing tab shows when the test run's impact run expired."
  def expired_selection(assigns) do
    ~H"""
    <.alert
      id="test-selection-expired"
      type="secondary"
      status="information"
      size="large"
      title={dgettext("dashboard_tests", "The coverage selection's details expired")}
      description={
        dgettext(
          "dashboard_tests",
          "This test run used coverage-based test selection, but its impact run is past retention."
        )
      }
    />
    """
  end

  defp tab_card(%{tab: "tests"} = assigns), do: tests_card(assigns)
  defp tab_card(%{tab: "files"} = assigns), do: files_card(assigns)
  defp tab_card(%{tab: "modules", modules: [_ | _]} = assigns), do: ~H"{render_slot(@modules)}"
  defp tab_card(%{tab: "modules"} = assigns), do: modules_card(assigns)
  defp tab_card(%{tab: "shards"} = assigns), do: shards_card(assigns)
  defp tab_card(%{tab: "debug"} = assigns), do: debug_card(assigns)

  defp tests_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Tests")}
      icon="subtask"
      data-part="selection-tests-card"
    >
      <.card_section data-part="selection-table-section">
        <div data-part="filters">
          <.form
            for={%{}}
            id="search-selection-tests-form"
            phx-change="search-selection"
            phx-debounce="200"
          >
            <.text_input
              type="search"
              id="search-selection-tests"
              name="search"
              placeholder={dgettext("dashboard_tests", "Search...")}
              show_suffix={false}
              data-part="search"
              value={@filters.search}
            />
          </.form>
          <.dropdown
            id="selection-decision-dropdown"
            label={decision_filter_label(@filters.decision)}
            secondary_text={dgettext("dashboard_tests", "Decision:")}
          >
            <.dropdown_item
              :for={decision <- ~w(any selected skipped)}
              value={decision}
              label={decision_filter_label(decision)}
              patch={filter_patch(@uri, "selection-decision", decision)}
              data-selected={@filters.decision == decision}
            >
              <:right_icon :if={@filters.decision == decision}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            id="selection-reason-dropdown"
            label={reason_filter_label(@filters.reason)}
            secondary_text={dgettext("dashboard_tests", "Reason:")}
          >
            <.dropdown_item
              :for={reason <- ["any" | reasons()]}
              value={reason}
              label={reason_filter_label(reason)}
              patch={filter_patch(@uri, "selection-reason", reason)}
              data-selected={@filters.reason == reason}
            >
              <:right_icon :if={@filters.reason == reason}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            :if={@summary.reported}
            id="selection-flag-dropdown"
            label={flag_filter_label(@filters.flag)}
            secondary_text={dgettext("dashboard_tests", "Flag:")}
          >
            <.dropdown_item
              :for={flag <- ~w(any not_run)}
              value={flag}
              label={flag_filter_label(flag)}
              patch={filter_patch(@uri, "selection-flag", flag)}
              data-selected={@filters.flag == flag}
            >
              <:right_icon :if={@filters.flag == flag}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            :if={@plan}
            id="selection-shard-dropdown"
            label={shard_filter_label(@filters.shard)}
            secondary_text={dgettext("dashboard_tests", "Shard:")}
          >
            <.dropdown_item
              value="any"
              label={shard_filter_label(nil)}
              patch={"?#{@uri.query |> Query.drop("selection-shard") |> Query.drop("selection-page")}"}
              data-selected={is_nil(@filters.shard)}
            >
              <:right_icon :if={is_nil(@filters.shard)}><.check /></:right_icon>
            </.dropdown_item>
            <.dropdown_item
              :for={index <- 0..(@plan.shard_count - 1)//1}
              value={to_string(index)}
              label={shard_filter_label(index)}
              patch={filter_patch(@uri, "selection-shard", index)}
              data-selected={@filters.shard == index}
            >
              <:right_icon :if={@filters.shard == index}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>

        <div :if={@tests != []} data-part="selection-table">
          <.table
            id="selection-tests-table"
            rows={@tests}
            row_key={& &1.test_case_id}
            row_navigate={&test_href(@account, @project, &1)}
          >
            <:col
              :let={test}
              label={dgettext("dashboard_tests", "Test")}
              patch={column_sort_patch(@uri, @filters, "name")}
              sort_order={@filters.sort_by == "name" && @filters.sort_order}
            >
              <.text_and_description_cell label={test.name} description={test_location(test)} />
            </:col>
            <:col
              :let={test}
              label={dgettext("dashboard_tests", "Decision")}
              patch={column_sort_patch(@uri, @filters, "decision")}
              sort_order={@filters.sort_by == "decision" && @filters.sort_order}
            >
              <.decision_cell decision={test.decision} />
            </:col>
            <:col :let={test} label={dgettext("dashboard_tests", "Reason")}>
              <.text_and_description_cell
                label={reason_label(test.reason)}
                description={if test.matched_path != "", do: Path.basename(test.matched_path)}
              />
            </:col>
            <:col
              :let={test}
              :if={@plan}
              label={dgettext("dashboard_tests", "Shard")}
              patch={column_sort_patch(@uri, @filters, "shard")}
              sort_order={@filters.sort_by == "shard" && @filters.sort_order}
            >
              <.text_cell label={
                if is_nil(test.shard_index), do: "–", else: format_number(test.shard_index)
              } />
            </:col>
            <:col
              :let={test}
              label={dgettext("dashboard_tests", "Est. duration")}
              patch={column_sort_patch(@uri, @filters, "duration")}
              sort_order={@filters.sort_by == "duration" && @filters.sort_order}
            >
              <.text_cell label={format_duration(test.duration)} icon="history" />
            </:col>
          </.table>
          <.pagination_group
            :if={@tests_meta.total_pages > 1}
            current_page={@tests_meta.current_page}
            number_of_pages={@tests_meta.total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "selection-page", page)}" end}
          />
        </div>

        <.coverage_empty
          :if={@tests == []}
          title={dgettext("dashboard_tests", "No test matches")}
          image="table"
          data-part="empty-selection-tests"
        />
      </.card_section>
    </.card>
    """
  end

  defp files_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Changed files")}
      icon="file"
      data-part="selection-files-card"
    >
      <.card_section data-part="selection-table-section">
        <div data-part="filters">
          <.form
            for={%{}}
            id="search-selection-files-form"
            phx-change="search-selection"
            phx-debounce="200"
          >
            <.text_input
              type="search"
              id="search-selection-files"
              name="search"
              placeholder={dgettext("dashboard_tests", "Search by path...")}
              show_suffix={false}
              data-part="search"
              value={@filters.search}
            />
          </.form>
          <.dropdown
            id="selection-tracked-dropdown"
            label={tracked_filter_label(@filters.tracked)}
            secondary_text={dgettext("dashboard_tests", "Files:")}
          >
            <.dropdown_item
              :for={tracked <- ~w(any true)}
              value={tracked}
              label={tracked_filter_label(tracked)}
              patch={filter_patch(@uri, "selection-tracked", tracked)}
              data-selected={@filters.tracked == tracked}
            >
              <:right_icon :if={@filters.tracked == tracked}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>

        <.alert
          :if={@diff && @diff.changed_files_count > length(@diff.changed_files)}
          id="selection-files-capped"
          type="secondary"
          status="information"
          size="small"
          title={
            dgettext("dashboard_tests", "Showing the first %{shown} of %{total} changed files",
              shown: format_number(length(@diff.changed_files)),
              total: format_number(@diff.changed_files_count)
            )
          }
        />

        <div :if={@files != []} data-part="selection-table">
          <.table id="selection-files-table" rows={@files} row_key={& &1.path}>
            <:col :let={file} label={dgettext("dashboard_tests", "File")}>
              <.text_and_description_cell
                label={Path.basename(file.path)}
                description={parent_dir(file.path)}
              />
            </:col>
            <:col :let={file} label={dgettext("dashboard_tests", "Change")}>
              <.status_badge_cell
                status={file_status(file.status)}
                label={file_status_label(file.status)}
              />
            </:col>
            <:col :let={file} label={dgettext("dashboard_tests", "Tracked")}>
              <.badge_cell
                :if={file.tracked}
                label={dgettext("dashboard_tests", "Tracked")}
                color="warning"
                style="light-fill"
              />
              <.text_cell :if={!file.tracked} label="–" />
            </:col>
            <:col :let={file} label={dgettext("dashboard_tests", "Tests it selected")}>
              <.text_cell label={format_number(file.selected_tests_count)} />
            </:col>
          </.table>
          <.pagination_group
            :if={@files_meta.total_pages > 1}
            current_page={@files_meta.current_page}
            number_of_pages={@files_meta.total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "selection-page", page)}" end}
          />
        </div>

        <.coverage_empty
          :if={@files == []}
          title={
            if @diff,
              do: dgettext("dashboard_tests", "No file matches"),
              else: dgettext("dashboard_tests", "No baseline to diff against")
          }
          image="table"
          data-part="empty-selection-files"
        />
      </.card_section>
    </.card>
    """
  end

  defp modules_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Modules")}
      icon="stack_2"
      data-part="selection-modules-card"
    >
      <.card_section data-part="selection-table-section">
        <div :if={@targets != []} data-part="selection-table">
          <.table
            id="selection-modules-table"
            rows={@targets}
            row_key={& &1.module_name}
            row_navigate={
              fn target ->
                "?#{@uri.query |> Query.put("selection-tab", "tests") |> drop_tab_params() |> Query.put("selection-search", target.module_name)}"
              end
            }
          >
            <:col :let={target} label={dgettext("dashboard_tests", "Module")}>
              <.text_cell label={target.module_name} />
            </:col>
            <:col :let={target} label={dgettext("dashboard_tests", "Selected")}>
              <.text_cell label={"#{format_number(target.selected)} / #{format_number(target.requested)}"} />
            </:col>
            <:col :let={target} label={dgettext("dashboard_tests", "Skip rate")}>
              <.text_cell label={"#{Selections.skip_rate(target.selected, target.skipped)}%"} />
            </:col>
            <:col :let={target} label={dgettext("dashboard_tests", "Why it runs")}>
              <.text_cell label={
                target.reasons |> Enum.sort() |> Enum.map_join(", ", &reason_label/1)
              } />
            </:col>
            <:col :let={target} label={dgettext("dashboard_tests", "Est. time saved")}>
              <.text_cell label={format_duration(target.estimated_skipped_duration)} icon="history" />
            </:col>
          </.table>
        </div>
        <.coverage_empty
          :if={@targets == []}
          title={
            if @selection_run.requested_modules == [],
              do: dgettext("dashboard_tests", "Hashing left no module to decide"),
              else: dgettext("dashboard_tests", "The invocation requested no tests")
          }
          image="table"
        />
      </.card_section>
    </.card>
    <.card
      :if={@selection_run.skipped_modules != %{}}
      title={dgettext("dashboard_tests", "Unchanged modules")}
      icon="stack_2"
      data-part="selection-unchanged-modules-card"
    >
      <.card_section data-part="selection-table-section">
        <div data-part="selection-table">
          <.table
            id="selection-unchanged-modules-table"
            rows={Selections.skipped_modules(@selection_run)}
            row_key={& &1.module_name}
          >
            <:col :let={module} label={dgettext("dashboard_tests", "Module")}>
              <.text_cell label={module.module_name} />
            </:col>
            <:col :let={module} label={dgettext("dashboard_tests", "Tests skipped")}>
              <.text_cell label={format_number(module.tests)} />
            </:col>
          </.table>
        </div>
      </.card_section>
    </.card>
    """
  end

  defp shards_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Shards")}
      icon="server"
      data-part="selection-shards-card"
    >
      <.card_section data-part="selection-table-section">
        <div :if={@shards != []} data-part="selection-table">
          <.table
            id="selection-shards-table"
            rows={@shards}
            row_key={&"shard-#{&1.shard_index}"}
            row_navigate={
              fn shard ->
                "?#{@uri.query |> Query.put("selection-tab", "tests") |> drop_tab_params() |> Query.put("selection-decision", "selected") |> Query.put("selection-shard", shard.shard_index)}"
              end
            }
          >
            <:col :let={shard} label={dgettext("dashboard_tests", "Shard")}>
              <.text_cell label={shard_filter_label(shard.shard_index)} />
            </:col>
            <:col :let={shard} label={dgettext("dashboard_tests", "Planned")}>
              <.text_cell label={format_number(shard.planned)} />
            </:col>
            <:col :let={shard} label={dgettext("dashboard_tests", "Est. duration")}>
              <.text_cell label={format_duration(shard.estimated_duration)} icon="history" />
            </:col>
            <:col :let={shard} label={dgettext("dashboard_tests", "Ran")}>
              <.text_cell label={if @summary.reported, do: format_number(shard.ran), else: "–"} />
            </:col>
            <:col :let={shard} label={dgettext("dashboard_tests", "Failed")}>
              <.status_badge_cell
                :if={shard.failed > 0}
                status="error"
                label={format_number(shard.failed)}
              />
              <.text_cell :if={shard.failed == 0} label="0" />
            </:col>
            <:col :let={shard} label={dgettext("dashboard_tests", "Planned, not run")}>
              <.status_badge_cell
                :if={@summary.reported and shard.not_run > 0}
                status="warning"
                label={format_number(shard.not_run)}
              />
              <.text_cell
                :if={!@summary.reported or shard.not_run == 0}
                label={if @summary.reported, do: "0", else: "–"}
              />
            </:col>
          </.table>
        </div>
        <.coverage_empty
          :if={@shards == []}
          title={dgettext("dashboard_tests", "No test was planned on a shard")}
          image="table"
        />
      </.card_section>
    </.card>
    """
  end

  defp debug_card(assigns) do
    assigns = assign(assigns, :tracked_file_globs, Selections.tracked_file_globs(assigns.project))

    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Debug")}
      icon="settings"
      data-part="selection-debug-card"
    >
      <.card_section data-part="selection-table-section">
        <div :if={@selection_run.rule_trace != []} data-part="selection-table">
          <.table
            id="selection-rule-trace-table"
            rows={Enum.with_index(@selection_run.rule_trace)}
            row_key={fn {entry, index} -> "#{index}-#{entry.rule}" end}
          >
            <:col :let={{entry, _index}} label={dgettext("dashboard_tests", "Rule")}>
              <.text_cell label={entry.rule} />
            </:col>
            <:col :let={{entry, _index}} label={dgettext("dashboard_tests", "Selected")}>
              <.text_cell label={format_number(entry.selected)} />
            </:col>
            <:col :let={{entry, _index}} label={dgettext("dashboard_tests", "Skipped")}>
              <.text_cell label={format_number(entry.skipped)} />
            </:col>
            <:col :let={{entry, _index}} label={dgettext("dashboard_tests", "Verdict")}>
              <.badge_cell
                label={entry.verdict}
                color={if String.starts_with?(entry.verdict, "abort"), do: "warning", else: "neutral"}
                style="light-fill"
              />
            </:col>
          </.table>
        </div>
        <.coverage_empty
          :if={@selection_run.rule_trace == []}
          title={dgettext("dashboard_tests", "No rule ran")}
          image="table"
          data-part="empty-selection-rule-trace"
        />
      </.card_section>
      <.card_section data-part="selection-tracked-files-section">
        <dl data-part="details">
          <div>
            <dt>{dgettext("dashboard_tests", "Tracked files")}</dt>
            <dd id="selection-tracked-files">{Enum.join(@tracked_file_globs, ", ")}</dd>
          </div>
        </dl>
      </.card_section>
    </.card>
    """
  end

  defp tab_label("tests", %{summary: summary}),
    do: dgettext("dashboard_tests", "Tests (%{count})", count: format_number(summary.requested))

  defp tab_label("files", %{diff: diff}),
    do:
      dgettext("dashboard_tests", "Changed files (%{count})",
        count: format_number((diff && diff.changed_files_count) || 0)
      )

  defp tab_label("modules", %{selection_run: run} = assigns),
    do:
      dgettext("dashboard_tests", "Modules (%{count})",
        count: format_number(assigns.modules_count || length(run.requested_modules) + map_size(run.skipped_modules))
      )

  defp tab_label("shards", %{plan: plan}),
    do: dgettext("dashboard_tests", "Shards (%{count})", count: format_number(plan.shard_count))

  defp tab_label("debug", _assigns), do: dgettext("dashboard_tests", "Debug")

  # A test that ran opens its test case run's Selective Testing tab; one the
  # selection skipped never ran, so it opens the test case.
  defp test_href(account, project, %{test_case_run_id: id}) when is_binary(id) and id != "",
    do: "/#{account.name}/#{project.name}/tests/test-cases/runs/#{id}?tab=selective-testing"

  defp test_href(account, project, test), do: "/#{account.name}/#{project.name}/tests/test-cases/#{test.test_case_id}"

  defp drop_tab_params(query) do
    Enum.reduce(
      ~w(selection-search selection-decision selection-reason selection-flag selection-shard selection-tracked selection-sort-by selection-sort-order selection-page),
      query,
      &Query.drop(&2, &1)
    )
  end

  defp filter_patch(uri, key, value), do: "?#{uri.query |> Query.put(key, value) |> Query.drop("selection-page")}"

  defp column_sort_patch(uri, filters, column) do
    order =
      cond do
        filters.sort_by != column -> if column == "duration", do: "desc", else: "asc"
        filters.sort_order == "asc" -> "desc"
        true -> "asc"
      end

    "?#{uri.query |> Query.put("selection-sort-by", column) |> Query.put("selection-sort-order", order) |> Query.drop("selection-page")}"
  end

  defp reasons, do: Selections.selected_reasons() ++ Selections.skipped_reasons()

  defp has_baseline?(run), do: run.baseline_sha not in [nil, ""]

  defp decision_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  defp decision_filter_label(decision), do: decision_label(decision)

  defp flag_filter_label("not_run"), do: dgettext("dashboard_tests", "Planned, not run")
  defp flag_filter_label(_flag), do: dgettext("dashboard_tests", "Any")

  defp shard_filter_label(nil), do: dgettext("dashboard_tests", "Any")
  defp shard_filter_label(index), do: dgettext("dashboard_tests", "Shard %{index}", index: index)

  defp reason_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  defp reason_filter_label(reason), do: reason_label(reason)

  defp tracked_filter_label("true"), do: dgettext("dashboard_tests", "Tracked")
  defp tracked_filter_label(_tracked), do: dgettext("dashboard_tests", "All")

  defp format_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)

  defp parse_shard(_value, nil), do: nil

  defp parse_shard(value, plan) do
    case Integer.parse(value || "") do
      {index, ""} when index >= 0 and index < plan.shard_count -> index
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
