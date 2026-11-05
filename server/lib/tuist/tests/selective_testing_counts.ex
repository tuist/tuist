defmodule Tuist.Tests.SelectiveTestingCounts do
  @moduledoc """
  How much of an Xcode test run selective testing saved, in tests: the tests
  the run was asked for (`requested_test_count`) and the ones it skipped
  because their target's selective-testing hash matched
  (`skipped_test_count`). Requested is what the run executed plus what it
  skipped, the same split test selection's impact runs record, so a
  coverage-selected run's counts add up the same way.

  A skipped target reports no tests, so its count is taken from the nearest
  earlier run that executed it, within `@history_days`: ranked first a run
  whose caller did not narrow it to some of the target's tests, then one of
  the same scheme, then the newest. That is the order coverage carry ranks a
  hit target's source runs (`Tuist.Tests.Coverage.Reported`), without its
  commit ancestry and hash index, which only projects with coverage have. A
  skipped target no run executed counts as none; how many there were is kept
  in `skipped_modules_without_history`, so a run with any reads as a lower
  bound.

  Only runs whose command event hashed at least one test target are counted:
  without selective testing nothing could be skipped, and counting them would
  make the rate say less about selective testing than about how often it was
  used. The hits arrive with the command event, after the run, and an
  uploaded result bundle is processed after both, so each of the two
  enqueues a count (`Tuist.Tests.Workers.SelectiveTestingCountsWorker`) and
  the one that finds the other missing does nothing.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.SelectiveTestingCount
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.Workers.SelectiveTestingCountsWorker

  @history_days 30
  @candidate_runs 5
  @unprocessed_statuses ["processing", "in_progress"]

  @doc """
  Schedules a count for the run a command event belongs to when its Xcode
  graph hashed any target for selective testing.
  """
  def count_after_command_event(%{test_run_id: test_run_id}, xcode_graph) do
    if selective_testing_hashed?(xcode_graph),
      do: SelectiveTestingCountsWorker.enqueue(test_run_id),
      else: :skipped
  end

  defp selective_testing_hashed?(xcode_graph) do
    xcode_graph
    |> field(:projects, [])
    |> Enum.flat_map(&field(&1, :targets, []))
    |> Enum.any?(&(&1 |> field(:selective_testing_metadata, %{}) |> field(:hash, nil) != nil))
  end

  defp field(nil, _key, default), do: default
  defp field(map, key, default), do: Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default

  @doc """
  Counts the run's tests and stores them. Returns the stored row, or
  `:skipped` when the run is unknown, not yet processed, or had no
  selective testing.
  """
  def record(test_run_id) do
    with {:ok, %Test{status: status} = test} when status not in @unprocessed_statuses <- Tests.get_test(test_run_id),
         [_ | _] = targets <- Coverage.Xcode.selective_testing_hashes(test.project_id, [test.id]) do
      row = count(test, targets)
      IngestRepo.insert_all(SelectiveTestingCount, [row])
      {:ok, row}
    else
      _ -> :skipped
    end
  end

  defp count(test, targets) do
    hits =
      targets
      |> Enum.filter(&(&1.hit in ["local", "remote"]))
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    history = history_test_counts(test, hits)
    skipped = hits |> Enum.map(&Map.get(history, &1, 0)) |> Enum.sum()

    %{
      test_run_id: test.id,
      project_id: test.project_id,
      ran_at: test.ran_at,
      is_ci: test.is_ci,
      scheme: test.scheme || "",
      requested_test_count: executed_test_count(test) + skipped,
      skipped_test_count: skipped,
      skipped_module_count: length(hits),
      skipped_modules_without_history: Enum.count(hits, &(not Map.has_key?(history, &1))),
      inserted_at: NaiveDateTime.utc_now()
    }
  end

  defp executed_test_count(test) do
    from(m in TestModuleRun.query(),
      where: m.test_run_id == ^test.id,
      distinct: true,
      select: {m.id, m.test_case_count}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Enum.map(fn {_id, count} -> count end)
    |> Enum.sum()
  end

  # The test count each skipped target had in its best-ranked earlier run.
  defp history_test_counts(_test, []), do: %{}

  defp history_test_counts(test, modules) do
    ran_at = test.ran_at
    cutoff = NaiveDateTime.add(ran_at, -@history_days * 86_400, :second)

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(
        """
        SELECT name, toString(test_run_id), max(test_case_count) AS tests, max(ran_at) AS last_ran_at
        FROM test_module_runs
        WHERE project_id = {project_id:Int64}
          AND name IN {modules:Array(String)}
          AND test_case_count > 0
          AND test_run_id != {test_run_id:UUID}
          AND ran_at >= {cutoff:DateTime64(6)}
          AND ran_at < {ran_at:DateTime64(6)}
        GROUP BY name, test_run_id
        ORDER BY last_ran_at DESC
        LIMIT {candidates:UInt8} BY name
        """,
        %{
          project_id: test.project_id,
          modules: modules,
          test_run_id: test.id,
          cutoff: cutoff,
          ran_at: ran_at,
          candidates: @candidate_runs
        }
      )

    candidates =
      Enum.map(rows, fn [name, run_id, count, ran_at] ->
        %{name: name, test_run_id: run_id, test_case_count: count, ran_at: ran_at}
      end)

    runs = candidate_runs(test, candidates, cutoff)

    candidates
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, module_candidates} ->
      best = Enum.min_by(module_candidates, &rank(&1, Map.get(runs, &1.test_run_id), test.scheme))
      {name, best.test_case_count}
    end)
  end

  defp candidate_runs(_test, [], _cutoff), do: %{}

  defp candidate_runs(test, candidates, cutoff) do
    ids = candidates |> Enum.map(& &1.test_run_id) |> Enum.uniq()

    from(t in Test.query(),
      where: t.project_id == ^test.project_id and t.id in ^ids,
      where: t.ran_at >= ^cutoff and t.ran_at < ^test.ran_at,
      distinct: true,
      select: {t.id, t.scheme, t.only_test_identifiers}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {id, scheme, only} -> {id, %{scheme: scheme, only_test_identifiers: only}} end)
  end

  defp rank(candidate, run, scheme) do
    {narrowed?(run, candidate.name), not same_scheme?(run, scheme),
     -NaiveDateTime.diff(candidate.ran_at, ~N[1970-01-01 00:00:00], :microsecond)}
  end

  # A run whose caller named some of the target's tests executed only those.
  defp narrowed?(nil, _module), do: false

  defp narrowed?(%{only_test_identifiers: identifiers}, module),
    do: Enum.any?(identifiers || [], &(&1 |> String.split("/", parts: 2) |> hd() == module))

  defp same_scheme?(%{scheme: scheme}, scheme) when scheme not in [nil, ""], do: true
  defp same_scheme?(_run, _scheme), do: false

  @doc """
  The requested and skipped tests summed over the project's counted runs
  that ran in the period.
  """
  def totals(project_id, start_datetime, end_datetime, opts \\ []) do
    from(c in SelectiveTestingCount,
      hints: ["FINAL"],
      where: c.project_id == ^project_id,
      where: c.ran_at > ^DateTime.to_naive(start_datetime) and c.ran_at < ^DateTime.to_naive(end_datetime),
      select: %{
        requested: fragment("toUInt64(sum(?))", c.requested_test_count),
        skipped: fragment("toUInt64(sum(?))", c.skipped_test_count),
        runs: count()
      }
    )
    |> filter_is_ci(Keyword.get(opts, :is_ci))
    |> ClickHouseRepo.one()
  end

  @doc """
  `totals/4` per time bucket, keyed by the bucket's start formatted with
  `date_format` (a ClickHouse `formatDateTime` pattern).
  """
  def totals_by_bucket(project_id, start_datetime, end_datetime, date_format, opts \\ []) do
    from(c in SelectiveTestingCount,
      hints: ["FINAL"],
      where: c.project_id == ^project_id,
      where: c.ran_at > ^DateTime.to_naive(start_datetime) and c.ran_at < ^DateTime.to_naive(end_datetime),
      group_by: fragment("formatDateTime(?, ?, 'UTC')", c.ran_at, ^date_format),
      select: %{
        date: fragment("formatDateTime(?, ?, 'UTC')", c.ran_at, ^date_format),
        requested: fragment("toUInt64(sum(?))", c.requested_test_count),
        skipped: fragment("toUInt64(sum(?))", c.skipped_test_count)
      }
    )
    |> filter_is_ci(Keyword.get(opts, :is_ci))
    |> ClickHouseRepo.all()
  end

  defp filter_is_ci(query, nil), do: query
  defp filter_is_ci(query, is_ci), do: where(query, [c], c.is_ci == ^is_ci)
end
