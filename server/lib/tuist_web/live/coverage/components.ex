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

  @movers_limit 5

  @doc """
  The rows that moved most in one direction against the baseline, largest
  first: what a card highlights rather than lists. A row that did not move,
  or has nothing to compare with, is not a highlight. Targets are named and
  files are paths; both read as a name here.
  """
  def movers(rows, direction, prefix) do
    rows
    |> Enum.filter(&(is_float(&1.delta) and moved?(&1.delta, direction)))
    |> Enum.sort_by(& &1.delta, direction)
    |> Enum.take(@movers_limit)
    |> Enum.map(fn row ->
      name = Map.get(row, :name) || Map.fetch!(row, :path)
      row |> Map.put(:name, name) |> Map.put(:id, prefix <> "-" <> name)
    end)
  end

  defp moved?(delta, :desc), do: delta > 0
  defp moved?(delta, :asc), do: delta < 0

  attr :rises, :list, required: true
  attr :falls, :list, required: true
  attr :baseline, :map, default: nil
  attr :baseline_reason, :map, default: nil
  attr :href, :string, required: true

  @doc """
  Where the commit's targets moved against its baseline, with the way to
  every target behind it. The project's page and a subject's overview show
  the same card.
  """
  def targets_coverage_card(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_tests", "Targets coverage")}
      icon="stack_2"
      data-part="targets-coverage"
    >
      <:actions>
        <.button
          label={dgettext("dashboard_tests", "View more")}
          variant="secondary"
          size="medium"
          navigate={@href}
        />
      </:actions>
      <.card_section :if={is_nil(@baseline)} data-part="movements-empty">
        <div data-part="empty">
          {dgettext("dashboard_tests", "Nothing to compare with: %{reason}.",
            reason: reason_label(@baseline_reason)
          )}
        </div>
      </.card_section>
      <div :if={@baseline} data-part="movements-sections">
        <.movement_section
          id="target-rises"
          title={dgettext("dashboard_tests", "Targets that rose most")}
          rows={@rises}
          empty={dgettext("dashboard_tests", "No target rose.")}
          label={dgettext("dashboard_tests", "Target")}
        />
        <.movement_section
          id="target-falls"
          title={dgettext("dashboard_tests", "Targets that fell most")}
          rows={@falls}
          empty={dgettext("dashboard_tests", "No target fell.")}
          label={dgettext("dashboard_tests", "Target")}
        />
      </div>
    </.card>
    """
  end

  attr :rises, :list, required: true
  attr :falls, :list, required: true
  attr :least_covered, :list, required: true
  attr :unmeasured, :list, required: true
  attr :unmeasured_count, :integer, default: 0
  attr :baseline, :map, default: nil
  attr :baseline_reason, :map, default: nil
  attr :href, :string, required: true

  @doc """
  Where the commit's files moved, where they are thinnest, and which of them
  nothing measured, with the way to every file behind it.
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
      <.card_section :if={is_nil(@baseline)} data-part="movements-empty">
        <div data-part="empty">
          {dgettext("dashboard_tests", "Nothing to compare with: %{reason}.",
            reason: reason_label(@baseline_reason)
          )}
        </div>
      </.card_section>
      <div :if={@baseline} data-part="movements-sections">
        <.movement_section
          id="file-rises"
          title={dgettext("dashboard_tests", "Files that rose most")}
          rows={@rises}
          empty={dgettext("dashboard_tests", "No file rose.")}
          label={dgettext("dashboard_tests", "File")}
        />
        <.movement_section
          id="file-falls"
          title={dgettext("dashboard_tests", "Files that fell most")}
          rows={@falls}
          empty={dgettext("dashboard_tests", "No file fell.")}
          label={dgettext("dashboard_tests", "File")}
        />
      </div>
      <div data-part="movements-sections">
        <.card_section data-part="movement-section">
          <div data-part="header">
            <span data-part="title">{dgettext("dashboard_tests", "Least covered files")}</span>
          </div>
          <.table :if={@least_covered != []} id="coverage-gap-files-table" rows={@least_covered}>
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
            <span data-part="title">{dgettext("dashboard_tests", "Files nothing measured")}</span>
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
            {dgettext("dashboard_tests", "Every file Git knows at this commit was measured.")}
          </div>
        </.card_section>
      </div>
    </.card>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :label, :string, required: true
  attr :empty, :string, required: true
  attr :rows, :list, required: true

  @doc """
  One side of a movement: the targets or files that rose, or fell, most
  against the baseline. A row carries its `name`, its coverage and the
  difference in percentage points.
  """
  def movement_section(assigns) do
    ~H"""
    <.card_section data-part="movement-section">
      <div data-part="header">
        <span data-part="title">{@title}</span>
      </div>
      <.table :if={@rows != []} id={"coverage-#{@id}-table"} rows={@rows}>
        <:col :let={row} label={@label}>
          <.text_and_description_cell
            label={Path.basename(row.name)}
            description={parent_dir(row.name)}
          />
        </:col>
        <:col :let={row} label={dgettext("dashboard_tests", "Coverage")}>
          <div data-part="cell" data-type="badge">
            <span data-part="label">{if row.coverage, do: "#{row.coverage}%", else: "—"}</span>
            <.badge
              :if={row.delta}
              style="light-fill"
              size="large"
              color={change_color({:delta, row.delta})}
              label={"#{signed(row.delta)}%"}
            />
          </div>
        </:col>
      </.table>
      <div :if={@rows == []} data-part="empty">{@empty}</div>
    </.card_section>
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

  attr :delta, :float, default: nil

  def change_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@delta}
      style="light-fill"
      color={change_color({:delta, @delta})}
      label={"#{signed(@delta)}%"}
    />
    <.text_cell :if={is_nil(@delta)} label="—" />
    """
  end

  attr :totals, :map, default: nil

  def totals_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <span data-part="label">
        {if @totals,
          do: "#{Coverage.percentage(@totals.covered_lines, @totals.executable_lines)}%",
          else: "—"}
      </span>
      <.badge
        :for={{color, label} <- List.wrap(coverage_badge(@totals))}
        style="light-fill"
        size="small"
        color={color}
        label={label}
      />
    </div>
    """
  end

  attr :commit, :map, required: true

  # The schemes that measured a commit, the partial ones marked.
  def measured_by_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="badge">
      <div data-part="tags">
        <.badge
          :for={scheme <- @commit.schemes}
          style="light-fill"
          size="small"
          color={if scheme in @commit.partial_schemes, do: "warning", else: "neutral"}
          label={if scheme in @commit.partial_schemes, do: "#{scheme} · P", else: scheme}
        />
      </div>
    </div>
    """
  end

  @doc false
  def signed(nil), do: "—"
  def signed(value) when value > 0, do: "+#{value}"
  def signed(value), do: "#{value}"

  @doc false
  def short_sha(sha), do: String.slice(sha || "", 0, 7)

  @doc false
  def change_color({:delta, delta}) when delta < 0, do: "destructive"
  def change_color({:delta, delta}) when delta > 0, do: "success"
  def change_color(_change), do: "neutral"

  @doc false
  def completeness_label(%{measured: false}), do: dgettext("dashboard_tests", "Not measured")
  def completeness_label(%{complete: true, completeness: "signal"}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{complete: true}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{chained: true}), do: dgettext("dashboard_tests", "Comparable")
  def completeness_label(_commit), do: dgettext("dashboard_tests", "Not chained")

  @doc false
  def completeness_color(%{measured: false}), do: "neutral"
  def completeness_color(%{complete: true}), do: "success"
  def completeness_color(%{chained: true}), do: "information"
  def completeness_color(_commit), do: "neutral"

  @doc false
  def reason_label(%{kind: :no_merge_base, base_branch: branch} = reason),
    do: with_detail(dgettext("dashboard_tests", "the merge base with %{branch} is unknown", branch: branch), reason)

  def reason_label(%{kind: :no_history, commit: ""} = reason),
    do: with_detail(dgettext("dashboard_tests", "the commit is unknown"), reason)

  def reason_label(%{kind: :no_history, commit: sha} = reason),
    do:
      with_detail(
        dgettext("dashboard_tests", "commit %{sha} is not in the repository's Git history", sha: short_sha(sha)),
        reason
      )

  def reason_label(%{kind: :no_measured_commits, base_branch: branch, window_days: days}),
    do:
      dgettext("dashboard_tests", "no measured commit on %{branch} in the last %{days} days", branch: branch, days: days)

  def reason_label(%{kind: :no_ancestor_commit, base_branch: branch, commit: sha, window_commits: commits}),
    do:
      dgettext("dashboard_tests", "no measured commit on %{branch} within %{commits} commits before %{sha}",
        branch: branch,
        commits: commits,
        sha: short_sha(sha)
      )

  def reason_label(%{kind: :measured_set_mismatch, commit: sha, schemes: schemes, baseline_schemes: baseline}),
    do:
      dgettext("dashboard_tests", "commit %{sha} measured %{baseline} where this commit measured %{schemes}",
        sha: short_sha(sha),
        baseline: schemes_label(baseline),
        schemes: schemes_label(schemes)
      )

  def reason_label(%{reason: :partial_run}), do: dgettext("dashboard_tests", "some tests were skipped")
  def reason_label(%{kind: :partial_run}), do: dgettext("dashboard_tests", "some tests were skipped")

  def reason_label(%{reason: :no_history} = reason),
    do: with_detail(dgettext("dashboard_tests", "the run's Git history was not collected"), reason)

  def reason_label(_reason), do: dgettext("dashboard_tests", "unknown")

  def schemes_label([]), do: dgettext("dashboard_tests", "nothing")
  def schemes_label(schemes), do: Enum.join(schemes, ", ")

  def with_detail(text, %{detail: detail}) when is_binary(detail) and detail != "", do: "#{text} (#{detail})"
  def with_detail(text, _reason), do: text

  @doc "The gates that were evaluated, as the commit page's table lists them."
  def gate_rows(%{checks: checks}), do: Enum.map(checks, &Map.put(&1, :id, Atom.to_string(&1.gate)))

  @doc "The name of a gate, as the settings page and the check run call it."
  def gate_label(:min_patch_coverage), do: dgettext("dashboard_tests", "Minimum patch coverage")
  def gate_label(:max_total_drop), do: dgettext("dashboard_tests", "Maximum total drop")

  @doc """
  What the gates decided for the commit: nothing until its pipeline signals
  completion, since a verdict on a half-measured commit would be wrong.
  """
  def verdict_label(_verdict, false), do: dgettext("dashboard_tests", "Pending")
  def verdict_label(%{conclusion: :success}, _complete), do: dgettext("dashboard_tests", "Passed")
  def verdict_label(%{conclusion: :failure}, _complete), do: dgettext("dashboard_tests", "Failed")
  def verdict_label(_verdict, _complete), do: dgettext("dashboard_tests", "Not decided")

  def verdict_color(_verdict, false), do: "information"
  def verdict_color(%{conclusion: :success}, _complete), do: "success"
  def verdict_color(%{conclusion: :failure}, _complete), do: "destructive"
  def verdict_color(_verdict, _complete), do: "neutral"

  def gate_status_label(:passed), do: dgettext("dashboard_tests", "Passed")
  def gate_status_label(:failed), do: dgettext("dashboard_tests", "Failed")
  def gate_status_label(_status), do: dgettext("dashboard_tests", "Not evaluated")

  def gate_status_color(:passed), do: "success"
  def gate_status_color(:failed), do: "destructive"
  def gate_status_color(_status), do: "neutral"

  @doc "A gate's threshold and what the commit measured against it."
  def gate_threshold(%{gate: :min_patch_coverage, threshold: threshold}),
    do: dgettext("dashboard_tests", "at least %{threshold}%", threshold: threshold)

  def gate_threshold(%{gate: :max_total_drop, threshold: threshold}),
    do: dgettext("dashboard_tests", "at most %{threshold}% down", threshold: threshold)

  def gate_value(%{value: nil}), do: "—"
  def gate_value(%{gate: :min_patch_coverage, value: value}), do: "#{value}%"
  def gate_value(%{gate: :max_total_drop, value: value}), do: "#{signed(value)}%"

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

  def ref_status_color(%{complete: true}), do: "success"
  def ref_status_color(_ref), do: "information"

  def skipped_reason_label(:stale), do: dgettext("dashboard_tests", "Measured on another version of the file")
  def skipped_reason_label(:no_line_data), do: dgettext("dashboard_tests", "No per-line data in the run")
  def skipped_reason_label(:truncated), do: dgettext("dashboard_tests", "Diff too large to record its lines")
  def skipped_reason_label(:not_instrumented), do: dgettext("dashboard_tests", "Not compiled into any tested target")
  def skipped_reason_label(:excluded), do: dgettext("dashboard_tests", "Excluded in the project's coverage settings")

  @doc false
  def line_ranges(nil), do: dgettext("dashboard_tests", "Unknown")
  def line_ranges([]), do: dgettext("dashboard_tests", "None")

  def line_ranges(ranges) do
    Enum.map_join(ranges, ", ", fn
      {line, line} -> Integer.to_string(line)
      {first, last} -> "#{first}–#{last}"
    end)
  end

  @doc false
  def coverage_badge(nil), do: nil
  def coverage_badge(%{partial: true}), do: {"warning", dgettext("dashboard_tests", "P")}
  def coverage_badge(_totals), do: {"success", dgettext("dashboard_tests", "F")}
end
