defmodule Tuist.Tests.XcodeCoverage do
  @moduledoc """
  Xcode code coverage for test runs.

  The coverage is read from the run's result bundle by the shared Swift parser
  (`xccov view --report` for targets and functions, `xccov view --archive` for
  per-line execution counts), wherever the bundle is processed: on the server's
  macOS processors for uploaded bundles, or on the client when it processes the
  bundle itself. The client ties the files to the repository with the Git blob
  each had, which only the checkout knows.

  Every file the run observed is stored in `xcode_coverage_files` with its line
  data. A run that left tests out on purpose (selective testing, `-only-testing`)
  has not run every test that covers its files: Xcode still builds and loads the
  skipped tests' targets, so their files show up observed with the lines only
  the skipped tests reach left uncovered, or not at all when the target was not
  built. For every tracked file of such a run whose Git blob matches the latest
  earlier evidence for its path, that evidence is carried forward when it covers
  lines the run did not: unchanged contents, tests skipped because nothing they
  depend on changed. The run's reported coverage is the union of what it
  observed and what it carried forward; the observed figure is kept beside it
  on `test_runs`.

  A sharded run has rows per shard. Readers merge every row of a path the same
  way: the executable and covered lines are the union across rows, since shards
  run disjoint tests over the same sources.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Test
  alias Tuist.Tests.XcodeCoverageFile

  @carry_forward_window_days 30
  @lookup_chunk_size 1_000
  @insert_chunk_size 2_000

  @doc """
  Turns the `xcode_coverage` block reported for a run into the rows to store:
  the files the run observed, and for a partial run, the files carried forward
  from earlier runs of the project.
  """
  def evidence(_project_id, _test_run_id, nil), do: nil

  def evidence(project_id, test_run_id, coverage) do
    observed = coverage |> Map.get(:files, []) |> Enum.map(&observed_row/1)
    observed_paths = MapSet.new(observed, & &1.path)

    carried =
      if Map.get(coverage, :partial, false) do
        observed_by_path = Map.new(observed, &{&1.path, &1})

        unobserved =
          coverage
          |> Map.get(:unobserved_files, [])
          |> Enum.reject(&MapSet.member?(observed_paths, &1.path))
          |> Enum.map(&{&1.path, Map.get(&1, :git_blob_id)})

        (Enum.map(observed, &{&1.path, &1.git_blob_id}) ++ unobserved)
        |> Enum.reject(fn {_path, git_blob_id} -> blank?(git_blob_id) end)
        |> carried_rows(project_id, test_run_id)
        |> Enum.filter(&adds_coverage?(&1, Map.get(observed_by_path, &1.path)))
      else
        []
      end

    %{observed: observed, carried_forward: carried}
  end

  @doc """
  The `test_runs` coverage columns for an unsharded run's evidence.
  """
  def run_attrs(nil), do: %{}

  def run_attrs(%{observed: observed, carried_forward: carried}) do
    {covered, executable} = union_totals(observed ++ carried)
    {observed_covered, observed_executable} = union_totals(observed)

    %{
      coverage_covered_lines: covered,
      coverage_executable_lines: executable,
      coverage_observed_covered_lines: observed_covered,
      coverage_observed_executable_lines: observed_executable,
      coverage_carried_forward_files: carried |> Enum.map(& &1.path) |> Enum.uniq() |> length()
    }
  end

  @doc """
  Folds a shard's evidence into the merged run, after its rows are stored. The
  totals are aggregated in ClickHouse over every shard's rows, read with
  sequential consistency since a plain read can miss rows another request
  inserted moments ago, and the line totals never drop below what the run
  already carries: two shards that report at the same time each see the
  other's rows or not, and the one that writes last must not shrink the run.
  """
  def merge_run_attrs(%Test{}, nil), do: %{}

  def merge_run_attrs(%Test{} = existing, _evidence) do
    totals = stored_totals(existing.project_id, existing.id)

    %{
      coverage_covered_lines: max(totals.covered_lines, existing.coverage_covered_lines || 0),
      coverage_executable_lines: max(totals.executable_lines, existing.coverage_executable_lines || 0),
      coverage_observed_covered_lines: max(totals.observed_covered_lines, existing.coverage_observed_covered_lines || 0),
      coverage_observed_executable_lines:
        max(totals.observed_executable_lines, existing.coverage_observed_executable_lines || 0),
      coverage_carried_forward_files: totals.carried_forward_files
    }
  end

  def insert_files(%Test{}, nil), do: :ok

  def insert_files(%Test{id: test_run_id, project_id: project_id}, %{observed: observed, carried_forward: carried}) do
    now = NaiveDateTime.utc_now()

    (observed ++ carried)
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

    [
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
    ]
    |> Tuist.Tasks.parallel_tasks()
    |> then(fn [files, count] -> {files, count} end)
  end

  @doc """
  One file's merged coverage in a run: per-line execution counts, the ranges
  of executable lines no test ran, and its functions. Nil when the run has no
  coverage for the path.
  """
  def file_detail(project_id, test_run_id, path) do
    rows =
      ClickHouseRepo.all(
        from(f in XcodeCoverageFile,
          where: f.project_id == ^project_id and f.path == ^path and f.test_run_id == ^test_run_id,
          order_by: [desc: f.inserted_at]
        )
      )

    case Enum.split_with(rows, &(&1.source == "observed")) do
      {[], []} -> nil
      {observed, carried} -> detail(path, observed, Enum.take(carried, 1))
    end
  end

  def percentage(_covered, 0), do: 0.0
  def percentage(_covered, nil), do: 0.0
  def percentage(covered, executable), do: Float.round(covered / executable * 100, 1)

  # Observed rows (one per shard) add up; the latest carried-forward row fills in
  # what no shard ran.
  defp detail(path, observed, carried) do
    lines =
      carried
      |> line_counts()
      |> Map.merge(line_counts(observed), fn _line, carried_count, observed_count ->
        if observed_count > 0, do: observed_count, else: carried_count
      end)
      |> Enum.sort()

    functions =
      carried
      |> functions_by_key()
      |> Map.merge(functions_by_key(observed), fn _key, carried_function, observed_function ->
        %{
          observed_function
          | execution_count:
              if(observed_function.execution_count > 0,
                do: observed_function.execution_count,
                else: carried_function.execution_count
              ),
            covered_lines: max(observed_function.covered_lines, carried_function.covered_lines)
        }
      end)
      |> Map.values()
      |> Enum.sort_by(&{&1.line_number, &1.name})

    rows = observed ++ carried

    %{
      path: path,
      source: source(observed, carried),
      source_test_run_id: Enum.find_value(carried, & &1.source_test_run_id),
      git_blob_id: rows |> hd() |> Map.get(:git_blob_id),
      targets: rows |> Enum.flat_map(& &1.targets) |> Enum.uniq() |> Enum.sort(),
      covered_lines: Enum.count(lines, fn {_line, count} -> count > 0 end),
      executable_lines: length(lines),
      lines: lines,
      uncovered_ranges: uncovered_ranges(lines),
      functions: functions
    }
  end

  defp source([_ | _], []), do: "observed"
  defp source([], [_ | _]), do: "carried_forward"
  defp source(_observed, _carried), do: "observed_and_carried_forward"

  defp line_counts(rows) do
    rows
    |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
    |> Enum.reduce(%{}, fn {line, count}, acc -> Map.update(acc, line, count, &(&1 + count)) end)
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

  defp functions_by_key(rows) do
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
    |> Map.new(fn {{name, line}, entries} ->
      {{name, line},
       %{
         name: name,
         line_number: line,
         execution_count: entries |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
         covered_lines: entries |> Enum.map(&elem(&1, 3)) |> Enum.max(),
         executable_lines: entries |> Enum.map(&elem(&1, 4)) |> Enum.max()
       }}
    end)
  end

  # One row per path, every row of it merged: the lines are the union across
  # shards and carried-forward evidence. A file whose archive entry was missing
  # keeps the counts the report gave it, since there are no lines to merge.
  defp merged_files_query(project_id, test_run_id) do
    from(f in XcodeCoverageFile,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id,
      group_by: f.path,
      select: %{
        path: f.path,
        observed: fragment("toBool(countIf(? = 'observed') > 0)", f.source),
        carried_forward: fragment("toBool(countIf(? = 'carried_forward') > 0)", f.source),
        git_blob_id:
          fragment(
            "if(countIf(? = 'observed') > 0, anyIf(?, ? = 'observed'), any(?))",
            f.source,
            f.git_blob_id,
            f.source,
            f.git_blob_id
          ),
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
          ),
        observed_executable_lines:
          fragment(
            "toUInt64(if(maxIf(length(?), ? = 'observed') = 0, maxIf(?, ? = 'observed'), length(groupUniqArrayArrayIf(?, ? = 'observed'))))",
            f.line_numbers,
            f.source,
            f.executable_lines,
            f.source,
            f.line_numbers,
            f.source
          ),
        observed_covered_lines:
          fragment(
            "toUInt64(if(maxIf(length(?), ? = 'observed') = 0, maxIf(?, ? = 'observed'), length(groupUniqArrayArrayIf(arrayFilter((l, c) -> c > 0, ?, ?), ? = 'observed'))))",
            f.line_numbers,
            f.source,
            f.covered_lines,
            f.source,
            f.line_numbers,
            f.execution_counts,
            f.source
          )
      }
    )
  end

  defp stored_totals(project_id, test_run_id) do
    from(f in subquery(merged_files_query(project_id, test_run_id)),
      select: %{
        covered_lines: sum(f.covered_lines),
        executable_lines: sum(f.executable_lines),
        observed_covered_lines: sum(f.observed_covered_lines),
        observed_executable_lines: sum(f.observed_executable_lines),
        carried_forward_files: fragment("countIf(?)", f.carried_forward)
      }
    )
    |> ClickHouseRepo.one(settings: [select_sequential_consistency: 1])
    |> case do
      nil ->
        %{
          covered_lines: 0,
          executable_lines: 0,
          observed_covered_lines: 0,
          observed_executable_lines: 0,
          carried_forward_files: 0
        }

      totals ->
        Map.new(totals, fn {key, value} -> {key, value || 0} end)
    end
  end

  # The latest observed evidence per path within the window, kept only where it
  # has the Git blob the run built. Evidence the run itself stored (another
  # shard of it) is left out: the run's own rows are merged on read anyway.
  defp carried_rows([], _project_id, _test_run_id), do: []

  defp carried_rows(candidates, project_id, test_run_id) do
    blob_ids_by_path = Map.new(candidates)
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@carry_forward_window_days, :day)

    blob_ids_by_path
    |> Map.keys()
    |> Enum.chunk_every(@lookup_chunk_size)
    |> Enum.flat_map(fn paths ->
      ids =
        from(f in XcodeCoverageFile,
          where:
            f.project_id == ^project_id and f.path in ^paths and f.source == "observed" and
              f.inserted_at >= ^cutoff,
          group_by: [f.path, f.git_blob_id],
          select: {f.path, f.git_blob_id, fragment("argMax(?, ?)", f.id, f.inserted_at)}
        )
        |> exclude_run(test_run_id)
        |> ClickHouseRepo.all()
        |> Enum.filter(fn {path, git_blob_id, _id} -> Map.get(blob_ids_by_path, path) == git_blob_id end)
        |> Enum.map(fn {_path, _git_blob_id, id} -> id end)

      case ids do
        [] ->
          []

        ids ->
          from(f in XcodeCoverageFile, where: f.project_id == ^project_id and f.path in ^paths and f.id in ^ids)
          |> ClickHouseRepo.all()
          |> Enum.map(&carried_row/1)
      end
    end)
  end

  defp exclude_run(query, nil), do: query
  defp exclude_run(query, test_run_id), do: where(query, [f], f.test_run_id != ^test_run_id)

  defp carried_row(%XcodeCoverageFile{} = row) do
    row
    |> Map.from_struct()
    |> Map.drop([:__meta__, :test_run, :id, :test_run_id, :project_id, :inserted_at])
    |> Map.merge(%{source: "carried_forward", source_test_run_id: row.test_run_id})
  end

  defp observed_row(file) do
    functions = Map.get(file, :functions) || []

    %{
      path: file.path,
      git_blob_id: Map.get(file, :git_blob_id) || "",
      targets: Map.get(file, :targets) || [],
      source: "observed",
      source_test_run_id: nil,
      covered_lines: Map.get(file, :covered_lines) || 0,
      executable_lines: Map.get(file, :executable_lines) || 0,
      line_numbers: Map.get(file, :line_numbers) || [],
      execution_counts: Map.get(file, :execution_counts) || [],
      function_names: Enum.map(functions, &(Map.get(&1, :name) || "")),
      function_line_numbers: Enum.map(functions, &(Map.get(&1, :line_number) || 0)),
      function_execution_counts: Enum.map(functions, &(Map.get(&1, :execution_count) || 0)),
      function_covered_lines: Enum.map(functions, &(Map.get(&1, :covered_lines) || 0)),
      function_executable_lines: Enum.map(functions, &(Map.get(&1, :executable_lines) || 0))
    }
  end

  # Carried-forward evidence is only worth a row when it covers a line the run
  # did not.
  defp adds_coverage?(_carried, nil), do: true

  defp adds_coverage?(carried, observed) do
    not MapSet.subset?(covered_line_set(carried), covered_line_set(observed))
  end

  defp covered_line_set(row) do
    row.line_numbers
    |> Enum.zip(row.execution_counts)
    |> Enum.flat_map(fn {line, count} -> if count > 0, do: [line], else: [] end)
    |> MapSet.new()
  end

  # Per path, the union of its rows' lines, as the merged query computes it.
  defp union_totals(rows) do
    rows
    |> Enum.group_by(& &1.path)
    |> Enum.reduce({0, 0}, fn {_path, path_rows}, {covered, executable} ->
      {path_covered, path_executable} = union_counts(path_rows)
      {covered + path_covered, executable + path_executable}
    end)
  end

  defp union_counts(rows) do
    if Enum.all?(rows, &(&1.line_numbers == [])) do
      {rows |> Enum.map(& &1.covered_lines) |> Enum.max(), rows |> Enum.map(& &1.executable_lines) |> Enum.max()}
    else
      {
        rows |> Enum.reduce(MapSet.new(), &MapSet.union(&2, covered_line_set(&1))) |> MapSet.size(),
        rows |> Enum.flat_map(& &1.line_numbers) |> MapSet.new() |> MapSet.size()
      }
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
