defmodule Tuist.Tests.Selections do
  @moduledoc """
  Coverage-based test selection plans: for a commit, which tests (or test
  targets) its runs had to execute and which they could skip, decided
  against the per-test coverage evidence of the nearest full run, the
  baseline. A test is skipped only when it has its own passing evidence at
  the baseline and none of the files it executed changed since; anything
  uncertain runs.

  A commit has one plan (`Tuist.Tests.TestSelection`, the latest one written
  for it), its decisions (`Tuist.Tests.TestSelectionDecision`) and the files
  that changed since its baseline (`Tuist.Tests.TestSelectionChangedFile`).
  The reads here back the Test Selection pages; nothing plans yet, so the
  rows come from the seeds or a client that writes them.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestSelection
  alias Tuist.Tests.TestSelectionChangedFile
  alias Tuist.Tests.TestSelectionDecision

  @selected_reasons ~w(covers_changed_file no_evidence new_test recently_failed flaky unskippable tracked_file_changed unattributed_change no_baseline)
  @skipped_reasons ~w(unaffected)

  @doc "Why a plan selects a test (`TestSelectionDecision.reason`)."
  def selected_reasons, do: @selected_reasons

  @doc "Why a plan skips a test (`TestSelectionDecision.reason`)."
  def skipped_reasons, do: @skipped_reasons

  defp plans, do: from(s in TestSelection, hints: ["FINAL"])

  @doc """
  The project's plans over a period: totals, their trend against the period
  before, and per-bucket series (hours for a period of two days or less,
  days otherwise) of plans, selected and skipped decisions, and skip rate.
  The end is carried to the close of its second, as the date picker's
  periods are in whole seconds.
  """
  def analytics(project_id, {start_datetime, end_datetime}) do
    until = DateTime.add(end_datetime, 1, :second)
    bucket = bucket(start_datetime, end_datetime)
    format = bucket_format(bucket)

    rows =
      from(s in plans(),
        where: s.project_id == ^project_id,
        where: s.inserted_at >= ^start_datetime and s.inserted_at < ^until,
        group_by: fragment("formatDateTime(?, ?)", s.inserted_at, ^format),
        select: %{
          date: fragment("formatDateTime(?, ?)", s.inserted_at, ^format),
          selections: count(),
          selected: sum(s.selected_count),
          skipped: sum(s.skipped_count),
          skipped_duration: sum(s.skipped_duration)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(&{&1.date, &1})

    points =
      start_datetime
      |> buckets(end_datetime, bucket)
      |> Enum.map(fn {date, key} ->
        row = Map.get(rows, key, %{selections: 0, selected: 0, skipped: 0, skipped_duration: 0})
        Map.merge(row, %{date: date, skip_rate: skip_rate(row.selected, row.skipped)})
      end)

    span = DateTime.diff(end_datetime, start_datetime, :second)
    current = totals(project_id, start_datetime, until)
    previous = totals(project_id, DateTime.add(start_datetime, -span, :second), start_datetime)

    %{
      totals: current,
      trends: %{
        selections: trend(previous.selections, current.selections),
        selected: trend(previous.selected, current.selected),
        skipped: trend(previous.skipped, current.skipped),
        skip_rate: trend(previous.skip_rate, current.skip_rate)
      },
      dates: Enum.map(points, & &1.date),
      selections: Enum.map(points, & &1.selections),
      selected: Enum.map(points, & &1.selected),
      skipped: Enum.map(points, & &1.skipped),
      skip_rates: Enum.map(points, & &1.skip_rate)
    }
  end

  defp totals(project_id, start_datetime, until) do
    row =
      ClickHouseRepo.one(
        from(s in plans(),
          where: s.project_id == ^project_id,
          where: s.inserted_at >= ^start_datetime and s.inserted_at < ^until,
          select: %{
            selections: count(),
            selected: sum(s.selected_count),
            skipped: sum(s.skipped_count),
            skipped_duration: sum(s.skipped_duration)
          }
        )
      )

    selected = to_integer(row && row.selected)
    skipped = to_integer(row && row.skipped)

    %{
      selections: to_integer(row && row.selections),
      selected: selected,
      skipped: skipped,
      skipped_duration: to_integer(row && row.skipped_duration),
      skip_rate: skip_rate(selected, skipped)
    }
  end

  @doc "The share of decisions that skipped, as a percentage with one decimal."
  def skip_rate(selected, skipped) do
    case selected + skipped do
      0 -> 0.0
      total -> Float.round(skipped / total * 100, 1)
    end
  end

  defp trend(previous, current) when previous in [0, +0.0] or current in [0, +0.0], do: 0.0
  defp trend(previous, current), do: Float.round((current - previous) / previous * 100, 1)

  defp bucket(start_datetime, end_datetime) do
    if DateTime.diff(end_datetime, start_datetime, :hour) <= 48, do: :hour, else: :day
  end

  defp bucket_format(:hour), do: "%Y-%m-%d %H:00"
  defp bucket_format(:day), do: "%Y-%m-%d"

  defp buckets(start_datetime, end_datetime, :hour) do
    first = %{DateTime.truncate(start_datetime, :second) | minute: 0, second: 0}
    hours = div(DateTime.diff(end_datetime, first, :second), 3600)

    for offset <- 0..hours//1 do
      datetime = DateTime.add(first, offset, :hour)
      {datetime, Calendar.strftime(datetime, "%Y-%m-%d %H:00")}
    end
  end

  defp buckets(start_datetime, end_datetime, :day) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.map(&{&1, Date.to_iso8601(&1)})
  end

  @doc """
  A page of the project's plans, newest first, with the number of test runs
  each commit has. Options: `:search` (a commit SHA prefix or part of a
  branch name), `:scope` (`test` or `target`), `:page` and `:page_size`.
  Returns `{rows, %{current_page, total_pages, total_count}}`.
  """
  def list(project_id, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      plans()
      |> where([s], s.project_id == ^project_id)
      |> filter_search(Keyword.get(opts, :search))
      |> filter_scope(Keyword.get(opts, :scope))

    total_count = query |> select([s], count()) |> ClickHouseRepo.one() |> to_integer()

    rows =
      query
      |> order_by([s], desc: s.inserted_at, desc: s.git_commit_sha)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> ClickHouseRepo.all()

    counts = test_runs_counts(project_id, Enum.map(rows, & &1.git_commit_sha))
    rows = Enum.map(rows, &Map.put(&1, :test_runs_count, Map.get(counts, &1.git_commit_sha, 0)))

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp filter_search(query, search) when search in [nil, ""], do: query

  defp filter_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [s],
      fragment("startsWith(?, ?)", s.git_commit_sha, ^String.downcase(term)) or
        fragment("positionCaseInsensitive(?, ?) > 0", s.git_branch, ^term)
    )
  end

  defp filter_scope(query, scope) when scope in ["test", "target"], do: where(query, [s], s.scope == ^scope)
  defp filter_scope(query, _scope), do: query

  @doc "The number of test runs of each of `shas`, keyed by SHA."
  def test_runs_counts(_project_id, []), do: %{}

  def test_runs_counts(project_id, shas) do
    from(t in Test.query(),
      where: t.project_id == ^project_id and t.git_commit_sha in ^shas,
      group_by: t.git_commit_sha,
      select: {t.git_commit_sha, count(t.id)}
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  @doc "The commit's plan, the latest one written for it."
  def get(project_id, sha) do
    from(s in plans(),
      where: s.project_id == ^project_id and s.git_commit_sha == ^sha,
      order_by: [desc: s.inserted_at],
      limit: 1
    )
    |> ClickHouseRepo.one()
    |> case do
      nil -> {:error, :not_found}
      selection -> {:ok, selection}
    end
  end

  @doc """
  What the plan's decisions add up to: selected and skipped decisions, the
  test targets and schemes they cover, how many targets have a selected
  test, the time the skipped ones took in the baseline, and the number of
  decisions per reason.
  """
  def summary(%TestSelection{id: id, project_id: project_id}) do
    rows =
      ClickHouseRepo.all(
        from(d in TestSelectionDecision,
          where: d.project_id == ^project_id and d.test_selection_id == ^id,
          group_by: [d.decision, d.reason],
          select: %{decision: d.decision, reason: d.reason, count: count(), duration: sum(d.duration)}
        )
      )

    targets =
      ClickHouseRepo.one(
        from(d in TestSelectionDecision,
          where: d.project_id == ^project_id and d.test_selection_id == ^id,
          select: %{
            targets: fragment("uniqExact(?)", d.module_name),
            selected_targets: fragment("uniqExactIf(?, ? = 'selected')", d.module_name, d.decision),
            schemes: fragment("groupUniqArray(?)", d.scheme)
          }
        )
      )

    count = fn decision -> rows |> Enum.filter(&(&1.decision == decision)) |> Enum.map(& &1.count) |> Enum.sum() end
    selected = count.("selected")
    skipped = count.("skipped")

    %{
      selected: selected,
      skipped: skipped,
      skip_rate: skip_rate(selected, skipped),
      skipped_duration:
        rows |> Enum.filter(&(&1.decision == "skipped")) |> Enum.map(&to_integer(&1.duration)) |> Enum.sum(),
      targets: to_integer(targets && targets.targets),
      selected_targets: to_integer(targets && targets.selected_targets),
      schemes: Enum.sort((targets && targets.schemes) || []),
      reasons:
        rows
        |> Enum.map(&Map.take(&1, [:decision, :reason, :count]))
        |> Enum.sort_by(&{&1.decision != "selected", -&1.count, &1.reason})
    }
  end

  @doc """
  A page of the plan's decisions. Options: `:search` (part of the module,
  suite or test name), `:decision` (`selected` or `skipped`), `:scheme`,
  `:sort_by` (`name`, `decision` or `duration`), `:sort_order` (`asc` or
  `desc`), `:page` and `:page_size`. Selected decisions come first unless
  sorted otherwise. Returns `{rows, %{current_page, total_pages,
  total_count}}`.
  """
  def decisions(%TestSelection{id: id, project_id: project_id}, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      TestSelectionDecision
      |> where([d], d.project_id == ^project_id and d.test_selection_id == ^id)
      |> filter_decision_search(Keyword.get(opts, :search))
      |> filter_field(:decision, Keyword.get(opts, :decision))
      |> filter_field(:scheme, Keyword.get(opts, :scheme))

    total_count = query |> select([d], count()) |> ClickHouseRepo.one() |> to_integer()

    rows =
      query
      |> sort_decisions(Keyword.get(opts, :sort_by, "decision"), Keyword.get(opts, :sort_order, "asc"))
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> ClickHouseRepo.all()

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp filter_decision_search(query, search) when search in [nil, ""], do: query

  defp filter_decision_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [d],
      fragment("positionCaseInsensitive(?, ?) > 0", d.module_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", d.suite_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", d.name, ^term)
    )
  end

  defp filter_field(query, _field, value) when value in [nil, "", "any"], do: query
  defp filter_field(query, field, value), do: where(query, [d], field(d, ^field) == ^value)

  defp sort_decisions(query, "name", "desc"),
    do: order_by(query, [d], desc: d.module_name, desc: d.suite_name, desc: d.name, desc: d.scheme)

  defp sort_decisions(query, "name", _order),
    do: order_by(query, [d], asc: d.module_name, asc: d.suite_name, asc: d.name, asc: d.scheme)

  defp sort_decisions(query, "duration", "asc"), do: order_by(query, [d], asc: d.duration, asc: d.module_name)
  defp sort_decisions(query, "duration", _order), do: order_by(query, [d], desc: d.duration, asc: d.module_name)

  # Selected first: what a run of the commit executes is what a reader
  # checks first.
  defp sort_decisions(query, _decision, "desc"),
    do: order_by(query, [d], desc: d.decision, asc: d.module_name, asc: d.suite_name, asc: d.name)

  defp sort_decisions(query, _decision, _order),
    do: order_by(query, [d], asc: d.decision, asc: d.module_name, asc: d.suite_name, asc: d.name)

  @doc "One of the plan's decisions, by its id."
  def get_decision(%TestSelection{id: id, project_id: project_id}, decision_id) do
    with {:ok, decision_id} <- Ecto.UUID.cast(decision_id),
         %TestSelectionDecision{} = decision <-
           ClickHouseRepo.one(
             from(d in TestSelectionDecision,
               where: d.project_id == ^project_id and d.test_selection_id == ^id and d.id == ^decision_id,
               limit: 1
             )
           ) do
      {:ok, decision}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The files that changed between the plan's baseline and its commit. Options:
  `:search` (part of the path), `:kind`, `:page` and `:page_size`. Files that
  selected tests come first. Returns `{rows, %{current_page, total_pages,
  total_count}}`.
  """
  def changed_files(%TestSelection{id: id, project_id: project_id}, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      TestSelectionChangedFile
      |> where([f], f.project_id == ^project_id and f.test_selection_id == ^id)
      |> filter_path(Keyword.get(opts, :search))
      |> filter_field(:kind, Keyword.get(opts, :kind))

    total_count = query |> select([f], count()) |> ClickHouseRepo.one() |> to_integer()

    rows =
      query
      |> order_by([f], desc: f.selected_count, asc: f.path)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> ClickHouseRepo.all()

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp filter_path(query, search) when search in [nil, ""], do: query

  defp filter_path(query, search),
    do: where(query, [f], fragment("positionCaseInsensitive(?, ?) > 0", f.path, ^String.trim(search)))

  @doc "The changed files of the plan among `paths`, keyed by path."
  def changed_files_by_path(_selection, []), do: %{}

  def changed_files_by_path(%TestSelection{id: id, project_id: project_id}, paths) do
    from(f in TestSelectionChangedFile,
      where: f.project_id == ^project_id and f.test_selection_id == ^id and f.path in ^paths
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.path, &1})
  end

  @doc "The test runs of the commit, newest first."
  def test_runs(project_id, sha, opts \\ []) do
    ClickHouseRepo.all(
      from(t in Test.query(),
        where: t.project_id == ^project_id and t.git_commit_sha == ^sha,
        order_by: [desc: t.ran_at],
        limit: ^Keyword.get(opts, :limit, 100)
      )
    )
  end

  @doc "Whether any test run of the commit reported coverage."
  def coverage?(project_id, sha) do
    from(r in CoverageRun,
      where: r.project_id == ^project_id and r.git_commit_sha == ^sha,
      select: 1,
      limit: 1
    )
    |> ClickHouseRepo.one()
    |> is_integer()
  end

  defp ceil_div(count, size), do: div(count + size - 1, size)

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
