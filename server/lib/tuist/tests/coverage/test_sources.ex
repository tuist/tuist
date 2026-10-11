defmodule Tuist.Tests.Coverage.TestSources do
  @moduledoc """
  The versions of each test, by what it executed, and where a skipped test's
  coverage can be carried from.

  A test's evidence holds at a commit when every file it executed has the
  same blob there. A commit's fold records, for each test of its clean runs
  with evidence of its own, a fingerprint of the repository files the test
  and its suite executed with their blobs (`fingerprint/1`), the files it
  covers, those whose evidence holds no lines, whether the test passed, and
  the run. A version is the test's `test_case_id` and fingerprint, so a
  test's history keeps every version of the code it ran. A commit whose run
  skipped a test reads the test's versions and carries it from the latest
  run whose fingerprint its own blobs reproduce, on any branch
  (`Tuist.Tests.Coverage.Reported`), without walking its history.

  Files a run did not report are ones its repository's Git does not track (a
  submodule's): nothing holds their blob, and they never count, so they are
  left out. A file the run reported without a blob takes the one its
  commit's listing holds. Evidence recorded before this index existed is
  added by `backfill/1`, which fills `Tuist.Tests.Coverage.TargetSources`
  too.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.TargetSources
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageTestSource
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 2_000
  @backfill_commits 200

  @doc """
  A fingerprint of `{path, blob}` pairs, whatever their order: the same
  files with the same blobs give the same fingerprint, a changed or missing
  blob a different one.
  """
  def fingerprint(pairs) do
    pairs
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {path, blob} -> [path, 0, blob || "", 0] end)
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  @doc "Records the test versions of the commit's runs (`Tuist.Tests.Coverage.Commits.runs/2`)."
  def record(project_id, runs) do
    now = NaiveDateTime.utc_now()

    # A run at a time: a full run holds a row per test.
    for run <- runs, Map.get(run, :git_repository_id) not in [nil, 0] do
      rows = rows(project_id, run, now)
      recorded = recorded(project_id, run, Enum.map(rows, & &1.test_case_id))

      rows
      |> Enum.reject(&MapSet.member?(recorded, {&1.test_case_id, &1.fingerprint}))
      |> Enum.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(CoverageTestSource, &1))
    end

    :ok
  end

  # The versions the index already holds from this run or a newer one: its
  # commit is folded again on every report and on the completion signal, and
  # a version keeps only its latest run, so writing either again adds nothing.
  defp recorded(_project_id, _run, []), do: MapSet.new()

  defp recorded(project_id, run, test_case_ids) do
    test_case_ids
    |> Enum.uniq()
    |> Coverage.id_chunks(3)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(s in CoverageTestSource,
          where:
            s.project_id == ^project_id and s.git_repository_id == ^run.git_repository_id and s.test_case_id in ^ids and
              s.ran_at >= ^run.ran_at,
          select: {fragment("toString(?)", s.test_case_id), s.fingerprint}
        )
      )
    end)
    |> MapSet.new()
  end

  @doc """
  The versions recorded for each of the tests in the repository, with the
  latest run of each, as `%{test_case_id => [version]}`. Merges keep one row
  per version, but until they run a version can have several, so the latest
  is picked.
  """
  def versions(_project_id, _repository_id, []), do: %{}

  def versions(project_id, repository_id, test_case_ids) do
    test_case_ids
    |> Enum.uniq()
    |> Coverage.id_chunks(2)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(s in CoverageTestSource,
          where: s.project_id == ^project_id and s.git_repository_id == ^repository_id and s.test_case_id in ^ids,
          group_by: [s.test_case_id, s.fingerprint],
          select: %{
            test_case_id: fragment("toString(?)", s.test_case_id),
            fingerprint: s.fingerprint,
            paths: fragment("argMax(?, ?)", s.paths, s.ran_at),
            unlined_paths: fragment("argMax(?, ?)", s.unlined_paths, s.ran_at),
            passed: fragment("argMax(?, ?)", s.passed, s.ran_at),
            run_id: fragment("toString(argMax(?, ?))", s.test_run_id, s.ran_at),
            sha: fragment("argMax(?, ?)", s.git_commit_sha, s.ran_at),
            ran_at: max(s.ran_at)
          }
        )
      )
    end)
    |> Enum.group_by(& &1.test_case_id)
  end

  @doc """
  Records the test versions and target sources
  (`Tuist.Tests.Coverage.TargetSources`) of every run of the project still
  within the file retention, for what was reported before the indexes
  existed.
  """
  def backfill(project_id) do
    from(c in CoverageRun,
      where: c.project_id == ^project_id and c.git_commit_sha != "",
      distinct: true,
      select: c.git_commit_sha
    )
    |> ClickHouseRepo.all()
    |> Enum.chunk_every(@backfill_commits)
    |> Enum.each(fn shas ->
      runs = Commits.runs(project_id, shas)
      TargetSources.record(project_id, runs)
      record(project_id, runs)
    end)
  end

  @doc "Backfills every project with coverage (`backfill/1`) and returns how many it went through."
  def backfill_all do
    project_ids = ClickHouseRepo.all(from(c in CoverageRun, distinct: true, select: c.project_id))
    Enum.each(project_ids, &backfill/1)
    length(project_ids)
  end

  defp rows(project_id, run, now) do
    run_id = run.test_run_id

    case evidence(project_id, run_id) do
      [] ->
        []

      evidence ->
        files = run_files(project_id, run)
        by_scope = Enum.group_by(evidence, &{elem(&1, 0), elem(&1, 1)}, &{elem(&1, 2), elem(&1, 3)})

        for test <- test_cases(project_id, run_id),
            own = Map.get(by_scope, {"test", Evidence.test_scope_id(test.module_name, test.suite_name, test.name)}),
            own != nil do
          suite =
            if test.suite_name == "",
              do: [],
              else: Map.get(by_scope, {"suite", Evidence.suite_scope_id(test.module_name, test.suite_name)}, [])

          touched = Enum.filter(own ++ suite, fn {path, _lines?} -> Map.has_key?(files, path) end)
          pairs = Enum.map(touched, fn {path, _lines?} -> {path, elem(files[path], 0)} end)

          %{
            project_id: project_id,
            git_repository_id: run.git_repository_id,
            test_case_id: test.test_case_id,
            fingerprint: fingerprint(pairs),
            paths: pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort(),
            unlined_paths:
              (
                for_result = for({path, false} <- touched, not elem(files[path], 1), do: path)
                for_result |> Enum.uniq() |> Enum.sort()
              ),
            passed: test.passed,
            test_run_id: run_id,
            git_commit_sha: run.git_commit_sha,
            ran_at: run.ran_at,
            inserted_at: now
          }
        end
    end
  end

  # The run's test and suite evidence, each shard's latest report: which
  # files each scope executed, and whether it recorded lines in them.
  defp evidence(project_id, run_id) do
    latest =
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^run_id and f.scope_kind in ["test", "suite"],
        group_by: [f.shard_index, f.scope_kind, f.scope_id],
        select: %{
          shard_index: f.shard_index,
          scope_kind: f.scope_kind,
          scope_id: f.scope_id,
          inserted_at: max(f.inserted_at)
        }
      )

    from(f in CoverageFile,
      join: l in subquery(latest),
      on:
        l.shard_index == f.shard_index and l.scope_kind == f.scope_kind and l.scope_id == f.scope_id and
          l.inserted_at == f.inserted_at,
      where: f.project_id == ^project_id and f.test_run_id == ^run_id and f.scope_kind in ["test", "suite"],
      group_by: [f.scope_kind, f.scope_id, f.path],
      select: {f.scope_kind, f.scope_id, f.path, fragment("min(notEmpty(?))", f.line_numbers)}
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn {kind, scope_id, path, lines?} -> {kind, scope_id, path, lines? == 1} end)
  end

  # What the run reported per path: its blob, the listing's when it reported
  # none, and whether it is test code.
  defp run_files(project_id, run) do
    reported =
      from(f in Coverage.report_files_for_runs(project_id, [run.test_run_id]),
        group_by: f.path,
        select:
          {f.path, fragment("argMaxIf(?, ?, ? != '')", f.git_blob_id, f.inserted_at, f.git_blob_id),
           fragment("min(?)", f.is_test)}
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn {path, blob, is_test} -> {path, {blob, is_test in [true, 1]}} end)

    missing = for {path, {"", _is_test}} <- reported, do: path
    listed = GitHistory.blobs_at(run.git_repository_id, run.git_commit_sha, missing)

    Map.new(reported, fn {path, {blob, is_test}} ->
      {path, {if(blob == "", do: Map.get(listed, path), else: blob), is_test}}
    end)
  end

  # The run's tests, and whether each passed: a test retried to a pass did.
  defp test_cases(project_id, run_id) do
    from(r in TestCaseRun,
      where: r.project_id == ^project_id and r.test_run_id == ^run_id and not is_nil(r.test_case_id),
      group_by: r.test_case_id,
      select: %{
        test_case_id: fragment("toString(?)", r.test_case_id),
        module_name: fragment("any(?)", r.module_name),
        suite_name: fragment("any(?)", r.suite_name),
        name: fragment("any(?)", r.name),
        passed: fragment("max(? = 'success')", r.status)
      }
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Enum.map(&%{&1 | passed: &1.passed in [true, 1]})
  end
end
