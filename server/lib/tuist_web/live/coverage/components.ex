defmodule TuistWeb.Coverage.Components do
  @moduledoc """
  The cells and words the coverage pages share: a file's coverage as a bar,
  a difference in percentage points, and
  the labels that word a commit's completeness, a gate's verdict and the
  reasons a comparison could not be made.
  """
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits

  attr :title, :string, required: true
  attr :get_started_href, :string, default: nil
  attr :image, :string, default: "line_chart", values: ~w(line_chart table)
  attr :rest, :global

  def coverage_empty(assigns) do
    assigns = assign(assigns, :artwork, empty_artwork(assigns.image))

    ~H"""
    <.empty_card_section title={@title} get_started_href={@get_started_href} {@rest}>
      <:image>
        <img src={@artwork.light} data-theme="light" loading="lazy" decoding="async" />
        <img src={@artwork.dark} data-theme="dark" loading="lazy" decoding="async" />
      </:image>
    </.empty_card_section>
    """
  end

  def empty_artwork("table"), do: %{light: ~p"/images/empty_table_light.png", dark: ~p"/images/empty_table_dark.png"}

  def empty_artwork(_image),
    do: %{light: ~p"/images/empty_line_chart_light.png", dark: ~p"/images/empty_line_chart_dark.png"}

  attr :covered, :integer, required: true
  attr :executable, :integer, required: true

  def coverage_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <div data-part="coverage-cell">
        <.progress_bar value={@covered} max={max(@executable, 1)} />
        <span data-part="percentage">{Coverage.percentage(@covered, @executable)}%</span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :partial, :boolean, default: nil

  @doc "Whether a run measured every test (Full) or selective testing left some out (Partial); nil for no run."
  def run_kind_cell(assigns) do
    ~H"""
    <.tooltip_badge_cell
      :if={not is_nil(@partial)}
      id={@id}
      label={
        if @partial,
          do: dgettext("dashboard_tests", "Partial"),
          else: dgettext("dashboard_tests", "Full")
      }
      color={if @partial, do: "warning", else: "success"}
      description={
        if @partial,
          do:
            dgettext(
              "dashboard_tests",
              "Selective testing, or a filter, left some of the run's tests out, so it measured part of the scheme."
            ),
          else:
            dgettext(
              "dashboard_tests",
              "Every test of the run's scheme ran, so it measured the scheme in full."
            )
      }
    />
    <.text_cell :if={is_nil(@partial)} label="—" />
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :color, :string, required: true
  attr :description, :string, required: true

  @doc """
  A table's badge cell with a tooltip that says what the badge means, titled
  by the badge. The tooltip wraps the badge only, not the cell, so it opens
  over the badge and right against it.
  """
  def tooltip_badge_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="badge">
      <.tooltip id={@id} size="large" title={@label} description={@description}>
        <:trigger :let={attrs}>
          <span {attrs} tabindex="0">
            <.badge label={@label} color={@color} style="light-fill" size="large" />
          </span>
        </:trigger>
      </.tooltip>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :ranges, :list, default: nil

  # Line ranges shown briefly, with every range in a tooltip once they do not
  # all fit (`full_line_ranges/1`).
  defp line_ranges(assigns) do
    assigns = assign(assigns, :full, full_line_ranges(assigns.ranges))

    ~H"""
    <span :if={is_nil(@ranges)}>{dgettext("dashboard_tests", "Unavailable")}</span>
    <span :if={@ranges == []}>{dgettext("dashboard_tests", "None")}</span>
    <span :if={@ranges not in [nil, []] and is_nil(@full)}>{brief_line_ranges(@ranges)}</span>
    <.tooltip
      :if={@full}
      id={@id}
      size="large"
      title={@title}
      description={@full}
    >
      <:trigger :let={attrs}>
        <span {attrs} tabindex="0">{brief_line_ranges(@ranges)}</span>
      </:trigger>
    </.tooltip>
    """
  end

  @doc """
  Where a coverage page's back button leads when it was opened from another
  coverage page (the `from` parameter the links out of a branch, a pull
  request or a commit carry): that page, named for what it is. Nil when
  `from` is missing or points anywhere but the project's coverage pages.
  """
  def back_to(nil, _account_name, _project_name), do: nil

  def back_to(from, account_name, project_name) do
    prefix = "/#{account_name}/#{project_name}/tests/coverage/"
    %URI{path: path, scheme: scheme, host: host} = URI.parse(from)

    if is_nil(scheme) and is_nil(host) and is_binary(path) and String.starts_with?(path, prefix) and
         not String.contains?(from, ["//", "\\"]) do
      %{label: path |> String.replace_prefix(prefix, "") |> String.split("/") |> back_label(), href: from}
    end
  end

  defp back_label(["branches" | branch]) when branch != [],
    do: dgettext("dashboard_tests", "Branch %{name}", name: Enum.map_join(branch, "/", &URI.decode/1))

  defp back_label(["pull-requests", number]), do: dgettext("dashboard_tests", "Pull request %{name}", name: "#" <> number)
  defp back_label(["commits", sha]), do: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha))
  defp back_label(_path), do: dgettext("dashboard_tests", "Code coverage")

  @doc false
  def short_sha(sha), do: String.slice(sha || "", 0, 7)

  @doc """
  The figure a commit is shown with: its reported coverage once its runs
  skipped tests, what a full run would measure when every one of them was
  carried forward and the confirmed part of it otherwise (the lines known to
  be covered among those that could be counted), and what the runs measured
  when nothing was skipped.
  """
  def displayed_coverage(%{reported: %{kind: kind, coverage: coverage}}) when kind in ~w(reported partial), do: coverage
  def displayed_coverage(%{coverage: coverage}), do: coverage

  @doc "Whether the whole of a commit's figure is confirmed (`Tuist.Tests.Coverage.Commits.confirmed?/1`)."
  def confirmed?(summary), do: Commits.confirmed?(summary)

  @doc "The line totals behind `displayed_coverage/1`, from a commit's published summary (nil when there is none)."
  def displayed_lines(%{reported_kind: kind, reported_covered_lines: covered, reported_executable_lines: executable})
      when kind in ~w(reported partial), do: %{covered_lines: covered, executable_lines: executable}

  def displayed_lines(%{covered_lines: covered, executable_lines: executable}),
    do: %{covered_lines: covered, executable_lines: executable}

  def displayed_lines(_summary), do: %{covered_lines: 0, executable_lines: 0}

  @doc "What the page says about a commit some scheme of which only ran selectively."
  def partial_run_title(%{reported: %{kind: "reported"} = reported} = commit) do
    dgettext(
      "dashboard_tests",
      "Some tests were skipped (%{schemes}). The coverage of the %{count} skipped tests was carried forward from the commits they last ran at, every file they executed being unchanged, so the total is what a full run would measure: %{reported}% reported, %{measured}% measured here.",
      schemes: Enum.join(commit.partial_schemes, ", "),
      count: reported.carried_tests_count,
      reported: reported.coverage,
      measured: commit.coverage
    )
  end

  def partial_run_title(%{reported: %{kind: "partial", skipped_tests_count: skipped} = reported} = commit)
      when skipped > 0 do
    dgettext(
      "dashboard_tests",
      "Some tests were skipped (%{schemes}): the total is not compared, and only the files some test executed are. The coverage of %{carried} of the %{skipped} skipped tests could be carried forward; the rest changed, failed or has no line evidence.",
      schemes: Enum.join(commit.partial_schemes, ", "),
      carried: reported.carried_tests_count,
      skipped: skipped
    )
  end

  def partial_run_title(commit) do
    dgettext(
      "dashboard_tests",
      "Some tests were skipped (%{schemes}): the total is not compared, and only the files some test executed are.",
      schemes: Enum.join(commit.partial_schemes, ", ")
    )
  end

  @doc """
  A commit's status in a list: `Not measured` when no run measured it (a
  branch lists every commit on it), otherwise `Complete` or `Pending` as its
  pipeline signalled it finished or not.
  """
  def commit_status_label(%{measured: false}), do: dgettext("dashboard_tests", "Not measured")
  def commit_status_label(commit), do: ref_status_label(commit)

  @doc "What a commit's status in a list means, for the status's tooltip."
  def commit_status_title(%{measured: false}),
    do: dgettext("dashboard_tests", "No run of this commit gathered coverage, so it has no figure of its own.")

  def commit_status_title(commit), do: head_status_title(commit)

  def commit_status_color(%{measured: false}), do: "neutral"
  def commit_status_color(commit), do: ref_status_color(commit)

  @doc """
  When a point of a coverage series happened, for the chart's axis: the start
  of the day, week or month it stands for when grouped, otherwise the commit's
  own time, or when it was measured where Git's history has none. Never when
  its totals were stored, which moves every time they are recomputed.
  """
  def point_time(point) do
    case Map.get(point, :period) || Map.get(point, :committed_at) || Map.get(point, :ran_at) || point.inserted_at do
      %DateTime{} = at -> DateTime.to_iso8601(at)
      at -> NaiveDateTime.to_iso8601(at)
    end
  end

  @doc """
  The points a trend chart draws over a period: every commit over a month at
  most, the last commit of each week over half a year at most, and the last
  of each month past that.
  """
  def chart_points(points, {start_datetime, end_datetime}) do
    days = DateTime.diff(end_datetime, start_datetime, :day)

    cond do
      days <= 30 -> points
      days <= 183 -> last_per(points, &Date.beginning_of_week(point_date(&1)))
      true -> last_per(points, &Date.beginning_of_month(point_date(&1)))
    end
  end

  defp last_per(points, bucket) do
    points
    |> Enum.chunk_by(bucket)
    |> Enum.map(&List.last/1)
  end

  defp point_date(point) do
    case Map.get(point, :committed_at) || Map.get(point, :ran_at) || point.inserted_at do
      %DateTime{} = at -> DateTime.to_date(at)
      at -> NaiveDateTime.to_date(at)
    end
  end

  @doc "How far coverage moved from a series' first point to its last, or nil when there is nothing to compare."
  def period_trend([first | [_ | _] = rest]) do
    last = List.last(rest)
    if is_number(first.coverage) and is_number(last.coverage), do: Float.round(last.coverage - first.coverage, 1)
  end

  def period_trend(_series), do: nil

  @doc """
  How much a count moved from a series' first point to its last, as a
  percentage of the first, or nil when there is nothing to compare.
  """
  def count_trend([first | [_ | _] = rest], field) do
    from = Map.get(first, field) || 0
    to = Map.get(List.last(rest), field) || 0
    if from > 0, do: Float.round((to - from) / from * 100, 1)
  end

  def count_trend(_series, _field), do: nil

  @doc "The directory a file sits in, or nil for one at the repository's root."
  def parent_dir(path) do
    case Path.dirname(path) do
      "." -> nil
      dir -> dir
    end
  end

  @doc """
  A branch's or pull request's state. Chaining is about a trend, which a
  single head commit has none of, so a ref is either complete or still
  waiting for its pipeline to say so.
  """
  def ref_status_label(%{complete: true}), do: dgettext("dashboard_tests", "Complete")
  def ref_status_label(_ref), do: dgettext("dashboard_tests", "Pending")

  @doc "What the status of the commit a page describes means, for its title."
  def head_status_title(%{complete: true}),
    do:
      dgettext(
        "dashboard_tests",
        "This commit's coverage pipeline signalled it finished, so its figure is final and its gates are decided."
      )

  def head_status_title(_commit),
    do:
      dgettext(
        "dashboard_tests",
        "This commit's coverage pipeline has not signalled completion yet, so more runs may still land and its gates wait."
      )

  def ref_status_color(%{complete: true}), do: "success"
  def ref_status_color(_ref), do: "information"

  @brief_ranges 2

  @doc "Line ranges (`[first, last]` or `{first, last}`) as `3–5, 9`; a dash for none."
  def line_ranges_label(ranges) when ranges in [nil, []], do: "—"

  def line_ranges_label(ranges) do
    Enum.map_join(ranges, ", ", fn
      [line, line] -> Integer.to_string(line)
      {line, line} -> Integer.to_string(line)
      [first, last] -> "#{first}–#{last}"
      {first, last} -> "#{first}–#{last}"
    end)
  end

  @doc """
  Line ranges as `line_ranges_label/1` words them, but at most two: past
  them, an ellipsis, and `full_line_ranges/1` for the title holding them all.
  """
  def brief_line_ranges(ranges) when ranges in [nil, []], do: "—"

  def brief_line_ranges(ranges) when length(ranges) > @brief_ranges,
    do: line_ranges_label(Enum.take(ranges, @brief_ranges)) <> ", …"

  def brief_line_ranges(ranges), do: line_ranges_label(ranges)

  @doc "Every range, for the title of a `brief_line_ranges/1` that left some out; nil when it left none."
  def full_line_ranges(ranges) when is_list(ranges) and length(ranges) > @brief_ranges, do: line_ranges_label(ranges)
  def full_line_ranges(_ranges), do: nil

  @doc """
  Where a file's own page lives: it carries the commit it was read at and the
  tab of the commit's page it was opened from, so the page can lead back there.
  `branch` or `pull_request` names what that page read the commit as.
  """
  def coverage_file_href(account_name, project_name, path, scope) do
    query =
      Enum.flat_map(
        [commit: "commit", branch: "branch", pull_request: "pull-request", tab: "tab", from: "from"],
        fn {key, name} ->
          case Map.get(scope, key) do
            value when value in [nil, ""] -> []
            value -> [{name, value}]
          end
        end
      )

    "/#{account_name}/#{project_name}/tests/coverage/files/#{encode_path(path)}?" <> URI.encode_query(query)
  end

  @doc false
  def encode_path(path), do: path |> String.split("/") |> Enum.map_join("/", &encode_segment/1)

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  attr :file, :map, required: true, doc: "A file's detail, from `Commits.file_detail/4`."

  attr :trend, :map,
    default: nil,
    doc: """
    The file's coverage over a branch's period, when the page was opened from
    a branch: `branch`, `points`, `latest`, `trends`, `selected_widget`,
    `preset` and `period`, as `coverage_analytics_card/1` takes them.
    """

  @doc """
  One file's coverage: its figures (over the period, on a branch) and the
  lines skipped tests' coverage was carried into. Its page lists the
  functions under it.
  """
  def coverage_file_view(assigns) do
    assigns = assign(assigns, :functions, Map.get(assigns.file, :functions, []))

    ~H"""
    <.coverage_analytics_card
      :if={@trend}
      branch={@trend.branch}
      latest={@trend.latest}
      trends={@trend.trends}
      points={@trend.points}
      selected_widget={@trend.selected_widget}
      empty_title={
        dgettext(
          "dashboard_tests",
          "No measured commit on %{branch} compiled this file in this period",
          branch: @trend.branch
        )
      }
    >
      <:actions>
        <.coverage_period_picker
          id="coverage-file-date-range-picker"
          selected_preset={@trend.preset}
          period={@trend.period}
        />
      </:actions>
      <:details :if={Map.get(@file, :carried_lines, []) != []}>
        <.carried_lines lines={@file.carried_lines} />
      </:details>
    </.coverage_analytics_card>
    <.card
      :if={is_nil(@trend)}
      title={dgettext("dashboard_tests", "Analytics")}
      icon="chart_arcs"
      data-part="file-summary-card"
    >
      <.card_section data-part="file-summary-section">
        <div data-part="widgets">
          <.widget
            id="widget-coverage-file-percentage"
            title={dgettext("dashboard_tests", "Code coverage")}
            description={
              dgettext(
                "dashboard_tests",
                "Share of the file's executable lines the tests ran at least once."
              )
            }
            value={"#{Coverage.percentage(@file.covered_lines, @file.executable_lines)}%"}
          />
          <.widget
            id="widget-coverage-file-lines"
            title={dgettext("dashboard_tests", "Covered lines")}
            description={dgettext("dashboard_tests", "Executable lines the tests ran at least once.")}
            value={"#{format_number(@file.covered_lines)} / #{format_number(@file.executable_lines)}"}
          />
          <.widget
            :if={@functions != []}
            id="widget-coverage-file-functions"
            title={dgettext("dashboard_tests", "Functions")}
            description={
              dgettext("dashboard_tests", "Functions the compiler instrumented in the file.")
            }
            value={format_number(length(@functions))}
          />
        </div>
        <.carried_lines :if={Map.get(@file, :carried_lines, []) != []} lines={@file.carried_lines} />
      </.card_section>
    </.card>
    """
  end

  attr :lines, :list, required: true

  defp carried_lines(assigns) do
    ~H"""
    <dl data-part="file-details">
      <div>
        <dt>{dgettext("dashboard_tests", "Covered by skipped tests, carried forward")}</dt>
        <dd id="coverage-file-carried-lines">
          <.line_ranges
            id="coverage-file-carried-lines-tooltip"
            title={dgettext("dashboard_tests", "Covered by skipped tests, carried forward")}
            ranges={Coverage.Evidence.line_ranges(@lines)}
          />
        </dd>
      </div>
    </dl>
    """
  end

  attr :id, :string, default: "coverage-files-table"

  attr :rows, :list, required: true, doc: "Files with `path`, `covered_lines` and `executable_lines`."

  attr :file_href, :any, required: true, doc: "A file's page, from its path."
  attr :meta, :map, required: true, doc: "`current_page` and `total_pages`."
  attr :page_patch, :any, required: true
  attr :sort_by, :string, required: true, doc: "The column the files are sorted by: `path` or `coverage`."
  attr :sort_order, :string, required: true
  attr :sort_patch, :any, required: true, doc: "The patch that sorts by a column."

  @doc """
  A list of files, each opening on its own page with its coverage.
  """
  def coverage_files_table(assigns) do
    ~H"""
    <div data-part="files-table">
      <.table id={@id} rows={@rows} row_navigate={fn file -> @file_href.(file.path) end}>
        <:col
          :let={file}
          label={dgettext("dashboard_tests", "File")}
          patch={@sort_by == "path" && @sort_patch.("path")}
          sort_order={@sort_by == "path" && @sort_order}
        >
          <.text_and_description_cell
            label={Path.basename(file.path)}
            description={parent_dir(file.path)}
          />
        </:col>
        <:col
          :let={file}
          label={dgettext("dashboard_tests", "File coverage")}
          patch={@sort_by == "coverage" && @sort_patch.("coverage")}
          sort_order={@sort_by == "coverage" && @sort_order}
        >
          <.coverage_cell covered={file.covered_lines} executable={file.executable_lines} />
        </:col>
        <:empty_state>
          <.table_empty_state
            icon="file"
            title={dgettext("dashboard_tests", "No file matches this search")}
            subtitle={dgettext("dashboard_tests", "Try updating your search")}
          />
        </:empty_state>
      </.table>
      <.pagination_group
        :if={@meta.total_pages > 1}
        current_page={@meta.current_page}
        number_of_pages={@meta.total_pages}
        page_patch={@page_patch}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :selected_preset, :string, required: true
  attr :period, :any, required: true

  @doc """
  The period a coverage page's figures cover, for the header of each card
  that depends on it; every picker on a page sets the same period.
  """
  def coverage_period_picker(assigns) do
    ~H"""
    <.date_picker
      id={@id}
      name="coverage-date-range"
      presets={[
        %{id: "last-7-days", label: dgettext("dashboard_tests", "Last 7 days"), period: {7, :day}},
        %{id: "last-30-days", label: dgettext("dashboard_tests", "Last 30 days"), period: {30, :day}},
        %{
          id: "last-12-months",
          label: dgettext("dashboard_tests", "Last 12 months"),
          period: {12, :month}
        },
        %{id: "custom", label: dgettext("dashboard_tests", "Custom")}
      ]}
      selected_preset={@selected_preset}
      period={@period}
      on_period_change="coverage_period_changed"
      max={Date.utc_today()}
    >
      <:actions>
        <.button
          label={dgettext("dashboard_tests", "Cancel")}
          variant="secondary"
          phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: @id})}
        />
        <.button
          label={dgettext("dashboard_tests", "Apply")}
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: @id})}
        />
      </:actions>
    </.date_picker>
    """
  end

  attr :branch, :string, required: true
  attr :latest, :map, default: nil, doc: "The branch's latest measured point in the period, or nil."
  attr :trends, :map, required: true
  attr :points, :list, required: true
  attr :selected_widget, :string, required: true
  attr :title, :string, default: nil, doc: "The card's title; Analytics when none is given."
  attr :empty_title, :string, default: nil, doc: "What the card says when no commit was measured in the period."

  attr :grouping, :atom,
    default: nil,
    doc: "What each point stands for (`History.trend_points/3`): a commit, or a day, week or month; the tooltip names it."

  slot :actions
  slot :details, doc: "Figures shown under the chart."

  @doc """
  A branch's coverage over the period: its latest measured commit's figure,
  covered and executable lines, each with its change over the period, and the
  chart the selected one switches to. The Code Coverage page shows it for the
  default branch, and a branch's page for its own.
  """
  def coverage_analytics_card(assigns) do
    ~H"""
    <.card
      title={@title || dgettext("dashboard_tests", "Analytics")}
      icon="chart_arcs"
      data-part="analytics"
    >
      <:actions>{render_slot(@actions)}</:actions>
      <div data-part="analytics-content">
        <div :if={@latest} data-part="widgets">
          <.widget
            id="widget-coverage"
            title={dgettext("dashboard_tests", "Code coverage")}
            description={
              dgettext(
                "dashboard_tests",
                "Share of executable lines covered at the latest measured commit of %{branch}, %{sha}, pooled over the schemes that measured it.",
                branch: @branch,
                sha: short_sha(@latest.git_commit_sha)
              )
            }
            value={"#{@latest.coverage}%"}
            legend_color="primary"
            trend_value={@trends["coverage"]}
            trend_label={dgettext("dashboard_tests", "over the period")}
            phx_click="select_widget"
            phx_value_widget="coverage"
            selected={@selected_widget == "coverage"}
          />
          <.widget
            id="widget-coverage-covered-lines"
            title={dgettext("dashboard_tests", "Covered lines")}
            description={
              dgettext(
                "dashboard_tests",
                "Lines that commit's tests ran at least once."
              )
            }
            value={format_number(@latest.covered_lines)}
            legend_color="secondary"
            trend_value={@trends["covered_lines"]}
            trend_label={dgettext("dashboard_tests", "over the period")}
            phx_click="select_widget"
            phx_value_widget="covered_lines"
            selected={@selected_widget == "covered_lines"}
          />
          <.widget
            id="widget-coverage-executable-lines"
            title={dgettext("dashboard_tests", "Executable lines")}
            description={
              dgettext(
                "dashboard_tests",
                "Lines the compiler instrumented for coverage at that commit."
              )
            }
            value={format_number(@latest.executable_lines)}
            legend_color="tertiary"
            trend_value={@trends["executable_lines"]}
            trend_type={:neutral}
            trend_label={dgettext("dashboard_tests", "over the period")}
            phx_click="select_widget"
            phx_value_widget="executable_lines"
            selected={@selected_widget == "executable_lines"}
          />
        </div>
        <.card_section :if={@latest}>
          <div data-part="analytics-chart">
            <.coverage_trend_chart
              id="coverage-chart"
              points={@points}
              metric={@selected_widget}
              grouping={@grouping}
            />
          </div>
        </.card_section>
        <.card_section :if={@details != []} data-part="analytics-details">
          {render_slot(@details)}
        </.card_section>
        <.coverage_empty
          :if={is_nil(@latest)}
          title={
            @empty_title ||
              dgettext("dashboard_tests", "No measured commit on %{branch} in this period",
                branch: @branch
              )
          }
          get_started_href="https://docs.tuist.dev/en/guides/features/tests"
          data-part="empty-analytics"
        />
      </div>
    </.card>
    """
  end

  attr :id, :string, required: true
  attr :points, :list, required: true, doc: "The trend's points, oldest first (`History.branch_points/3`)."

  attr :grouping, :atom, default: nil, doc: "What each point stands for; nil titles points by their date."

  attr :metric, :string,
    default: "coverage",
    values: ~w(coverage covered_lines executable_lines),
    doc: "What the chart plots: the coverage percentage, or one of the counts behind it."

  @doc """
  A branch's coverage over time, one point per chained commit: the chart the
  Code Coverage page and a branch's page lead with. Their widgets switch it
  to one of the counts behind the figure.
  """
  def coverage_trend_chart(assigns) do
    assigns =
      assigns
      |> assign(:unit, if(assigns.metric == "coverage", do: "%", else: ""))
      |> assign(:series_name, metric_label(assigns.metric))
      |> assign(:color, metric_color(assigns.metric))

    ~H"""
    <.chart
      id={@id}
      type="line"
      extra_options={
        %{
          # The last date's label centres on the last point, so the plot
          # leaves room on its right for half of it, as much as the y axis's
          # labels take on the left.
          grid: %{left: "0.4%", right: "24px", height: "88%", top: "5%"},
          xAxis: %{
            boundaryGap: false,
            type: "category",
            axisLabel: %{
              color: "var:noora-surface-label-secondary",
              formatter: "fn:toLocaleDate",
              customValues: [
                @points |> List.first() |> point_time(),
                @points |> List.last() |> point_time()
              ],
              padding: [10, 0, 0, 0]
            }
          },
          yAxis: %{
            splitNumber: 4,
            splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
            axisLabel: %{
              color: "var:noora-surface-label-secondary",
              formatter: "{value}" <> @unit
            }
          },
          legend: %{show: false},
          tooltip: %{valueFormat: "{value}" <> @unit, dateFormat: date_format(@grouping)}
        }
      }
      series={[
        %{
          color: @color,
          data: Enum.map(@points, &[point_time(&1), metric_value(&1, @metric)]),
          name: @series_name,
          type: "line",
          smooth: 0.1,
          symbol: "circle",
          symbolSize: 4
        }
      ]}
      y_axis_min={0}
      y_axis_max={if @metric == "coverage", do: 100}
    />
    """
  end

  defp date_format(:commit), do: "minute"
  defp date_format(grouping) when grouping in [:day, :week, :month], do: Atom.to_string(grouping)
  defp date_format(nil), do: nil

  defp metric_value(point, "coverage"), do: point.coverage
  defp metric_value(point, "covered_lines"), do: point.covered_lines
  defp metric_value(point, "executable_lines"), do: point.executable_lines

  defp metric_label("coverage"), do: dgettext("dashboard_tests", "Code coverage")
  defp metric_label("covered_lines"), do: dgettext("dashboard_tests", "Covered lines")
  defp metric_label("executable_lines"), do: dgettext("dashboard_tests", "Executable lines")

  # Each metric keeps the colour of its widget on the Code Coverage page.
  defp metric_color("coverage"), do: "var:noora-chart-primary"
  defp metric_color("covered_lines"), do: "var:noora-chart-secondary"
  defp metric_color("executable_lines"), do: "var:noora-chart-tertiary"

  attr :summary, :map, required: true, doc: "A commit's summary with its `reported` figure."
  attr :ran_tests_count, :integer, default: 0, doc: "How many tests the commit's runs executed."
  attr :commit_href, :any, required: true, doc: "A commit's page, from its SHA."

  @doc """
  Where a commit's coverage comes from, as one bar over its executable lines:
  what its own runs measured, what was reused from an ancestor for the tests
  they skipped, and the rest, which is unknown when some skipped test could
  not be reused and simply not covered otherwise. What is unknown has no
  line count, so it is counted in tests. It explains the one commit and
  compares nothing.
  """
  def coverage_sources_card(assigns) do
    assigns = assign(assigns, :sources, coverage_sources(assigns.summary))

    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Coverage breakdown")}
      icon="git_commit"
      data-part="sources-card"
    >
      <.card_section data-part="sources-section">
        <.chart
          id="coverage-sources-chart"
          type="bar"
          extra_options={sources_chart_options()}
          series={sources_chart_series(@sources)}
          x_axis_min={0}
          x_axis_max={max(@sources.executable, 1)}
        />
      </.card_section>
      <.card_section data-part="sources-details-section">
        <div data-part="metadata-row">
          <div :if={@ran_tests_count > 0} data-part="metadata">
            <div data-part="title">{dgettext("dashboard_tests", "Tests ran")}</div>
            <span data-part="value">{format_number(@ran_tests_count)}</span>
          </div>
          <div :if={@sources.reused > 0} data-part="metadata">
            <div data-part="title">{dgettext("dashboard_tests", "Skipped tests reused")}</div>
            <span data-part="value">{format_number(@sources.reused)}</span>
          </div>
          <div :if={@sources.carried_from != []} data-part="metadata">
            <div data-part="title">{dgettext("dashboard_tests", "Reused from")}</div>
            <span data-part="value">
              <.git_commit />
              <.link
                :for={sha <- @sources.carried_from}
                navigate={@commit_href.(sha)}
                data-part="commit-link"
              >
                {short_sha(sha)}
              </.link>
            </span>
          </div>
          <div :if={unknown?(@sources)} data-part="metadata">
            <div data-part="title">
              {dgettext("dashboard_tests", "Unknown")}
              <.tooltip
                id="coverage-sources-unknown-tooltip"
                title={dgettext("dashboard_tests", "Unknown")}
                description={sources_note(@sources)}
                size="large"
              >
                <:trigger :let={attrs}>
                  <span {attrs}>
                    <.alert_circle />
                  </span>
                </:trigger>
              </.tooltip>
            </div>
            <span data-part="value">{unknown_caption(@sources)}</span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  @doc """
  Whether a commit's figure needs its coverage broken down: some of it was
  reused from an ancestor, or some of it is unknown (`Commits.confirmed?/1`).
  A commit whose tests all ran here has nothing to break down.
  """
  def coverage_breakdown?(summary) do
    sources = coverage_sources(summary)
    sources.reused_lines > 0 or unknown?(sources)
  end

  @doc """
  A commit's covered lines split by where they come from, and its skipped
  tests by whether their coverage could be reused. Lines reused are the
  reported figure's beyond what the runs measured.
  """
  def coverage_sources(%{reported: %{kind: kind} = reported} = summary) when kind in ~w(reported partial) do
    measured = min(summary.covered_lines, reported.covered_lines)

    %{
      kind: kind,
      confirmed: kind == "reported",
      measured: measured,
      reused_lines: reported.covered_lines - measured,
      uncovered: max(reported.executable_lines - reported.covered_lines, 0),
      executable: reported.executable_lines,
      skipped: reported.skipped_tests_count,
      reused: reported.carried_tests_count,
      unknown: max(reported.skipped_tests_count - reported.carried_tests_count, 0),
      gap_files: reported.gap_files_count,
      carried_from: reported.carried_from
    }
  end

  def coverage_sources(summary) do
    %{
      kind: if(summary[:reported], do: summary.reported.kind, else: "measured"),
      confirmed: Map.get(summary, :partial_schemes, []) == [],
      measured: summary.covered_lines,
      reused_lines: 0,
      uncovered: max(summary.executable_lines - summary.covered_lines, 0),
      executable: summary.executable_lines,
      skipped: 0,
      reused: 0,
      unknown: 0,
      gap_files: 0,
      carried_from: []
    }
  end

  defp unknown?(sources), do: sources.unknown > 0 or sources.gap_files > 0 or not sources.confirmed

  # The stacked bar of the run page's Module Cache tab, over the commit's
  # executable lines.
  defp sources_chart_options do
    %{
      tooltip: %{trigger: "axis", axisPointer: %{type: "none"}},
      legend: %{
        left: "-0.3%",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-primary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{width: "99%", left: "0%", height: "60%", top: "0%"},
      xAxis: %{type: "value", axisLabel: %{show: false}, splitLine: %{show: false}},
      yAxis: %{type: "category", data: [dgettext("dashboard_tests", "Executable lines")], axisLabel: %{show: false}}
    }
  end

  defp sources_chart_series(sources) do
    segments = [
      {dgettext("dashboard_tests", "Covered here"), sources.measured, "var:noora-chart-legend-primary"},
      {dgettext("dashboard_tests", "Reused"), sources.reused_lines, "var:noora-chart-legend-secondary"},
      {if(unknown?(sources),
         do: dgettext("dashboard_tests", "Not covered or unknown"),
         else: dgettext("dashboard_tests", "Not covered")
       ), sources.uncovered, "var:coverage-chart-uncovered"}
    ]

    present = segments |> Enum.with_index() |> Enum.filter(fn {{_name, lines, _color}, _index} -> lines > 0 end)
    first = present |> List.first({nil, nil}) |> elem(1)
    last = present |> List.last({nil, nil}) |> elem(1)

    segments
    |> Enum.with_index()
    |> Enum.map(fn {{name, lines, color}, index} ->
      %{
        name: name,
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [lines],
        color: color,
        itemStyle: %{
          borderRadius: [
            if(index == first, do: 5, else: 0),
            if(index == last, do: 5, else: 0),
            if(index == last, do: 5, else: 0),
            if(index == first, do: 5, else: 0)
          ]
        }
      }
    end)
  end

  defp unknown_caption(%{unknown: 0, gap_files: 0}), do: dgettext("dashboard_tests", "Skipped tests not listed")

  defp unknown_caption(%{unknown: unknown, gap_files: 0}),
    do:
      dngettext("dashboard_tests", "%{count} skipped test not reused", "%{count} skipped tests not reused", unknown,
        count: unknown
      )

  defp unknown_caption(%{unknown: 0, gap_files: files}),
    do:
      dngettext(
        "dashboard_tests",
        "%{count} changed file no run compiled",
        "%{count} changed files no run compiled",
        files, count: files)

  defp unknown_caption(%{unknown: unknown, gap_files: files}),
    do:
      dgettext("dashboard_tests", "%{tests} · %{files}",
        tests: unknown_caption(%{unknown: unknown, gap_files: 0}),
        files: unknown_caption(%{unknown: 0, gap_files: files})
      )

  # Why part of the figure is unknown, until the fold records the reason per
  # commit: the conditions a skipped test's coverage has to meet to be reused.
  defp sources_note(%{kind: "partial", unknown: unknown}) when unknown > 0 do
    dgettext(
      "dashboard_tests",
      "Only the confirmed part is shown: the coverage of %{count} skipped tests could not be carried forward, so the lines they cover are not counted. A skipped test's coverage is carried forward only from an ancestor where it ran with coverage attribution and passed, and only while the code it executed there and the tracked files are unchanged.",
      count: unknown
    )
  end

  defp sources_note(%{kind: "partial"}),
    do:
      dgettext(
        "dashboard_tests",
        "Only the confirmed part is shown: files no run compiled here changed since they were last measured, so their lines are not counted."
      )

  defp sources_note(%{confirmed: false}),
    do:
      dgettext(
        "dashboard_tests",
        "Only the confirmed part is shown: some schemes ran selectively and the runs did not list the tests they could have run, so what the skipped tests cover is not counted."
      )

  defp sources_note(_sources), do: nil
end
