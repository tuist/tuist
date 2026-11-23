defmodule Tuist.Tests.Coverage.TargetSources do
  @moduledoc """
  Where a test target selective testing skipped can carry its coverage from,
  found by the hash it was skipped with, the way selective testing found the
  hit: no walk of the commit's history.

  A commit's fold records, for each of its clean runs that executed a target
  whole (no identifier the caller narrowed or skipped the run by names it),
  passed it and recorded its `target` evidence, the run under the target's
  selective-testing hash.
  The same hash is the same target over the same inputs, so its tests and
  what they executed are the same; the per-file checks still run on what is
  carried (`Tuist.Tests.Coverage.Reported`). A run from another branch can
  be the source, as it can be selective testing's hit. A target with no row
  falls back to the commit's baseline: a run whose hashes landed after its
  commit was folded has none.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Instrumentation
  alias Tuist.Tests.Coverage.Xcode
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageTargetSource
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 2_000
  @pairs_per_query 400

  @doc "Records the targets the commit's runs (`Tuist.Tests.Coverage.Commits.runs/2`) can be a source of."
  def record(project_id, runs) do
    by_id = Map.new(runs, &{&1.test_run_id, &1})
    now = NaiveDateTime.utc_now()

    project_id
    |> sources(runs)
    |> Enum.map(fn %{test_run_id: run_id} = target ->
      run = by_id[run_id]

      %{
        project_id: project_id,
        target: target.name,
        selective_testing_hash: target.hash,
        test_run_id: run_id,
        git_commit_sha: run.git_commit_sha,
        git_repository_id: run.git_repository_id,
        ran_at: run.ran_at,
        inserted_at: now
      }
    end)
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(&IngestRepo.insert_all(CoverageTargetSource, &1))
  end

  @doc """
  Records again the sources of the targets a checkpoint copied
  (`Tuist.TestImpactAnalysis.Snapshots.record/3`), each `%{module, hash,
  source}`, so they outlive their first recording while copies of them do:
  the copy holds the target's rows, and its source run still names its tests.
  """
  def renew(project_id, repository_id, targets) do
    now = NaiveDateTime.utc_now()

    rows =
      for %{module: module, hash: hash, source: source} <- targets do
        %{
          project_id: project_id,
          target: module,
          selective_testing_hash: hash,
          test_run_id: source.run_id,
          git_commit_sha: source.sha,
          git_repository_id: repository_id,
          ran_at: naive(source.ran_at),
          inserted_at: now
        }
      end

    if rows != [], do: IngestRepo.insert_all(CoverageTargetSource, rows)
    :ok
  end

  defp naive(%DateTime{} = at), do: DateTime.to_naive(at)
  defp naive(%NaiveDateTime{} = at), do: at

  @doc """
  The targets the runs can be a source of, as `%{test_run_id, name, hash}`:
  each target a clean, instrumented Xcode run executed whole (no identifier
  the caller narrowed or skipped it by names it), passed and recorded its
  `target` evidence for, under its selective-testing hash.
  """
  def sources(project_id, runs) do
    runs =
      Enum.filter(runs, fn run ->
        Map.get(run, :build_system) == "xcode" and Map.get(run, :git_repository_id) not in [nil, 0]
      end)

    by_id = Map.new(runs, &{&1.test_run_id, &1})
    run_ids = Map.keys(by_id)

    # A run that took code from the cache without counters executed its tests
    # over counters that weren't there, so it says nothing about any target.
    uninstrumented = Instrumentation.uninstrumented_runs(project_id, runs)

    hashes =
      project_id
      |> Xcode.selective_testing_hashes(Enum.reject(run_ids, &MapSet.member?(uninstrumented, &1)))
      |> Enum.reject(&(&1.name in narrowed_targets(by_id[&1.test_run_id])))

    evidenced = evidenced_targets(project_id, run_ids, hashes)
    failed = failed_targets(project_id, run_ids, hashes)

    Enum.filter(
      hashes,
      &(MapSet.member?(evidenced, {&1.test_run_id, &1.name}) and not MapSet.member?(failed, {&1.test_run_id, &1.name}))
    )
  end

  @doc """
  The latest run recorded for each `{target, hash}` in the repository, as
  `%{{target, hash} => %{run_id:, sha:, ran_at:}}`. Merges keep one row per
  key, but until they run a key can have several, so the latest is picked.
  """
  def latest(_project_id, _repository_id, []), do: %{}

  def latest(project_id, repository_id, pairs) do
    wanted = MapSet.new(pairs)

    # A pair binds two parameters, its target and its hash.
    pairs
    |> Enum.chunk_every(@pairs_per_query)
    |> Enum.flat_map(fn chunk ->
      targets = chunk |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      hashes = chunk |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      ClickHouseRepo.all(
        from(s in CoverageTargetSource,
          where:
            s.project_id == ^project_id and s.git_repository_id == ^repository_id and s.target in ^targets and
              s.selective_testing_hash in ^hashes,
          group_by: [s.target, s.selective_testing_hash],
          select: {
            s.target,
            s.selective_testing_hash,
            fragment("toString(argMax(?, ?))", s.test_run_id, s.ran_at),
            fragment("argMax(?, ?)", s.git_commit_sha, s.ran_at),
            max(s.ran_at)
          }
        )
      )
    end)
    |> Enum.filter(fn {target, hash, _run_id, _sha, _ran_at} -> MapSet.member?(wanted, {target, hash}) end)
    |> Map.new(fn {target, hash, run_id, sha, ran_at} ->
      {{target, hash}, %{run_id: run_id, sha: sha, ran_at: ran_at}}
    end)
  end

  # The targets the caller's identifiers name, whose tests the run may not
  # all have executed: a skip names a few tests, and the run's other targets
  # still ran whole.
  defp narrowed_targets(run) do
    Enum.map(
      Map.get(run, :only_test_identifiers, []) ++ Map.get(run, :skip_test_identifiers, []),
      &(&1 |> String.split("/", parts: 2) |> hd())
    )
  end

  defp evidenced_targets(_project_id, _run_ids, []), do: MapSet.new()

  defp evidenced_targets(project_id, run_ids, hashes) do
    for targets <- hashes |> Enum.map(& &1.name) |> Enum.uniq() |> Coverage.id_chunks(length(run_ids)),
        pair <-
          ClickHouseRepo.all(
            from(f in CoverageFile,
              where:
                f.project_id == ^project_id and f.test_run_id in ^run_ids and f.scope_kind == "target" and
                  f.scope_id in ^targets,
              distinct: true,
              select: {fragment("toString(?)", f.test_run_id), f.scope_id}
            )
          ),
        into: MapSet.new(),
        do: pair
  end

  defp failed_targets(_project_id, _run_ids, []), do: MapSet.new()

  defp failed_targets(project_id, run_ids, hashes) do
    for targets <- hashes |> Enum.map(& &1.name) |> Enum.uniq() |> Coverage.id_chunks(length(run_ids)),
        pair <-
          ClickHouseRepo.all(
            from(r in TestCaseRun,
              where:
                r.project_id == ^project_id and r.test_run_id in ^run_ids and r.module_name in ^targets and
                  r.status == "failure",
              distinct: true,
              select: {fragment("toString(?)", r.test_run_id), r.module_name}
            )
          ),
        into: MapSet.new(),
        do: pair
  end
end
