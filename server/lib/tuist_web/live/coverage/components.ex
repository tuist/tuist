defmodule TuistWeb.Coverage.Components do
  @moduledoc """
  The cells and words the coverage pages share: a file's coverage as a bar,
  a difference in percentage points, the schemes that measured a commit, and
  the labels that word a commit's completeness, a gate's verdict and the
  reasons a comparison could not be made.
  """
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Tests.Coverage

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

  attr :least_covered, :list, required: true
  attr :file_href, :any, default: nil
  attr :unmeasured, :list, required: true
  attr :unmeasured_count, :integer, default: 0
  attr :href, :string, required: true

  @doc """
  Where the commit's files are thinnest, and which of them have no coverage
  data, with the way to every file behind it.
  """
  def files_coverage_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Files coverage")}
      icon="file"
      data-part="files-coverage"
    >
      <:actions>
        <.button
          label={dgettext("dashboard_tests", "View more")}
          variant="secondary"
          size="medium"
          navigate={@href}
        />
      </:actions>
      <div data-part="movements-sections">
        <.card_section data-part="movement-section">
          <div data-part="header">
            <span data-part="title">{dgettext("dashboard_tests", "Least covered files")}</span>
          </div>
          <.table
            :if={@least_covered != []}
            id="coverage-gap-files-table"
            rows={@least_covered}
            row_navigate={@file_href && fn file -> @file_href.(file.path) end}
          >
            <:col :let={file} label={dgettext("dashboard_tests", "File")}>
              <.text_and_description_cell
                label={Path.basename(file.path)}
                description={parent_dir(file.path)}
              />
            </:col>
            <:col :let={file} label={dgettext("dashboard_tests", "Coverage")}>
              <.coverage_cell covered={file.covered_lines} executable={file.executable_lines} />
            </:col>
          </.table>
          <div :if={@least_covered == []} data-part="empty">
            {dgettext("dashboard_tests", "No file was measured at this commit.")}
          </div>
        </.card_section>
        <.card_section data-part="movement-section">
          <div data-part="header">
            <span data-part="title">{dgettext("dashboard_tests", "Files without coverage data")}</span>
            <span :if={@unmeasured_count > 0} data-part="count">
              {dgettext("dashboard_tests", "%{count} in total",
                count: format_number(@unmeasured_count)
              )}
            </span>
          </div>
          <.table :if={@unmeasured != []} id="coverage-unmeasured-files-table" rows={@unmeasured}>
            <:col :let={file} label={dgettext("dashboard_tests", "File")}>
              <.text_and_description_cell
                label={Path.basename(file.path)}
                description={parent_dir(file.path)}
              />
            </:col>
          </.table>
          <div :if={@unmeasured == []} data-part="empty">
            {dgettext("dashboard_tests", "Every file Git tracks at this commit has coverage data.")}
          </div>
        </.card_section>
      </div>
    </.card>
    """
  end

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

  attr :partial, :boolean, default: nil

  @doc "Whether a run measured every test (Full) or selective testing left some out (Partial); nil for no run."
  def run_kind_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={not is_nil(@partial)}
      title={
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
      style="light-fill"
      color={if @partial, do: "warning", else: "success"}
      label={
        if @partial,
          do: dgettext("dashboard_tests", "Partial"),
          else: dgettext("dashboard_tests", "Full")
      }
    />
    <.text_cell :if={is_nil(@partial)} label="—" />
    """
  end

  attr :commit, :map, required: true

  # The schemes that measured a commit, the partial ones marked. Past two, the
  # rest fold into a count, as a run's tags do on the Build Runs page.
  def measured_by_cell(assigns) do
    schemes = assigns.commit.schemes
    {shown, folded} = if length(schemes) > 2, do: Enum.split(schemes, 1), else: {schemes, []}
    assigns = assigns |> assign(:shown, shown) |> assign(:folded, folded)

    ~H"""
    <div data-part="cell" data-type="badge">
      <div data-part="tags">
        <.badge
          :for={scheme <- @shown}
          style="light-fill"
          size="large"
          color={if scheme in @commit.partial_schemes, do: "warning", else: "neutral"}
          label={if scheme in @commit.partial_schemes, do: "#{scheme} · P", else: scheme}
        />
        <.badge
          :if={@folded != []}
          style="light-fill"
          size="large"
          color={
            if Enum.any?(@folded, &(&1 in @commit.partial_schemes)), do: "warning", else: "neutral"
          }
          label={"+#{length(@folded)}"}
          title={Enum.join(@folded, ", ")}
        />
      </div>
    </div>
    """
  end

  @doc false
  def short_sha(sha), do: String.slice(sha || "", 0, 7)

  @doc """
  The figure a commit is shown with: its reported coverage when everything its
  runs skipped was carried forward (what a full run would measure), and what
  the runs measured otherwise.
  """
  def displayed_coverage(%{reported: %{kind: "reported", coverage: coverage}}), do: coverage
  def displayed_coverage(%{coverage: coverage}), do: coverage

  @doc "The line totals behind `displayed_coverage/1`, from a commit's published summary (nil when there is none)."
  def displayed_lines(%{
        reported_kind: "reported",
        reported_covered_lines: covered,
        reported_executable_lines: executable
      }), do: %{covered_lines: covered, executable_lines: executable}

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

  @doc false
  def completeness_label(%{measured: false}), do: dgettext("dashboard_tests", "Not measured")
  def completeness_label(%{complete: true, completeness: "signal"}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{complete: true}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{chained: true}), do: dgettext("dashboard_tests", "Comparable")
  def completeness_label(_commit), do: dgettext("dashboard_tests", "Not chained")

  @doc "What a commit's status in a list means, for the status's title."
  def completeness_title(%{measured: false}),
    do: dgettext("dashboard_tests", "No run of this commit gathered coverage, so it has no figure of its own.")

  def completeness_title(%{complete: true}),
    do:
      dgettext(
        "dashboard_tests",
        "The commit's coverage pipeline signalled it finished, so no more runs are expected and its figure is final."
      )

  def completeness_title(%{chained: true}),
    do:
      dgettext(
        "dashboard_tests",
        "Measured the same schemes, each as fully, as the commit before it on the trend, so the two compare as a whole. More runs may still land."
      )

  def completeness_title(_commit),
    do:
      dgettext(
        "dashboard_tests",
        "Measured a different set of schemes than the commit before it on the trend, so it only compares scheme by scheme and stays off the chart."
      )

  @doc false
  def completeness_color(%{measured: false}), do: "neutral"
  def completeness_color(%{complete: true}), do: "success"
  def completeness_color(%{chained: true}), do: "information"
  def completeness_color(_commit), do: "neutral"

  @doc """
  When a point of a coverage series happened, for the chart's axis: the commit's
  own time, or when it was measured where Git's history has none. Never when
  its totals were stored, which moves every time they are recomputed.
  """
  def point_time(point) do
    case Map.get(point, :committed_at) || Map.get(point, :ran_at) || point.inserted_at do
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
  """
  def coverage_file_href(account_name, project_name, path, scope) do
    query =
      Enum.flat_map([commit: "commit", tab: "tab"], fn {key, name} ->
        case Map.get(scope, key) do
          value when value in [nil, ""] -> []
          value -> [{name, value}]
        end
      end)

    "/#{account_name}/#{project_name}/tests/coverage/files/#{encode_path(path)}?" <> URI.encode_query(query)
  end

  @doc false
  def encode_path(path), do: path |> String.split("/") |> Enum.map_join("/", &encode_segment/1)

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  attr :file, :map, required: true, doc: "A file's detail, from `Commits.file_detail/4`."

  @doc """
  One file's coverage: its figures, the targets that compiled it, the lines
  no test ran and its functions.
  """
  def coverage_file_view(assigns) do
    assigns =
      assign(
        assigns,
        :functions,
        assigns.file |> Map.get(:functions, []) |> Enum.with_index() |> Enum.map(fn {f, i} -> Map.put(f, :id, i) end)
      )

    ~H"""
    <.card title={dgettext("dashboard_tests", "Coverage")} icon="file" data-part="file-summary-card">
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
        <dl data-part="file-details">
          <div :if={@file.targets != []}>
            <dt>{dgettext("dashboard_tests", "Targets")}</dt>
            <dd id="coverage-file-targets">
              <ul data-part="targets">
                <li :for={target <- @file.targets}>
                  <.badge label={target} color="neutral" style="light-fill" size="large" />
                </li>
              </ul>
            </dd>
          </div>
          <div>
            <dt>{dgettext("dashboard_tests", "Uncovered lines")}</dt>
            <dd id="coverage-file-uncovered-lines" title={full_line_ranges(@file.uncovered_ranges)}>
              {case @file.uncovered_ranges do
                nil -> dgettext("dashboard_tests", "Unavailable")
                [] -> dgettext("dashboard_tests", "None")
                ranges -> brief_line_ranges(ranges)
              end}
            </dd>
          </div>
          <div :if={Map.get(@file, :carried_lines, []) != []}>
            <dt>{dgettext("dashboard_tests", "Covered by skipped tests, carried forward")}</dt>
            <dd
              id="coverage-file-carried-lines"
              title={full_line_ranges(Coverage.Evidence.line_ranges(@file.carried_lines))}
            >
              {brief_line_ranges(Coverage.Evidence.line_ranges(@file.carried_lines))}
            </dd>
          </div>
          <div :if={Map.get(@file, :git_blob_id, "") not in [nil, ""]}>
            <dt>{dgettext("dashboard_tests", "Git blob")}</dt>
            <dd><code>{@file.git_blob_id}</code></dd>
          </div>
        </dl>
      </.card_section>
    </.card>

    <.card
      :if={@functions != []}
      title={dgettext("dashboard_tests", "Functions")}
      icon="list_tree"
      data-part="file-functions-card"
    >
      <.card_section data-part="file-functions-section">
        <.table id="coverage-functions-table" rows={@functions}>
          <:col :let={function} label={dgettext("dashboard_tests", "Function")}>
            <.text_cell label={function.name} />
          </:col>
          <:col :let={function} label={dgettext("dashboard_tests", "Line")}>
            <.text_cell label={Integer.to_string(function.line_number)} />
          </:col>
          <:col :let={function} label={dgettext("dashboard_tests", "Executions")}>
            <.text_cell label={format_number(function.execution_count)} />
          </:col>
          <:col :let={function} label={dgettext("dashboard_tests", "Coverage")}>
            <.text_cell
              :if={is_nil(function.covered_lines)}
              label={dgettext("dashboard_tests", "Unavailable")}
            />
            <.coverage_cell
              :if={function.covered_lines}
              covered={function.covered_lines}
              executable={function.executable_lines}
            />
          </:col>
        </.table>
      </.card_section>
    </.card>
    """
  end

  attr :id, :string, default: "coverage-files-table"

  attr :rows, :list, required: true, doc: "Files with `path`, `covered_lines` and `executable_lines`."

  attr :file_href, :any, required: true, doc: "A file's page, from its path."
  attr :meta, :map, required: true, doc: "`current_page` and `total_pages`."
  attr :page_patch, :any, required: true

  @doc """
  A list of files, each opening on its own page with its coverage.
  """
  def coverage_files_table(assigns) do
    ~H"""
    <div data-part="files-table">
      <.table id={@id} rows={@rows} row_navigate={fn file -> @file_href.(file.path) end}>
        <:col :let={file} label={dgettext("dashboard_tests", "File")}>
          <.text_and_description_cell
            label={Path.basename(file.path)}
            description={parent_dir(file.path)}
          />
        </:col>
        <:col :let={file} label={dgettext("dashboard_tests", "File coverage")}>
          <.coverage_cell covered={file.covered_lines} executable={file.executable_lines} />
        </:col>
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
  attr :points, :list, required: true, doc: "The trend's points, oldest first (`History.branch_points/3`)."

  attr :metric, :string,
    default: "coverage",
    values: ~w(coverage covered_lines executable_lines unmeasured_files),
    doc: "What the chart plots: the coverage percentage, or one of the counts behind it."

  @doc """
  A branch's coverage over time, one point per chained commit: the chart the
  Code Coverage page leads with, and the project's overview repeats. The
  Code Coverage page's widgets switch it to one of the counts behind the
  figure.
  """
  def coverage_trend_chart(assigns) do
    assigns =
      assigns
      |> assign(:unit, if(assigns.metric == "coverage", do: "%", else: ""))
      |> assign(:series_name, metric_label(assigns.metric))

    ~H"""
    <.chart
      id={@id}
      type="line"
      extra_options={
        %{
          # The last date's label centres on the last point, so the plot
          # leaves room on its right for it.
          grid: %{width: "93%", left: "0.4%", height: "88%", top: "5%"},
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
          tooltip: %{valueFormat: "{value}" <> @unit}
        }
      }
      series={[
        %{
          color: "var:noora-chart-primary",
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

  defp metric_value(point, "coverage"), do: point.coverage
  defp metric_value(point, "covered_lines"), do: point.covered_lines
  defp metric_value(point, "executable_lines"), do: point.executable_lines
  defp metric_value(point, "unmeasured_files"), do: Map.get(point, :unmeasured_files_count) || 0

  defp metric_label("coverage"), do: dgettext("dashboard_tests", "Code coverage")
  defp metric_label("covered_lines"), do: dgettext("dashboard_tests", "Covered lines")
  defp metric_label("executable_lines"), do: dgettext("dashboard_tests", "Executable lines")
  defp metric_label("unmeasured_files"), do: dgettext("dashboard_tests", "Files without coverage data")
end
