defmodule Tuist.Tests.Coverage do
  @moduledoc """
  Code coverage for test runs, in a model shared by every build system.

  Xcode coverage is read from the run's result bundle by the shared Swift
  parser (`xccov view --report` for targets and functions, `xccov view
  --archive` for per-line execution counts), wherever the bundle is processed:
  on the server's macOS processors for uploaded bundles, or on the client when
  it processes the bundle itself. The client ties the files to the repository
  with the Git blob each had, which only the checkout knows. JaCoCo (Gradle)
  and LCOV (Bazel) reports map onto the same rows: a module or label is a
  target, a method is a function, and their branch counters fill the columns
  `xccov` leaves empty.

  Every file a report covered is stored in `coverage_files` with its line
  data, tagged with the build system and the tool that produced it. A row's
  scope is the run for now (`scope_kind` `run`); per-target, per-suite and
  per-test rows use the same table once tests are attributed. Its evidence
  kind is `observed`, measured in this run; `cached` and `carried` rows are
  reused evidence, recorded by later phases. `in_repository` marks the paths
  Git knows, the only ones evidence may rely on. Test code (files only `.xctest` bundles compiled) is stored but left
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
  coverage trend reads `coverage_runs`, where every report publishes the
  totals over the shards reported so far and the most complete computation
  wins, whatever order the reports land in. The totals carry the run's scheme
  and the tool and version that measured them, and the repository's Git
  object format, so figures are only ever compared like with like.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test

  @insert_chunk_size 2_000

  # A published version ranks the shards a computation included above the
  # newest report it saw, in microseconds, which stay below 2^51 until 2041.
  @shard_count_weight 2 ** 51

  @doc """
  The rows to store for the `xcode_coverage` block reported with a run, or nil
  when the project's account does not have coverage enabled. Only files the
  client found in Git, under a repository-relative path, are evidence.

  The block either carries its `files` inline, or a `path` to the file the
  parser streamed them to (one JSON object per line), which comes back as a
  lazy stream so a large report is never held whole. String and atom keys are
  both accepted: the inline form arrives cast by the API, the streamed form
  decoded from JSON.
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
    files =
      case value(coverage, :path, nil) do
        nil ->
          coverage |> value(:files, []) |> Enum.map(&file_row/1)

        path ->
          path
          |> File.stream!()
          |> Stream.map(&String.trim_trailing(&1, "\n"))
          |> Stream.reject(&(&1 == ""))
          |> Stream.map(&(&1 |> JSON.decode!() |> file_row()))
      end

    %{partial: value(coverage, :partial, false), files: files}
  end

  @doc """
  Stores one report's files and publishes the run's totals over every shard
  reported so far. `shard_index` is nil for an unsharded run, and
  `expected_shards` is how many shards the run's plan has: until each of them
  reported coverage, the published totals are partial, since the missing
  shards' tests are not in them.
  """
  def publish(test, coverage, shard_index, expected_shards \\ 1)

  def publish(%Test{}, nil, _shard_index, _expected_shards), do: :ok

  def publish(%Test{} = test, coverage, shard_index, expected_shards) do
    shard_index = shard_index || 0
    reported_at = NaiveDateTime.utc_now()
    others = other_shards(test.project_id, test.id, shard_index)
    folded = insert_files_and_fold(test, coverage, shard_index, reported_at, others)
    publish_totals(test, coverage, expected_shards, reported_at, others, folded)
  end

  # One pass over the report's files, which may be a lazy stream: each chunk is
  # inserted and folded into the run's totals as it goes by, so nothing holds
  # the report whole. The report's own files are merged from memory, since rows
  # inserted moments ago are not reliably read back within the same request;
  # the other shards' latest reports come from ClickHouse. A file's lines are
  # only kept when another shard reported the same path, for the union; every
  # other file adds its counts and is let go.
  defp insert_files_and_fold(%Test{id: test_run_id, project_id: project_id}, coverage, shard_index, reported_at, others) do
    others_by_path = Map.new(others.files)

    {{covered, executable}, overlap, object_format} =
      coverage.files
      |> Stream.map(
        &Map.merge(&1, %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          project_id: project_id,
          build_system: "xcode",
          shard_index: shard_index,
          partial: coverage.partial,
          scope_kind: "run",
          scope_id: "",
          evidence_kind: "observed",
          inserted_at: reported_at
        })
      )
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.reduce({{0, 0}, %{}, ""}, fn chunk, acc ->
        IngestRepo.insert_all(CoverageFile, chunk)

        Enum.reduce(chunk, acc, fn file, {totals, overlap, object_format} ->
          object_format = if object_format == "", do: git_object_format(file), else: object_format

          cond do
            file.is_test ->
              {totals, overlap, object_format}

            Map.has_key?(others_by_path, file.path) ->
              {totals, Map.put(overlap, file.path, file_evidence(file)), object_format}

            true ->
              {covered, executable} = totals
              {{covered + file.covered_lines, executable + file.executable_lines}, overlap, object_format}
          end
        end)
      end)

    totals =
      Enum.reduce(others_by_path, {covered, executable}, fn {path, evidence}, {covered, executable} ->
        {path_covered, path_executable} =
          case Map.fetch(overlap, path) do
            {:ok, own_evidence} -> merge_evidence([own_evidence, evidence])
            :error -> merge_evidence([evidence])
          end

        {covered + path_covered, executable + path_executable}
      end)

    %{totals: totals, object_format: object_format}
  end

  defp publish_totals(
         %Test{id: test_run_id, project_id: project_id} = test,
         coverage,
         expected_shards,
         reported_at,
         others,
         folded
       ) do
    {covered, executable} = folded.totals
    newest_report_at = Enum.max([reported_at, others.newest_report_at], NaiveDateTime)

    IngestRepo.insert_all(CoverageRun, [
      %{
        project_id: project_id,
        test_run_id: test_run_id,
        build_system: "xcode",
        coverage_tool: "xccov",
        coverage_tool_version: test.xcode_version || "",
        git_object_format: folded.object_format,
        scheme: test.scheme || "",
        covered_lines: covered,
        executable_lines: executable,
        partial: coverage.partial or others.partial or others.shards_count + 1 < expected_shards,
        version:
          (others.shards_count + 1) * @shard_count_weight +
            NaiveDateTime.diff(newest_report_at, ~N[1970-01-01 00:00:00], :microsecond),
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    :ok
  end

  # A blob id is 40 hex digits in a SHA-1 repository and 64 in a SHA-256 one;
  # a file Git does not track says nothing about the repository.
  defp git_object_format(%{git_blob_id: <<_::binary-size(64)>>}), do: "sha256"
  defp git_object_format(%{git_blob_id: <<_::binary-size(40)>>}), do: "sha1"
  defp git_object_format(_file), do: ""

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
        ),
        settings: [select_sequential_consistency: 1]
      )

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
  The merged totals of the given runs, keyed by run id: the figures the
  coverage trend reads. Runs that gathered no coverage are absent.
  """
  def totals_for_runs(_project_id, []), do: %{}

  def totals_for_runs(project_id, test_run_ids) do
    from(c in CoverageRun,
      where: c.project_id == ^project_id and c.test_run_id in ^test_run_ids,
      group_by: c.test_run_id,
      having: fragment("argMax(?, ?)", c.executable_lines, c.version) > 0,
      select: %{
        test_run_id: c.test_run_id,
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
        partial: fragment("argMax(?, ?)", c.partial, c.version)
      }
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.test_run_id, Map.delete(&1, :test_run_id)})
  end

  @doc """
  The ids of the project's runs that gathered coverage, narrowed to the full
  (`:full`) or the partial (`:partial`) ones, or all of them for anything else.
  """
  def run_ids_query(project_id, coverage) do
    query =
      from(c in CoverageRun,
        where: c.project_id == ^project_id,
        group_by: c.test_run_id,
        having: fragment("argMax(?, ?)", c.executable_lines, c.version) > 0,
        select: c.test_run_id
      )

    case coverage do
      :full -> from(c in query, having: fragment("argMax(?, ?)", c.partial, c.version) == false)
      :partial -> from(c in query, having: fragment("argMax(?, ?)", c.partial, c.version) == true)
      _ -> query
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

  @retention_tables %{files: "coverage_files", runs: "coverage_runs"}

  @doc """
  Sets each coverage table's time-to-live to the configured retention (see
  `Tuist.Environment.coverage_retention_days/1`) and returns the days applied
  per table. The tables get it at creation; this re-applies it after the
  configuration changed.
  """
  def apply_retention do
    for {kind, days} <- Environment.coverage_retention_days(), table = Map.fetch!(@retention_tables, kind) do
      IngestRepo.query!("ALTER TABLE #{table} MODIFY TTL toDateTime(inserted_at) + INTERVAL #{days} DAY")
      {table, days}
    end
  end

  def percentage(_covered, 0), do: 0.0
  def percentage(_covered, nil), do: 0.0
  def percentage(covered, executable), do: Float.round(covered / executable * 100, 1)

  # A row per shard that compiled the file: the counts add up. When no report
  # has the file's lines (its archive entry was missing), the counts are the
  # report's, as in `merged_files_query/2`, and which lines ran is unknown:
  # `uncovered_ranges` is nil rather than empty.
  defp detail(path, rows) do
    lines =
      rows
      |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
      |> Enum.reduce(%{}, fn {line, count}, acc -> Map.update(acc, line, count, &(&1 + count)) end)
      |> Enum.sort()

    {covered_lines, executable_lines, uncovered_ranges} =
      if lines == [] do
        {rows |> Enum.map(& &1.covered_lines) |> Enum.max(), rows |> Enum.map(& &1.executable_lines) |> Enum.max(), nil}
      else
        {Enum.count(lines, fn {_line, count} -> count > 0 end), length(lines), uncovered_ranges(lines)}
      end

    %{
      path: path,
      git_blob_id: rows |> hd() |> Map.get(:git_blob_id),
      targets: rows |> Enum.flat_map(& &1.targets) |> Enum.uniq() |> Enum.sort(),
      covered_lines: covered_lines,
      executable_lines: executable_lines,
      lines: lines,
      uncovered_ranges: uncovered_ranges,
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

  # xccov gives a function its first line but not its range, so the union of
  # the lines several shards covered in it cannot be told apart from lines of
  # other functions. Its covered lines are exact when at most one report
  # covered any, and nil (unknown) otherwise; calls add up across shards.
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
      covered_lines =
        case entries |> Enum.map(&elem(&1, 3)) |> Enum.filter(&(&1 > 0)) do
          [] -> 0
          [covered] -> covered
          _ -> nil
        end

      %{
        name: name,
        line_number: line,
        execution_count: entries |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
        covered_lines: covered_lines,
        executable_lines: entries |> Enum.map(&elem(&1, 4)) |> Enum.max()
      }
    end)
    |> Enum.sort_by(&{&1.line_number, &1.name})
  end

  # The run-scoped rows of each shard's latest report.
  defp report_files(project_id, test_run_id) do
    latest_reports =
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind == "run",
        group_by: f.shard_index,
        select: %{shard_index: f.shard_index, inserted_at: max(f.inserted_at)}
      )

    from(f in CoverageFile,
      join: r in subquery(latest_reports),
      on: r.shard_index == f.shard_index and r.inserted_at == f.inserted_at,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind == "run"
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

    git_blob_id = value(file, :git_blob_id, "")

    path = value(file, :path, "")

    %{
      path: path,
      in_repository: git_blob_id != "" and not String.starts_with?(path, "/"),
      git_blob_id: git_blob_id,
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

  defp value(map, key, default) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key)) || default
      found -> found
    end
  end
end
