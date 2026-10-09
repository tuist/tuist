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
  alias TuistWeb.Utilities.Query

  attr :branch, :string, required: true
  attr :branches, :list, required: true, doc: "The branches to pick among (`History.branches/2`)."
  attr :uri, URI, required: true
  attr :preset, :string, required: true
  attr :period, :any, required: true

  @doc """
  The branch dropdown and the period picker the Code Coverage page leads
  with. Picking a branch keeps the rest of the query but
  its cursor, which only means something within one branch; the period
  picker sends `coverage_period_changed`.
  """
  def coverage_filters(assigns) do
    ~H"""
    <div data-part="filters">
      <.dropdown
        id="coverage-branch-dropdown"
        label={@branch}
        secondary_text={dgettext("dashboard_tests", "Branch:")}
      >
        <:search>
          <input
            type="text"
            placeholder={dgettext("dashboard_tests", "Search...")}
            data-part="search-input"
          />
        </:search>
        <.dropdown_item
          :for={branch <- @branches}
          value={branch}
          label={branch}
          patch={"?#{@uri.query |> Query.put("branch", branch) |> Query.drop("after") |> Query.drop("before")}"}
          data-selected={@branch == branch}
        >
          <:right_icon :if={@branch == branch}><.check /></:right_icon>
        </.dropdown_item>
      </.dropdown>
      <.coverage_period_picker
        id="coverage-date-range-picker"
        selected_preset={@preset}
        period={@period}
      />
    </div>
    """
  end

  @doc """
  `path` with the query the Code Coverage page and a file's page share: the
  branch and the period, so moving between them keeps both.
  """
  def with_shared_query(path, params) do
    case Map.filter(params, fn {key, _value} -> key == "branch" or String.starts_with?(key, "coverage-") end) do
      shared when map_size(shared) == 0 -> path
      shared -> path <> "?" <> URI.encode_query(shared)
    end
  end

  @doc "The branch a page describes: the one `branch` names, or the project's default branch."
  def selected_branch(branch, _project) when is_binary(branch) and branch != "", do: branch
  def selected_branch(_branch, project), do: project.default_branch

  attr :files, :list,
    required: true,
    doc:
      "The files that moved most, `%{name, detail, covered_lines, executable_lines, change}`, with an `href` when they open a page; more than four stacks the rest."

  attr :targets, :list, required: true, doc: "The targets that moved most, as `files`."
  attr :files_href, :string, required: true, doc: "Where the files' View more leads."
  attr :targets_href, :string, required: true, doc: "Where the targets' View more leads."
  attr :targets_title, :string, required: true, doc: "What the project's build system calls the targets."
  attr :empty_title, :string, required: true
  attr :rest, :global

  @doc """
  The files and targets whose coverage moved most, side by side as the Tests
  page's Test Cases card lays out its two lists: up to four cards each, led
  by the umbrella coloured by direction, the edges of more stacked behind
  the last when there are more.
  """
  def coverage_changes_card(assigns) do
    ~H"""
    <.card title={dgettext("dashboard_tests", "Coverage Changes")} icon="umbrella" {@rest}>
      <div :if={@files != [] or @targets != []} data-part="changes-sections">
        <.card_section
          :for={
            {side, title, items, href} <- [
              {"files", dgettext("dashboard_tests", "Files"), @files, @files_href},
              {"targets", @targets_title, @targets, @targets_href}
            ]
          }
          data-part="changes-section"
          data-side={side}
        >
          <div data-part="header">
            <span data-part="title">{title}</span>
            <.button
              :if={items != []}
              variant="secondary"
              label={dgettext("dashboard_tests", "View more")}
              size="small"
              navigate={href}
              data-part="view-more"
            />
          </div>
          <div :if={items != []} data-part="changes-list">
            <%= for item <- Enum.take(items, 4) do %>
              <.link
                :if={Map.get(item, :href)}
                navigate={item.href}
                class="coverage-change-card"
                data-direction={direction(item.change)}
              >
                <.change_item item={item} />
              </.link>
              <div
                :if={is_nil(Map.get(item, :href))}
                class="coverage-change-card"
                data-direction={direction(item.change)}
              >
                <.change_item item={item} />
              </div>
            <% end %>
            <div :if={length(items) > 4} data-part="more-card" data-index="two"></div>
            <div :if={length(items) > 4} data-part="more-card" data-index="one"></div>
          </div>
          <span :if={items == []} data-part="empty">
            {dgettext("dashboard_tests", "No coverage change")}
          </span>
        </.card_section>
      </div>
      <.coverage_empty
        :if={@files == [] and @targets == []}
        title={@empty_title}
        image="table"
        data-part="empty-changes"
      />
    </.card>
    """
  end

  defp direction(change) when change < 0, do: "down"
  defp direction(_change), do: "up"

  attr :item, :map, required: true

  defp change_item(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="icon">
        <.icon name="umbrella" />
      </div>
      <div data-part="title-and-subtitle">
        <h3 data-part="title">{@item.name}</h3>
        <span :if={@item.detail} data-part="subtitle">{@item.detail}</span>
      </div>
      <span data-part="coverage">
        {Coverage.percentage(@item.covered_lines, @item.executable_lines)}%
      </span>
      <.badge
        label={"#{signed(@item.change)}%"}
        color={change_color(@item.change)}
        style="light-fill"
        size="small"
        data-part="change"
      />
    </div>
    """
  end

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

  defp change_color(delta) when delta < 0, do: "destructive"
  defp change_color(delta) when delta > 0, do: "success"
  defp change_color(_delta), do: "neutral"

  defp signed(delta) when delta > 0, do: "+#{delta}"
  defp signed(delta), do: "#{delta}"

  attr :delta, :float, default: nil, doc: "Percentage points moved since the complete commit before, or nil for none."

  @doc "How far a commit moved coverage, coloured by direction; a dash when there is nothing to compare with."
  def change_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@delta}
      style="light-fill"
      color={change_color(@delta)}
      label={"#{signed(@delta)}%"}
    />
    <.text_cell :if={is_nil(@delta)} label="—" />
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

  attr :id, :string, required: true
  attr :partial, :boolean, default: nil
  attr :dirty, :boolean, default: false

  @doc """
  Whether a run measured every test (Full) or selective testing left some out
  (Partial), or, for a run from a dirty checkout, that its coverage was
  discarded;
  nil for no run.
  """
  def run_kind_cell(assigns) do
    ~H"""
    <.tooltip_badge_cell
      :if={@dirty}
      id={@id}
      label={dgettext("dashboard_tests", "Discarded")}
      color="warning"
      description={
        dgettext(
          "dashboard_tests",
          "The run came from a checkout with uncommitted changes, so it measured code that isn't the commit's and its coverage was discarded."
        )
      }
    />
    <.tooltip_badge_cell
      :if={not @dirty and not is_nil(@partial)}
      id={@id}
      label={
        if @partial,
          do: dgettext("dashboard_tests", "Partial"),
          else: dgettext("dashboard_tests", "Full")
      }
      color="neutral"
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
  coverage page (the `from` parameter the links out of a branch or a commit
  carry): that page, named for what it is. Nil when
  `from` is missing or points anywhere but the project's coverage pages.
  """
  def back_to(nil, _account_name, _project_name), do: nil

  def back_to(from, account_name, project_name) do
    base = "/#{account_name}/#{project_name}/tests/coverage"
    %URI{path: path, scheme: scheme, host: host} = URI.parse(from)

    if is_nil(scheme) and is_nil(host) and is_binary(path) and (path == base or String.starts_with?(path, base <> "/")) and
         not String.contains?(from, ["//", "\\"]) do
      %{label: path |> String.replace_prefix(base, "") |> String.split("/", trim: true) |> back_label(), href: from}
    end
  end

  defp back_label(["branches" | branch]) when branch != [],
    do: dgettext("dashboard_tests", "Branch %{name}", name: Enum.map_join(branch, "/", &URI.decode/1))

  defp back_label(["commits", sha]), do: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha))
  defp back_label(_path), do: dgettext("dashboard_tests", "Code Coverage")

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

  @doc "The line totals behind `displayed_coverage/1`, from a commit's published summary (nil when there is none)."
  def displayed_lines(%{reported_kind: kind, reported_covered_lines: covered, reported_executable_lines: executable})
      when kind in ~w(reported partial), do: %{covered_lines: covered, executable_lines: executable}

  def displayed_lines(%{covered_lines: covered, executable_lines: executable}),
    do: %{covered_lines: covered, executable_lines: executable}

  def displayed_lines(_summary), do: %{covered_lines: 0, executable_lines: 0}

  @doc """
  What the page says about a commit whose figure is incomplete
  (`Tuist.Tests.Coverage.Commits.incomplete?/1`).
  """
  def incomplete_title(commit) do
    if :dirty_run_excluded in Commits.gap_reasons(commit),
      do:
        dgettext(
          "dashboard_tests",
          "Some coverage only came from runs on a checkout with uncommitted changes, which don't count, so the actual coverage may be higher."
        ),
      else: skipped_title(commit)
  end

  defp skipped_title(%{reported_kind: kind, skipped_tests_count: skipped, carried_tests_count: carried})
       when kind in ~w(observed partial) and skipped > carried do
    dngettext(
      "dashboard_tests",
      "Some tests were skipped, and the coverage of %{count} of them couldn't be determined, so the actual coverage may be higher.",
      "Some tests were skipped, and the coverage of %{count} of them couldn't be determined, so the actual coverage may be higher.",
      skipped - carried,
      count: skipped - carried
    )
  end

  defp skipped_title(_commit),
    do:
      dgettext(
        "dashboard_tests",
        "Some tests were skipped, and their coverage couldn't be fully determined, so the actual coverage may be higher."
      )

  @doc """
  A commit's status (`Tuist.Tests.Coverage.Commits.status/1`), in a list or
  on its own page: `Not measured`, `In Progress`, `Incomplete` or `Complete`.
  """
  def commit_status_label(commit) do
    case Commits.status(commit) do
      :not_measured -> dgettext("dashboard_tests", "Not measured")
      :in_progress -> dgettext("dashboard_tests", "In Progress")
      :incomplete -> dgettext("dashboard_tests", "Incomplete")
      :complete -> dgettext("dashboard_tests", "Complete")
    end
  end

  @doc "What a commit's status means, for the status's tooltip."
  def commit_status_title(commit) do
    case Commits.status(commit) do
      :not_measured ->
        dgettext("dashboard_tests", "No run of this commit gathered coverage, so it has no figure of its own.")

      :in_progress ->
        dgettext(
          "dashboard_tests",
          "This commit's coverage pipeline has not signalled completion yet, so more runs may still land and its gates wait."
        )

      :incomplete ->
        incomplete_title(commit)

      :complete ->
        dgettext(
          "dashboard_tests",
          "This commit's coverage pipeline signalled it finished, so its figure is final and its gates are decided."
        )
    end
  end

  def commit_status_color(commit) do
    case Commits.status(commit) do
      :in_progress -> "information"
      :complete -> "success"
      _status -> "neutral"
    end
  end

  @doc """
  When a point of a coverage series happened, for the chart's axis: the start
  of the day, week or month it stands for when grouped, otherwise the commit's
  own time.
  """
  def point_time(point) do
    case Map.get(point, :period) || point.committed_at do
      %DateTime{} = at -> DateTime.to_iso8601(at)
      at -> NaiveDateTime.to_iso8601(at)
    end
  end

  @doc """
  How far coverage moved from a series' first point to its last, in
  percentage points: no change for a single point, nil for no point at all.
  """
  def period_trend([]), do: nil

  def period_trend([first | _] = series) do
    last = List.last(series)
    if is_number(first.coverage) and is_number(last.coverage), do: Float.round(last.coverage - first.coverage, 1)
  end

  @doc """
  How much a count moved from a series' first point to its last, as a
  percentage of the first: no change for a single point or a count that
  stayed at zero, and the whole of it (100%) for one that grew from zero,
  which has no share of zero to read; nil for no point at all.
  """
  def count_trend([], _field), do: nil

  def count_trend([first | _] = series, field) do
    from = Map.get(first, field) || 0
    to = Map.get(List.last(series), field) || 0

    cond do
      from > 0 -> Float.round((to - from) / from * 100, 1)
      to > 0 -> 100.0
      true -> 0.0
    end
  end

  @doc "The directory a file sits in, or nil for one at the repository's root."
  def parent_dir(path) do
    case Path.dirname(path) do
      "." -> nil
      dir -> dir
    end
  end

  @brief_ranges 2

  @doc "Line ranges (`[first, last]`) as `3–5, 9`; a dash for none."
  def line_ranges_label(ranges) when ranges in [nil, []], do: "—"

  def line_ranges_label(ranges) do
    Enum.map_join(ranges, ", ", fn
      [line, line] -> Integer.to_string(line)
      [first, last] -> "#{first}–#{last}"
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
  Where a file's own page lives, on `branch` over the period the `params`
  carry (their `coverage-*` keys), leading back to `from`.
  """
  def coverage_file_href(account_name, project_name, path, {:commit, sha}, from) do
    "/#{account_name}/#{project_name}/tests/coverage/files/#{encode_path(path)}?" <>
      URI.encode_query(%{"commit" => sha, "from" => from})
  end

  def coverage_file_href(account_name, project_name, path, branch, params, from) do
    period = Map.filter(params, fn {key, _value} -> String.starts_with?(key, "coverage-") end)

    "/#{account_name}/#{project_name}/tests/coverage/files/#{encode_path(path)}?" <>
      URI.encode_query(Map.merge(period, %{"branch" => branch, "from" => from}))
  end

  @doc false
  def encode_path(path), do: path |> String.split("/") |> Enum.map_join("/", &encode_segment/1)

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  attr :file, :map, required: true, doc: "A file's detail, from `Commits.file_detail/4`."
  attr :branch, :string, default: nil

  attr :trend, :map,
    default: nil,
    doc: """
    On a branch, the file's figures at its latest complete commit in the
    period and its coverage over the period: `latest`, `points`, `grouping`,
    `trends` and `selected_widget`, as `coverage_analytics_card/1` takes
    them; nil at one commit, which shows its figures alone.
    """

  @doc """
  One file's coverage, on a branch over a period (its figures and trend) or
  at one commit (its figures), with the lines skipped tests' coverage was
  carried into. Its page lists the functions under it.
  """
  def coverage_file_view(%{trend: nil} = assigns) do
    assigns = assign(assigns, :functions, Map.get(assigns.file, :functions, []))

    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Analytics")}
      icon="chart_arcs"
      data-part="file-summary-card"
    >
      <.card_section data-part="file-summary-section">
        <div data-part="widgets">
          <.widget
            id="widget-coverage-file-percentage"
            title={dgettext("dashboard_tests", "Code Coverage")}
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

  def coverage_file_view(assigns) do
    ~H"""
    <.coverage_analytics_card
      branch={@branch}
      latest={@trend.latest}
      trends={@trend.trends}
      points={@trend.points}
      grouping={@trend.grouping}
      selected_widget={@trend.selected_widget}
    >
      <:details :if={Map.get(@file, :carried_lines, []) != []}>
        <.carried_lines lines={@file.carried_lines} />
      </:details>
    </.coverage_analytics_card>
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

  attr :file_href, :any, default: nil, doc: "A file's page, from its path; nil when the files open nothing."
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
      <.table
        id={@id}
        rows={@rows}
        row_navigate={if @file_href, do: fn file -> @file_href.(file.path) end}
      >
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

  attr :grouping, :atom,
    required: true,
    doc: "What each point stands for (`History.trend_points/3`): a commit, or a day, week or month; the tooltip names it."

  attr :point_href, :any, default: nil, doc: "The page a chart point opens, from the point; nil when points open nothing."

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
      title={dgettext("dashboard_tests", "Analytics")}
      icon="chart_arcs"
      data-part="analytics"
    >
      <:actions>{render_slot(@actions)}</:actions>
      <div data-part="analytics-content">
        <div :if={@latest} data-part="widgets">
          <.widget
            id="widget-coverage"
            title={dgettext("dashboard_tests", "Code Coverage")}
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
              point_href={@point_href}
            />
          </div>
        </.card_section>
        <.card_section :if={@details != []} data-part="analytics-details">
          {render_slot(@details)}
        </.card_section>
        <.coverage_empty
          :if={is_nil(@latest)}
          title={
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
  attr :points, :list, required: true, doc: "The trend's points, oldest first (`History.trend_points/3`)."

  attr :grouping, :atom, required: true, doc: "What each point stands for."
  attr :point_href, :any, default: nil, doc: "The page a point opens when clicked, from the point."

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
          data: Enum.map(@points, &chart_point(&1, @metric, @point_href)),
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

  defp chart_point(point, metric, nil), do: [point_time(point), metric_value(point, metric)]

  defp chart_point(point, metric, href), do: %{value: [point_time(point), metric_value(point, metric)], url: href.(point)}

  defp date_format(:commit), do: "minute"
  defp date_format(grouping) when grouping in [:day, :week, :month], do: Atom.to_string(grouping)

  defp metric_value(point, "coverage"), do: point.coverage
  defp metric_value(point, "covered_lines"), do: point.covered_lines
  defp metric_value(point, "executable_lines"), do: point.executable_lines

  defp metric_label("coverage"), do: dgettext("dashboard_tests", "Code Coverage")
  defp metric_label("covered_lines"), do: dgettext("dashboard_tests", "Covered lines")
  defp metric_label("executable_lines"), do: dgettext("dashboard_tests", "Executable lines")

  # Each metric keeps the colour of its widget on the Code Coverage page.
  defp metric_color("coverage"), do: "var:noora-chart-primary"
  defp metric_color("covered_lines"), do: "var:noora-chart-secondary"
  defp metric_color("executable_lines"), do: "var:noora-chart-tertiary"
end
