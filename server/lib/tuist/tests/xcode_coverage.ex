defmodule Tuist.Tests.XcodeCoverage do
  @moduledoc """
  Xcode code coverage for test runs.

  The coverage is read from the run's result bundle by the shared Swift parser
  (`xccov view --report` for targets and functions, `xccov view --archive` for
  per-line execution counts), wherever the bundle is processed: on the server's
  macOS processors for uploaded bundles, or on the client when it processes the
  bundle itself. The client ties the files to the repository with the Git blob
  each had, which only the checkout knows.

  Every file the run covered is stored in `xcode_coverage_files` with its line
  data, and `test_runs` carries the totals. A run that left tests out on purpose
  (selective testing, `-only-testing`) is marked partial: its coverage describes
  the tests that ran and nothing else, so it stays out of the coverage trend.

  A sharded run has rows per shard. Readers merge the rows of a path: the
  executable and covered lines are the union across shards, since shards run
  disjoint tests over the same sources.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Tests.Test
  alias Tuist.Tests.XcodeCoverageFile

  @insert_chunk_size 2_000

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
  The `test_runs` coverage columns for an unsharded run.
  """
  def run_attrs(nil), do: %{}

  def run_attrs(%{partial: partial, files: files}) do
    {covered, executable} = union_totals(files)
    %{coverage_covered_lines: covered, coverage_executable_lines: executable, coverage_partial: partial}
  end

  @doc """
  Folds a shard's coverage into the merged run, after its rows are stored. The
  totals are aggregated in ClickHouse over every shard's rows, read with
  sequential consistency since a plain read can miss rows another request
  inserted moments ago, and never drop below what the run already carries: two
  shards that report at the same time each see the other's rows or not, and the
  one that writes last must not shrink the run. The run is partial when any
  shard was.
  """
  def merge_run_attrs(%Test{}, nil), do: %{}

  def merge_run_attrs(%Test{} = existing, %{partial: partial}) do
    totals = stored_totals(existing.project_id, existing.id)

    %{
      coverage_covered_lines: max(totals.covered_lines, existing.coverage_covered_lines || 0),
      coverage_executable_lines: max(totals.executable_lines, existing.coverage_executable_lines || 0),
      coverage_partial: partial or existing.coverage_partial == true
    }
  end

  def insert_files(%Test{}, nil), do: :ok

  def insert_files(%Test{id: test_run_id, project_id: project_id}, %{files: files}) do
    now = NaiveDateTime.utc_now()

    files
    |> Enum.map(
      &Map.merge(&1, %{id: UUIDv7.generate(), test_run_id: test_run_id, project_id: project_id, inserted_at: now})
    )
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(&IngestRepo.insert_all(XcodeCoverageFile, &1))
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
    from(f in XcodeCoverageFile,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.path == ^path,
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

  # One row per path, its shards' rows merged: the lines are the union across
  # shards. A file whose archive entry was missing keeps the counts the report
  # gave it, since there are no lines to merge.
  defp merged_files_query(project_id, test_run_id) do
    from(f in XcodeCoverageFile,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id,
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

  defp stored_totals(project_id, test_run_id) do
    from(f in subquery(merged_files_query(project_id, test_run_id)),
      select: %{covered_lines: sum(f.covered_lines), executable_lines: sum(f.executable_lines)}
    )
    |> ClickHouseRepo.one(settings: [select_sequential_consistency: 1])
    |> case do
      nil -> %{covered_lines: 0, executable_lines: 0}
      totals -> Map.new(totals, fn {key, value} -> {key, value || 0} end)
    end
  end

  defp file_row(file) do
    functions = value(file, :functions, [])

    %{
      path: file.path,
      git_blob_id: value(file, :git_blob_id, ""),
      targets: value(file, :targets, []),
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

  # Per path, the union of its rows' lines, as the merged query computes it: a
  # client reporting one file twice must not count it twice.
  defp union_totals(files) do
    files
    |> Enum.group_by(& &1.path)
    |> Enum.reduce({0, 0}, fn {_path, rows}, {covered, executable} ->
      {path_covered, path_executable} = union_counts(rows)
      {covered + path_covered, executable + path_executable}
    end)
  end

  defp union_counts(rows) do
    if Enum.all?(rows, &(&1.line_numbers == [])) do
      {rows |> Enum.map(& &1.covered_lines) |> Enum.max(), rows |> Enum.map(& &1.executable_lines) |> Enum.max()}
    else
      covered =
        rows
        |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
        |> Enum.flat_map(fn {line, count} -> if count > 0, do: [line], else: [] end)
        |> MapSet.new()

      {MapSet.size(covered), rows |> Enum.flat_map(& &1.line_numbers) |> MapSet.new() |> MapSet.size()}
    end
  end
end
