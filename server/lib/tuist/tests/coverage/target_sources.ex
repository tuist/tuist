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
  alias Tuist.Tests.Coverage.Xcode
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageTargetSource
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 2_000
  @pairs_per_query 400

  @doc "Records the targets the commit's runs (`Tuist.Tests.Coverage.Commits.runs/2`) can be a source of."
  def record(project_id, runs) do
    runs =
      Enum.filter(runs, fn run ->
        Map.get(run, :build_system) == "xcode" and Map.get(run, :git_repository_id) not in [nil, 0]
      end)

    by_id = Map.new(runs, &{&1.test_run_id, &1})
    run_ids = Map.keys(by_id)

    hashes =
      project_id
      |> Xcode.selective_testing_hashes(run_ids)
      |> Enum.reject(&(&1.name in narrowed_targets(by_id[&1.test_run_id])))

    evidenced = evidenced_targets(project_id, run_ids, hashes)
    failed = failed_targets(project_id, run_ids, hashes)
    now = NaiveDateTime.utc_now()

    hashes
    |> Enum.filter(
      &(MapSet.member?(evidenced, {&1.test_run_id, &1.name}) and not MapSet.member?(failed, {&1.test_run_id, &1.name}))
    )
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
  # all have executed: quarantine skips a few tests on every run, and the
  # run's other targets still ran whole.
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
