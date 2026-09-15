defmodule Tuist.Tests.XcodeCoverage do
  @moduledoc """
  Xcode code coverage for test runs.

  The coverage is read from the run's result bundle by the shared Swift parser
  (`xccov view --report` for targets and functions, `xccov view --archive` for
  per-line execution counts), wherever the bundle is processed: on the server's
  macOS processors for uploaded bundles, or on the client when it processes the
  bundle itself. The client ties the files to the repository with the Git blob
  each had, which only the checkout knows.

  Every file a report covered is stored in `xcode_coverage_files` with its line
  data. Test code (files only `.xctest` bundles compiled) is stored but left
  out of every figure: a test that runs covers its own body, which says nothing
  about the product. A run that left tests out on purpose (selective testing,
  `-only-testing`) is marked partial: its coverage describes the tests that ran
  and nothing else, so it stays out of the coverage trend.

  A sharded run gets a report per shard. A report's rows share `inserted_at`
  and only each shard's latest report is read, so a retried or reprocessed
  shard replaces what it sent before. Readers merge the reports of a path: the
  executable and covered lines are the union across shards, since shards run
  disjoint tests over the same sources.

  Shards report concurrently, so no report can safely rewrite totals another
  one computed. The run page derives the totals from the reports, and the
  coverage trend reads `xcode_coverage_runs`, where every report publishes the
  totals over the shards reported so far and the most complete computation
  wins, whatever order the reports land in.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Tests.Test
  alias Tuist.Tests.XcodeCoverageFile
  alias Tuist.Tests.XcodeCoverageRun

  @insert_chunk_size 2_000

  # A published version ranks the shards a computation included above the
  # newest report it saw, in microseconds, which stay below 2^51 until 2041.
  @shard_count_weight 2 ** 51

  @doc """
  The rows to store for the `xcode_coverage` block reported with a run, or nil
  when the project's account does not have coverage enabled.
  """
  def rows(_project_id, nil), do: nil

  def rows(project_id, coverage) do
    if enabled_for_project?(project_id), do: rows(coverage)
  end

  defp enabled_for_project?(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil -> false
      project -> FeatureFlags.xcode_coverage_enabled?(project.account)
    end
  end

  defp rows(coverage) do
    %{partial: Map.get(coverage, :partial, false), files: coverage |> Map.get(:files, []) |> Enum.map(&file_row/1)}
  end

  @doc """
  Stores one report's files and publishes the run's totals over every shard
  reported so far. `shard_index` is nil for an unsharded run.
  """
  def publish(%Test{}, nil, _shard_index), do: :ok

  def publish(%Test{} = test, coverage, shard_index) do
    shard_index = shard_index || 0
    reported_at = NaiveDateTime.utc_now()
    insert_files(test, coverage, shard_index, reported_at)
    publish_totals(test, coverage, shard_index, reported_at)
  end

  defp insert_files(%Test{id: test_run_id, project_id: project_id}, coverage, shard_index, reported_at) do
    coverage.files
    |> Enum.map(
      &Map.merge(&1, %{
        id: UUIDv7.generate(),
        test_run_id: test_run_id,
        project_id: project_id,
        shard_index: shard_index,
        partial: coverage.partial,
        inserted_at: reported_at
      })
    )
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(&IngestRepo.insert_all(XcodeCoverageFile, &1))
  end

  # The report's own files are merged from memory, since rows inserted moments
  # ago are not reliably read back within the same request; the other shards'
  # latest reports come from ClickHouse.
  defp publish_totals(%Test{id: test_run_id, project_id: project_id}, coverage, shard_index, reported_at) do
    others = other_shards(project_id, test_run_id, shard_index)

    {covered, executable} =
      coverage.files
      |> Enum.reject(& &1.is_test)
      |> Enum.map(&{&1.path, file_evidence(&1)})
      |> Kernel.++(others.files)
      |> merged_totals()

    newest_report_at = Enum.max([reported_at, others.newest_report_at], NaiveDateTime)

    IngestRepo.insert_all(XcodeCoverageRun, [
      %{
        project_id: project_id,
        test_run_id: test_run_id,
        covered_lines: covered,
        executable_lines: executable,
        partial: coverage.partial or others.partial,
        version:
          (others.shards_count + 1) * @shard_count_weight +
            NaiveDateTime.diff(newest_report_at, ~N[1970-01-01 00:00:00], :microsecond),
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    :ok
  end

  defp other_shards(project_id, test_run_id, shard_index) do
    reports = from(f in report_files(project_id, test_run_id), where: f.shard_index != ^shard_index)

    files =
      from(f in reports,
        where: not f.is_test,
        group_by: f.path,
        select: {
          f.path,
          fragment("max(length(?))", f.line_numbers),
          max(f.covered_lines),
          max(f.executable_lines),
          fragment("groupUniqArrayArray(?)", f.line_numbers),
          fragment("groupUniqArrayArray(arrayFilter((l, c) -> c > 0, ?, ?))", f.line_numbers, f.execution_counts)
        }
      )
      |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
      |> Enum.map(fn
        {path, 0, covered, executable, _lines, _covered_lines} -> {path, {:counts, covered, executable}}
        {path, _, _, _, lines, covered_lines} -> {path, {:lines, MapSet.new(lines), MapSet.new(covered_lines)}}
      end)

    summary =
      ClickHouseRepo.one(
        from(f in reports,
          select: %{
            shards_count: fragment("uniqExact(?)", f.shard_index),
            partial_rows: fragment("countIf(?)", f.partial),
            newest_report_at: max(f.inserted_at)
          }
        ), settings: [select_sequential_consistency: 1])

    %{
      files: files,
      shards_count: summary.shards_count,
      partial: summary.partial_rows > 0,
      newest_report_at: summary.newest_report_at || ~N[1970-01-01 00:00:00]
    }
  end

  defp file_evidence(%{line_numbers: [], covered_lines: covered, executable_lines: executable}),
    do: {:counts, covered, executable}

  defp file_evidence(file) do
    covered =
      file.line_numbers
      |> Enum.zip(file.execution_counts)
      |> Enum.flat_map(fn {line, count} -> if count > 0, do: [line], else: [] end)

    {:lines, MapSet.new(file.line_numbers), MapSet.new(covered)}
  end

  defp merged_totals(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce({0, 0}, fn {_path, evidence}, {covered, executable} ->
      {path_covered, path_executable} = merge_evidence(evidence)
      {covered + path_covered, executable + path_executable}
    end)
  end

  # As `merged_files_query/2`: the lines are the union across reports, and a
  # path no report has lines for keeps the largest counts.
  defp merge_evidence(evidence) do
    case for({:lines, lines, covered} <- evidence, do: {lines, covered}) do
      [] ->
        counts = for {:counts, covered, executable} <- evidence, do: {covered, executable}
        {counts |> Enum.map(&elem(&1, 0)) |> Enum.max(), counts |> Enum.map(&elem(&1, 1)) |> Enum.max()}

      line_sets ->
        {
          line_sets |> Enum.map(&elem(&1, 1)) |> Enum.reduce(&MapSet.union/2) |> MapSet.size(),
          line_sets |> Enum.map(&elem(&1, 0)) |> Enum.reduce(&MapSet.union/2) |> MapSet.size()
        }
    end
  end

  @doc """
  The run's totals merged across its shards, and whether any shard left tests
  out on purpose. Nil when the run has no coverage of product code.
  """
  def run_summary(project_id, test_run_id) do
    totals =
      ClickHouseRepo.one(
        from(f in subquery(merged_files_query(project_id, test_run_id)),
          select: %{covered_lines: sum(f.covered_lines), executable_lines: sum(f.executable_lines)}
        )
      )

    case totals do
      %{executable_lines: executable} when is_integer(executable) and executable > 0 ->
        partial_rows =
          ClickHouseRepo.one(from(f in report_files(project_id, test_run_id), select: fragment("countIf(?)", f.partial)))

        Map.put(totals, :partial, (partial_rows || 0) > 0)

      _ ->
        nil
    end
  end

  @doc """
  The run's targets with their file count and line totals, least covered
  first. A file compiled into several targets counts towards each, as `xccov`
  reports it.
  """
  def targets_for_run(project_id, test_run_id) do
    ClickHouseRepo.all(
      from(f in subquery(merged_files_query(project_id, test_run_id)),
        group_by: fragment("arrayJoin(?)", f.targets),
        select: %{
          name: fragment("arrayJoin(?)", f.targets),
          files_count: count(f.path),
          covered_lines: sum(f.covered_lines),
          executable_lines: sum(f.executable_lines)
        },
        order_by: [
          asc: fragment("sum(?) / greatest(sum(?), 1)", f.covered_lines, f.executable_lines),
          asc: fragment("arrayJoin(?)", f.targets)
        ]
      )
    )
  end

  @doc """
  One page of the run's files, least covered first, and the number of files.
  """
  def list_files(project_id, test_run_id, page, page_size) do
    files_query = merged_files_query(project_id, test_run_id)

    [files, count] =
      Tuist.Tasks.parallel_tasks([
        fn ->
          ClickHouseRepo.all(
            from(f in subquery(files_query),
              order_by: [asc: fragment("? / greatest(?, 1)", f.covered_lines, f.executable_lines), asc: f.path],
              limit: ^page_size,
              offset: ^((page - 1) * page_size)
            )
          )
        end,
        fn -> ClickHouseRepo.one(from(f in subquery(files_query), select: count(f.path))) || 0 end
      ])

    {files, count}
  end

  @doc """
  One file's merged coverage in a run: per-line execution counts, the ranges
  of executable lines no test ran, and its functions. Nil when the run has no
  coverage for the path.
  """
  def file_detail(project_id, test_run_id, path) do
    from(f in report_files(project_id, test_run_id),
      where: f.path == ^path and not f.is_test,
      order_by: [desc: f.inserted_at]
    )
    |> ClickHouseRepo.all()
    |> case do
      [] -> nil
      rows -> detail(path, rows)
    end
  end

  def percentage(_covered, 0), do: 0.0
  def percentage(_covered, nil), do: 0.0
  def percentage(covered, executable), do: Float.round(covered / executable * 100, 1)

  # A row per shard that compiled the file: the counts add up.
  defp detail(path, rows) do
    lines =
      rows
      |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
      |> Enum.reduce(%{}, fn {line, count}, acc -> Map.update(acc, line, count, &(&1 + count)) end)
      |> Enum.sort()

    %{
      path: path,
      git_blob_id: rows |> hd() |> Map.get(:git_blob_id),
      targets: rows |> Enum.flat_map(& &1.targets) |> Enum.uniq() |> Enum.sort(),
      covered_lines: Enum.count(lines, fn {_line, count} -> count > 0 end),
      executable_lines: length(lines),
      lines: lines,
      uncovered_ranges: uncovered_ranges(lines),
      functions: merged_functions(rows)
    }
  end

  # Runs of executable lines no test ran, in the order of the executable lines:
  # the non-executable lines between two uncovered ones (blank lines, comments)
  # do not split a range.
  defp uncovered_ranges(lines) do
    lines
    |> Enum.chunk_by(fn {_line, count} -> count == 0 end)
    |> Enum.filter(fn [{_line, count} | _] -> count == 0 end)
    |> Enum.map(fn chunk -> {chunk |> hd() |> elem(0), chunk |> List.last() |> elem(0)} end)
  end

  defp merged_functions(rows) do
    rows
    |> Enum.flat_map(fn row ->
      Enum.zip([
        row.function_names,
        row.function_line_numbers,
        row.function_execution_counts,
        row.function_covered_lines,
        row.function_executable_lines
      ])
    end)
    |> Enum.group_by(fn {name, line, _, _, _} -> {name, line} end)
    |> Enum.map(fn {{name, line}, entries} ->
      %{
        name: name,
        line_number: line,
        execution_count: entries |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
        covered_lines: entries |> Enum.map(&elem(&1, 3)) |> Enum.max(),
        executable_lines: entries |> Enum.map(&elem(&1, 4)) |> Enum.max()
      }
    end)
    |> Enum.sort_by(&{&1.line_number, &1.name})
  end

  # The rows of each shard's latest report.
  defp report_files(project_id, test_run_id) do
    latest_reports =
      from(f in XcodeCoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id,
        group_by: f.shard_index,
        select: %{shard_index: f.shard_index, inserted_at: max(f.inserted_at)}
      )

    from(f in XcodeCoverageFile,
      join: r in subquery(latest_reports),
      on: r.shard_index == f.shard_index and r.inserted_at == f.inserted_at,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id
    )
  end

  # One row per path, its shards' reports merged: the lines are the union
  # across shards. A file whose archive entry was missing keeps the counts the
  # report gave it, since there are no lines to merge.
  defp merged_files_query(project_id, test_run_id) do
    from(f in report_files(project_id, test_run_id),
      where: not f.is_test,
      group_by: f.path,
      select: %{
        path: f.path,
        git_blob_id: fragment("any(?)", f.git_blob_id),
        targets: fragment("groupUniqArrayArray(?)", f.targets),
        executable_lines:
          fragment(
            "toUInt64(if(max(length(?)) = 0, max(?), length(groupUniqArrayArray(?))))",
            f.line_numbers,
            f.executable_lines,
            f.line_numbers
          ),
        covered_lines:
          fragment(
            "toUInt64(if(max(length(?)) = 0, max(?), length(groupUniqArrayArray(arrayFilter((l, c) -> c > 0, ?, ?)))))",
            f.line_numbers,
            f.covered_lines,
            f.line_numbers,
            f.execution_counts
          )
      }
    )
  end

  defp file_row(file) do
    functions = value(file, :functions, [])

    %{
      path: file.path,
      git_blob_id: value(file, :git_blob_id, ""),
      targets: value(file, :targets, []),
      is_test: value(file, :is_test, false),
      covered_lines: value(file, :covered_lines, 0),
      executable_lines: value(file, :executable_lines, 0),
      line_numbers: value(file, :line_numbers, []),
      execution_counts: value(file, :execution_counts, []),
      function_names: Enum.map(functions, &value(&1, :name, "")),
      function_line_numbers: Enum.map(functions, &value(&1, :line_number, 0)),
      function_execution_counts: Enum.map(functions, &value(&1, :execution_count, 0)),
      function_covered_lines: Enum.map(functions, &value(&1, :covered_lines, 0)),
      function_executable_lines: Enum.map(functions, &value(&1, :executable_lines, 0))
    }
  end

  defp value(map, key, default), do: Map.get(map, key) || default
end
