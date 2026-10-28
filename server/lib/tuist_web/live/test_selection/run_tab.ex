defmodule TuistWeb.TestSelection.RunTab do
  @moduledoc """
  The coverage selection a test run's tests came from, in the run's
  Selective Testing tab: the mode, the baseline, the counts and, in dry run,
  whether the skips would have hidden a failure; then four tabs:

  - Tests: every requested test with its decision, reason, shard, estimated
    duration and outcome, the dry-run misses and the selected tests that
    never reported flagged; each opens its test case run's Test Selection
    tab (`TuistWeb.TestSelection.TestCaseRunTab`).
  - Changed files: what changed since the baseline and how many tests each
    file reaches.
  - Targets: the requested tests per test target.
  - Shards: per shard, what was planned and what ran.

  Its query parameters are prefixed with `selection-` so they don't clash
  with the test run page's own.
  """
  use TuistWeb, :html
  use Noora

  import TuistWeb.Coverage.Components, only: [coverage_empty: 1, short_sha: 1, parent_dir: 1]
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components

  alias Tuist.Tests.Selections
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @tabs ~w(tests files targets shards)
  @sort_fields ~w(decision name shard duration)
  @kinds ~w(source test resource tracked ignored)

  @doc "What the tab shows before its data is loaded."
  def assign_defaults(socket) do
    Phoenix.Component.assign(socket,
      selection_summary: nil,
      selection_impact: nil,
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
  Loads what the tab shows for `selection_run` from the page's query
  `params`. The run's summary and impact are loaded once and kept.
  """
  def assign_data(socket, selection_run, params) do
    socket =
      if socket.assigns.selection_summary do
        socket
      else
        [summary, impact, baseline_coverage?] =
          Tuist.Tasks.parallel_tasks([
            fn -> Selections.run_summary(selection_run) end,
            fn -> Selections.get_impact(selection_run) end,
            fn -> Selections.coverage?(selection_run.project_id, selection_run.baseline_sha) end
          ])

        socket
        |> Phoenix.Component.assign(:selection_summary, summary)
        |> Phoenix.Component.assign(:selection_impact, impact)
        |> Phoenix.Component.assign(:selection_baseline_coverage?, baseline_coverage?)
      end

    tabs = tabs(selection_run)
    tab = if params["selection-tab"] in tabs, do: params["selection-tab"], else: "tests"

    socket
    |> Phoenix.Component.assign(:selection_tab, tab)
    |> assign_tab(tab, selection_run, params)
  end

  defp assign_tab(socket, "tests", run, params) do
    search = params["selection-search"] || ""
    decision = if params["selection-decision"] in ~w(selected skipped), do: params["selection-decision"], else: "any"
    flag = if params["selection-flag"] in ~w(missed not_run), do: params["selection-flag"], else: "any"
    shard = parse_shard(params["selection-shard"], run.shard_count)
    sort_by = if params["selection-sort-by"] in @sort_fields, do: params["selection-sort-by"], else: "decision"
    sort_order = if params["selection-sort-order"] == "desc", do: "desc", else: "asc"

    {rows, meta} =
      Selections.run_tests(run,
        search: search,
        decision: decision,
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
        flag: flag,
        shard: shard,
        sort_by: sort_by,
        sort_order: sort_order
      }
    )
  end

  defp assign_tab(socket, "files", _run, params) do
    search = params["selection-search"] || ""
    kind = if params["selection-kind"] in @kinds, do: params["selection-kind"], else: "any"

    {rows, meta} =
      case socket.assigns.selection_impact do
        nil ->
          {[], %{current_page: 1, total_pages: 1, total_count: 0}}

        impact ->
          Selections.impact_changed_files(impact,
            search: search,
            kind: kind,
            page: parse_page(params["selection-page"])
          )
      end

    Phoenix.Component.assign(socket,
      selection_files: rows,
      selection_files_meta: meta,
      selection_filters: %{search: search, kind: kind}
    )
  end

  defp assign_tab(socket, "targets", run, _params),
    do: Phoenix.Component.assign(socket, :selection_targets, Selections.run_targets(run))

  defp assign_tab(socket, "shards", run, _params),
    do: Phoenix.Component.assign(socket, :selection_shards, Selections.run_shards(run))

  @doc "The query that searches the current tab for `search`."
  def search_query(uri, search), do: uri.query |> Query.put("selection-search", search) |> Query.drop("selection-page")

  defp tabs(%{shard_count: count}) when count > 1, do: @tabs
  defp tabs(_run), do: List.delete(@tabs, "shards")

  attr :selection_run, :map, required: true
  attr :summary, :map, required: true
  attr :impact, :any, required: true
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

  def coverage_selection(assigns) do
    ~H"""
    <div class="tuist-coverage-selection" data-part="coverage-selection">
      <.card
        title={dgettext("dashboard_tests", "Coverage selection")}
        icon="filter"
        data-part="selection-summary-card"
      >
        <:actions>
          <.badge
            label={mode_label(@selection_run.mode)}
            color={mode_color(@selection_run.mode)}
            style="light-fill"
            size="large"
          />
        </:actions>
        <.card_section
          :if={@selection_run.fallback_reason != "" or @selection_run.mode == "dry_run"}
          data-part="selection-verdict-section"
        >
          <.alert
            :if={@selection_run.fallback_reason != ""}
            id="test-selection-fallback"
            type="secondary"
            status="warning"
            size="large"
            title={
              dgettext("dashboard_tests", "Ran everything: %{reason}",
                reason: fallback_label(@selection_run.fallback_reason)
              )
            }
            description={fallback_description(@selection_run.fallback_reason)}
          />
          <.dry_run_verdict
            :if={@selection_run.fallback_reason == "" and @selection_run.mode == "dry_run"}
            selection_run={@selection_run}
            summary={@summary}
            uri={@uri}
          />
        </.card_section>
        <.card_section data-part="selection-widgets-section">
          <div data-part="widgets">
            <.widget
              id="widget-selection-selected"
              title={
                if @selection_run.mode == "dry_run",
                  do: dgettext("dashboard_tests", "Would run"),
                  else: dgettext("dashboard_tests", "Ran")
              }
              description={
                dgettext(
                  "dashboard_tests",
                  "Requested tests the selection kept, out of all requested."
                )
              }
              value={"#{format_number(@summary.selected)} / #{format_number(@summary.requested)}"}
              legend_color="primary"
            />
            <.widget
              id="widget-selection-skipped"
              title={
                if @selection_run.mode == "dry_run",
                  do: dgettext("dashboard_tests", "Would skip"),
                  else: dgettext("dashboard_tests", "Skipped")
              }
              description={
                if @selection_run.mode == "dry_run",
                  do:
                    dgettext(
                      "dashboard_tests",
                      "Requested tests the selection would have skipped. In dry run they ran anyway."
                    ),
                  else: dgettext("dashboard_tests", "Requested tests the selection skipped.")
              }
              value={format_number(@summary.skipped)}
              legend_color="secondary"
            />
            <.widget
              id="widget-selection-skip-rate"
              title={dgettext("dashboard_tests", "Skip rate")}
              description={
                dgettext("dashboard_tests", "The share of requested tests that were skipped.")
              }
              value={"#{@summary.skip_rate}%"}
              legend_color="tertiary"
            />
            <.widget
              id="widget-selection-time-saved"
              title={dgettext("dashboard_tests", "Est. time saved")}
              description={
                dgettext(
                  "dashboard_tests",
                  "The skipped tests' estimated duration, run one after another."
                )
              }
              value={format_duration(@selection_run.skipped_duration)}
            />
            <.widget
              :if={@selection_run.mode == "dry_run"}
              id="widget-selection-missed"
              title={dgettext("dashboard_tests", "Misses")}
              description={
                dgettext(
                  "dashboard_tests",
                  "Tests the selection would have skipped that failed when they ran anyway."
                )
              }
              value={if @summary.reported, do: format_number(@summary.missed), else: "–"}
              legend_color="destructive"
            />
            <.widget
              :if={@selection_run.mode != "dry_run"}
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
                  :if={@selection_run.baseline_sha != "" and @baseline_coverage?}
                  navigate={
                    "/#{@account.name}/#{@project.name}/tests/coverage/commits/#{@selection_run.baseline_sha}"
                  }
                  label={short_sha(@selection_run.baseline_sha)}
                  variant="secondary"
                  size="large"
                  underline
                />
                <span :if={@selection_run.baseline_sha != "" and !@baseline_coverage?}>
                  {short_sha(@selection_run.baseline_sha)}
                </span>
                <span :if={@selection_run.baseline_sha == ""}>
                  {dgettext("dashboard_tests", "None")}
                </span>
              </dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Changed since the baseline")}</dt>
              <dd>
                {if @impact,
                  do:
                    dngettext(
                      "dashboard_tests",
                      "%{count} file",
                      "%{count} files",
                      @impact.changed_files_count,
                      count: format_number(@impact.changed_files_count)
                    ),
                  else: "–"}
              </dd>
            </div>
            <div>
              <dt>{scheme_label(@project)}</dt>
              <dd>{@selection_run.scheme}</dd>
            </div>
            <div :if={@selection_run.test_plan != ""}>
              <dt>{dgettext("dashboard_tests", "Test plan")}</dt>
              <dd>{@selection_run.test_plan}</dd>
            </div>
            <div :if={@selection_run.destination != ""}>
              <dt>{dgettext("dashboard_tests", "Destination")}</dt>
              <dd>{@selection_run.destination}</dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Shards")}</dt>
              <dd>{format_number(@selection_run.shard_count)}</dd>
            </div>
            <div>
              <dt>{dgettext("dashboard_tests", "Selected at")}</dt>
              <dd>{DateFormatter.from_now(@selection_run.inserted_at)}</dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.tab_menu_horizontal>
        <.tab_menu_horizontal_item
          :for={tab <- tabs(@selection_run)}
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

  attr :selection_run, :map, required: true
  attr :summary, :map, required: true
  attr :uri, :any, required: true

  # In dry run nothing was skipped, so the question the tab answers first is
  # whether enforcing the selection would have been safe on this run.
  defp dry_run_verdict(assigns) do
    ~H"""
    <.alert
      :if={!@summary.reported}
      id="test-selection-dry-run"
      type="secondary"
      status="information"
      size="large"
      title={dgettext("dashboard_tests", "Dry run: nothing was skipped")}
      description={
        dgettext(
          "dashboard_tests",
          "The selection would skip %{skipped} of %{requested} tests (%{rate}%). Misses are counted once the run's results are processed.",
          skipped: format_number(@summary.skipped),
          requested: format_number(@summary.requested),
          rate: @summary.skip_rate
        )
      }
    />
    <.alert
      :if={@summary.reported and @summary.missed == 0}
      id="test-selection-dry-run"
      type="secondary"
      status="success"
      size="large"
      title={dgettext("dashboard_tests", "Dry run: no misses")}
      description={
        dgettext(
          "dashboard_tests",
          "The selection would have skipped %{skipped} of %{requested} tests (%{rate}%), saving about %{saved}. None of them failed, so enforcing it would have caught every failure this run found.",
          skipped: format_number(@summary.skipped),
          requested: format_number(@summary.requested),
          rate: @summary.skip_rate,
          saved: format_duration(@selection_run.skipped_duration)
        )
      }
    />
    <.alert
      :if={@summary.reported and @summary.missed > 0}
      id="test-selection-dry-run"
      type="secondary"
      status="error"
      size="large"
      title={
        dngettext(
          "dashboard_tests",
          "Dry run: %{count} miss",
          "Dry run: %{count} misses",
          @summary.missed,
          count: format_number(@summary.missed)
        )
      }
      description={
        dngettext(
          "dashboard_tests",
          "The selection would have skipped %{skipped} of %{requested} tests (%{rate}%), but %{count} of them failed when it ran anyway. Enforced, the selection would have hidden that failure.",
          "The selection would have skipped %{skipped} of %{requested} tests (%{rate}%), but %{count} of them failed when they ran anyway. Enforced, the selection would have hidden those failures.",
          @summary.missed,
          skipped: format_number(@summary.skipped),
          requested: format_number(@summary.requested),
          rate: @summary.skip_rate,
          count: format_number(@summary.missed)
        )
      }
    >
      <:action>
        <.button
          label={dgettext("dashboard_tests", "Show misses")}
          variant="secondary"
          size="small"
          patch={
            "?#{@uri.query |> Query.put("selection-tab", "tests") |> drop_tab_params() |> Query.put("selection-flag", "missed")}"
          }
          data-part="show-misses"
        />
      </:action>
    </.alert>
    """
  end

  defp tab_card(%{tab: "tests"} = assigns), do: tests_card(assigns)
  defp tab_card(%{tab: "files"} = assigns), do: files_card(assigns)
  defp tab_card(%{tab: "targets"} = assigns), do: targets_card(assigns)
  defp tab_card(%{tab: "shards"} = assigns), do: shards_card(assigns)

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
            label={decision_filter_label(@filters.decision, @selection_run.mode)}
            secondary_text={dgettext("dashboard_tests", "Decision:")}
          >
            <.dropdown_item
              :for={decision <- ~w(any selected skipped)}
              value={decision}
              label={decision_filter_label(decision, @selection_run.mode)}
              patch={filter_patch(@uri, "selection-decision", decision)}
              data-selected={@filters.decision == decision}
            >
              <:right_icon :if={@filters.decision == decision}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            :if={@selection_run.test_run_id}
            id="selection-flag-dropdown"
            label={flag_filter_label(@filters.flag)}
            secondary_text={dgettext("dashboard_tests", "Flag:")}
          >
            <.dropdown_item
              :for={
                flag <-
                  if(@selection_run.mode == "dry_run",
                    do: ~w(any missed not_run),
                    else: ~w(any not_run)
                  )
              }
              value={flag}
              label={flag_filter_label(flag)}
              patch={filter_patch(@uri, "selection-flag", flag)}
              data-selected={@filters.flag == flag}
            >
              <:right_icon :if={@filters.flag == flag}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            :if={@selection_run.shard_count > 1}
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
              :for={index <- 0..(@selection_run.shard_count - 1)}
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
              <.decision_cell decision={test.decision} mode={@selection_run.mode} />
            </:col>
            <:col :let={test} label={dgettext("dashboard_tests", "Reason")}>
              <.text_and_description_cell
                label={reason_label(test.reason)}
                description={if test.matched_path != "", do: Path.basename(test.matched_path)}
              />
            </:col>
            <:col
              :let={test}
              :if={@selection_run.shard_count > 1}
              label={dgettext("dashboard_tests", "Shard")}
              patch={column_sort_patch(@uri, @filters, "shard")}
              sort_order={@filters.sort_by == "shard" && @filters.sort_order}
            >
              <.text_cell label={
                if test.decision == "selected", do: format_number(test.shard_index), else: "–"
              } />
            </:col>
            <:col
              :let={test}
              label={dgettext("dashboard_tests", "Est. duration")}
              patch={column_sort_patch(@uri, @filters, "duration")}
              sort_order={@filters.sort_by == "duration" && @filters.sort_order}
            >
              <.text_cell label={format_duration(test.estimated_duration_ms)} icon="history" />
            </:col>
            <:col :let={test} label={dgettext("dashboard_tests", "Outcome")}>
              <.outcome_cell
                outcome={visible_outcome(test, @selection_run.mode)}
                decision={test.decision}
                mode={@selection_run.mode}
                reported={not is_nil(@selection_run.test_run_id)}
              />
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
            id="selection-kind-dropdown"
            label={kind_filter_label(@filters.kind)}
            secondary_text={dgettext("dashboard_tests", "Kind:")}
          >
            <.dropdown_item
              :for={kind <- ["any" | kinds()]}
              value={kind}
              label={kind_filter_label(kind)}
              patch={filter_patch(@uri, "selection-kind", kind)}
              data-selected={@filters.kind == kind}
            >
              <:right_icon :if={@filters.kind == kind}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>

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
            <:col :let={file} label={dgettext("dashboard_tests", "Kind")}>
              <.badge_cell
                label={file_kind_label(file.kind)}
                color={file_kind_color(file.kind)}
                style="light-fill"
              />
            </:col>
            <:col :let={file} label={dgettext("dashboard_tests", "Tests it reaches")}>
              <.text_cell label={format_number(file.impacted_tests_count)} />
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
            if @impact,
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

  defp targets_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Targets")}
      icon="stack_2"
      data-part="selection-targets-card"
    >
      <.card_section data-part="selection-table-section">
        <div :if={@targets != []} data-part="selection-table">
          <.table
            id="selection-targets-table"
            rows={@targets}
            row_key={& &1.module_name}
            row_navigate={
              fn target ->
                "?#{@uri.query |> Query.put("selection-tab", "tests") |> drop_tab_params() |> Query.put("selection-search", target.module_name)}"
              end
            }
          >
            <:col :let={target} label={dgettext("dashboard_tests", "Test target")}>
              <.text_cell label={target.module_name} />
            </:col>
            <:col
              :let={target}
              label={
                if @selection_run.mode == "dry_run",
                  do: dgettext("dashboard_tests", "Would run"),
                  else: dgettext("dashboard_tests", "Selected")
              }
            >
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
          title={dgettext("dashboard_tests", "The invocation requested no tests")}
          image="table"
        />
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

  defp tab_label("tests", %{selection_run: run}),
    do: dgettext("dashboard_tests", "Tests (%{count})", count: format_number(run.requested_count))

  defp tab_label("files", %{impact: impact}),
    do:
      dgettext("dashboard_tests", "Changed files (%{count})",
        count: format_number((impact && impact.changed_files_count) || 0)
      )

  defp tab_label("targets", %{selection_run: run}),
    do: dgettext("dashboard_tests", "Targets (%{count})", count: format_number(length(run.requested_targets)))

  defp tab_label("shards", %{selection_run: run}),
    do: dgettext("dashboard_tests", "Shards (%{count})", count: format_number(run.shard_count))

  # A test that ran opens its test case run's Test Selection tab; one the
  # selection skipped never ran, so it opens the test case.
  defp test_href(account, project, %{test_case_run_id: id}) when is_binary(id) and id != "",
    do: "/#{account.name}/#{project.name}/tests/test-cases/runs/#{id}?tab=test-selection"

  defp test_href(account, project, test), do: "/#{account.name}/#{project.name}/tests/test-cases/#{test.test_case_id}"

  defp drop_tab_params(query) do
    Enum.reduce(
      ~w(selection-search selection-decision selection-flag selection-shard selection-kind selection-sort-by selection-sort-order selection-page),
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

  defp kinds, do: @kinds

  defp decision_filter_label("any", _mode), do: dgettext("dashboard_tests", "Any")
  defp decision_filter_label(decision, mode), do: decision_label(decision, mode)

  defp flag_filter_label("missed"), do: dgettext("dashboard_tests", "Misses")
  defp flag_filter_label("not_run"), do: dgettext("dashboard_tests", "Planned, not run")
  defp flag_filter_label(_flag), do: dgettext("dashboard_tests", "Any")

  defp shard_filter_label(nil), do: dgettext("dashboard_tests", "Any")
  defp shard_filter_label(index), do: dgettext("dashboard_tests", "Shard %{index}", index: index)

  defp kind_filter_label("any"), do: dgettext("dashboard_tests", "Any")
  defp kind_filter_label(kind), do: file_kind_label(kind)

  defp format_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)

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
