defmodule Tuist.TestImpactAnalysis.Snapshots do
  @moduledoc """
  Writes and reads the test maps coverage-based test selection decides from
  (`Tuist.TestImpactAnalysis.Snapshot`): which repository files each test
  executed at a commit, kept for #{31} days.

  A commit's fold (`Tuist.Tests.Coverage.Commits.recompute/3`) records them
  from its clean, instrumented runs whose results are processed (`record/2`):

  - the newest full run of each scope (repository, scheme, platform) writes
    a **checkpoint**: every test it ran, numbered densely in module, suite
    and name order, and the inverted index from each file to the tests that
    executed it;
  - a run with an impact run whose baseline has a checkpoint writes an
    **overlay** against that checkpoint, keyed by the commit the impact run
    checked out: the tests it ran whose file set or status differs from the
    checkpoint, and as `stale` the tests it didn't run whose files changed
    since the checkpoint (`Tuist.TestImpactAnalysis.Candidate`). Every
    other test of the checkpoint holds at that commit too, so a later diff
    from it decides them. No overlay is written without the impact run's
    whole diff, or when it changed a tracked file.

  Both are built inside ClickHouse from the run's coverage: the repository
  files of its report (`coverage_run_files`), and its `test`, `suite` and
  `target` evidence over them (`coverage_files`). A test without evidence of its own in
  any of those files is `no_evidence`, which always selects it. A map is
  written under an id derived from what it's built from, so a fold that
  repeats writes nothing, and it's indexed in PostgreSQL only once its rows
  are in. The evidence expires two days after its report
  (`Tuist.Tests.Coverage.Evidence.retention_days/0`), so a run close to that
  age writes nothing: a commit folded again days later keeps the maps it
  has rather than writing them again from what's left.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Decision
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.Instrumentation
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun

  @retention_days 31
  @insert_chunk_size 10_000
  # Ranges per query, under ClickHouse's 128 KiB limit on a parameter.
  @ranges_chunk 5_000
  # Bytes of a `{…:Array(String)}` parameter per query, under that limit,
  # which open-source ClickHouse keeps by default and counts on the
  # URL-encoded value.
  @param_bytes 120_000
  @zero_uuid "00000000-0000-0000-0000-000000000000"
  # How long before its evidence starts expiring a run stops being written.
  @evidence_margin_seconds 3_600
  # A checkpoint of a large suite takes tens of seconds to write, beyond the
  # connection's default of 15.
  @write_timeout to_timeout(minute: 5)
  @settings [
    insert_quorum: "auto",
    insert_quorum_timeout: 10_000,
    select_sequential_consistency: 1,
    optimize_aggregation_in_order: 1,
    max_threads: 4,
    max_insert_threads: 2
  ]

  @doc """
  Records the snapshots of a commit's runs (`Tuist.Tests.Coverage.Commits.runs/2`).
  """
  def record(%Project{} = project, runs) do
    runs = Enum.filter(runs, &(Map.get(&1, :git_repository_id) not in [nil, 0] and fresh?(&1.ran_at)))
    processed = processed(project.id, Enum.map(runs, & &1.test_run_id))
    runs = Enum.filter(runs, &MapSet.member?(processed, &1.test_run_id))

    if runs != [] do
      uninstrumented = Instrumentation.uninstrumented_runs(project.id, runs)
      runs = Enum.reject(runs, &MapSet.member?(uninstrumented, &1.test_run_id))
      details = details(project.id, Enum.map(runs, & &1.test_run_id))
      runs = Enum.map(runs, &Map.merge(&1, Map.get(details, &1.test_run_id, %{platform: "", test_impact_run_id: nil})))
      whole = whole_evidence(project.id, runs)
      {full, partial} = Enum.split_with(runs, &(Map.get(&1, :partial) == false))

      # A scope's checkpoint holds every full run of it at the commit: a run
      # repeated without evidence doesn't hide the one that collected it.
      # Nor does one whose evidence may be gone: the scope's checkpoint that
      # has it stays the newest, and only a scope without one is written
      # from the runs whose evidence is whole.
      full
      |> Enum.group_by(&{&1.git_repository_id, &1.git_commit_sha, &1.scheme || "", &1.platform})
      |> Enum.each(fn {scope, runs} ->
        write_scope_checkpoint(project, scope, Enum.split_with(runs, &MapSet.member?(whole, &1.test_run_id)))
      end)

      for run <- partial, run.test_impact_run_id, MapSet.member?(whole, run.test_run_id), do: write_overlay(project, run)
    end

    :ok
  end

  # A scope's runs as `{whole, expired}` by their evidence (`whole_evidence/2`).
  defp write_scope_checkpoint(_project, _scope, {[], _expired}), do: :ok
  defp write_scope_checkpoint(project, _scope, {kept, []}), do: write_checkpoint(project, kept)

  defp write_scope_checkpoint(project, scope, {kept, _expired}) do
    if !checkpoint?(project.id, scope), do: write_checkpoint(project, kept)
  end

  # The runs whose evidence is still whole. Evidence expires
  # `Evidence.retention_days/0` after its report was inserted (the
  # `coverage_files` time-to-live), deleted part by part as merges reach it,
  # so a run past that age may have lost any of it, and a snapshot built from
  # what's left would read its tests as without evidence or with fewer files.
  # A report's rows share one `inserted_at` and its run rows
  # (`coverage_run_files`) outlive the evidence, so a run's oldest report is
  # read there; a run without such rows counts from when it ran. The margin covers a write's minutes and
  # the clocks.
  defp whole_evidence(project_id, runs) do
    cutoff = DateTime.add(DateTime.utc_now(), @evidence_margin_seconds - Evidence.retention_days() * 86_400, :second)

    reported =
      runs
      |> Enum.map(& &1.test_run_id)
      |> Coverage.id_chunks(1)
      |> Enum.flat_map(fn ids ->
        ClickHouseRepo.all(
          from(f in CoverageRunFile,
            where: f.project_id == ^project_id and f.test_run_id in ^ids,
            group_by: f.test_run_id,
            select: {f.test_run_id, min(f.inserted_at)}
          ),
          settings: [select_sequential_consistency: 1]
        )
      end)
      |> Map.new()

    for run <- runs,
        reported_at = Map.get(reported, run.test_run_id, run.ran_at),
        DateTime.after?(utc(reported_at), cutoff),
        into: MapSet.new(),
        do: run.test_run_id
  end

  defp checkpoint?(project_id, {repository_id, commit_sha, scheme, platform}) do
    Repo.exists?(
      from(s in Snapshot,
        where:
          s.project_id == ^project_id and s.repository_id == ^repository_id and s.commit_sha == ^commit_sha and
            s.kind == :checkpoint and s.scheme == ^scheme and s.platform == ^platform and
            s.expires_at > ^DateTime.utc_now()
      )
    )
  end

  @doc """
  Records the snapshots of the project's commits measured in the last `days`
  days from their runs' retained evidence, as their folds would have.
  """
  def backfill(%Project{} = project, days \\ 1) do
    since = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    runs =
      from(c in CoverageCommit,
        where: c.project_id == ^project.id and c.ran_at >= ^since,
        order_by: c.ran_at,
        select: c.git_commit_sha
      )
      |> Repo.all()
      |> Enum.map(&Commits.runs(project.id, &1))

    # Every checkpoint first: an overlay is written only against its
    # baseline's checkpoint, which a later commit in the list can hold.
    for commit_runs <- runs, do: record(project, Enum.filter(commit_runs, &(Map.get(&1, :partial) == false)))
    for commit_runs <- runs, do: record(project, commit_runs)
    :ok
  end

  @doc """
  The checkpoint at `commit_sha` for the scope, nil when there's none. An
  empty or nil `scheme`, or a nil `platform`, takes any one's newest.
  """
  def checkpoint(project_id, commit_sha, scheme, platform) do
    from(s in Snapshot,
      where:
        s.project_id == ^project_id and s.commit_sha == ^commit_sha and s.kind == :checkpoint and
          s.expires_at > ^DateTime.utc_now(),
      order_by: [desc: s.ran_at, desc: s.inserted_at],
      limit: 1
    )
    |> scheme_filter(scheme)
    |> platform_filter(platform)
    |> Repo.one()
  end

  defp platform_filter(query, nil), do: query
  defp platform_filter(query, platform), do: where(query, [s], s.platform == ^platform)

  @doc """
  The newest overlay of the branch for the scope that ran before `before`,
  at a commit other than `commit_sha`, with its checkpoint, as
  `{overlay, checkpoint}`; nil when there's none.
  """
  def latest_branch_overlay(_project_id, branch, _scope, _commit_sha, _before) when branch in [nil, ""], do: nil

  def latest_branch_overlay(project_id, branch, %{scheme: scheme, platform: platform}, commit_sha, before) do
    overlay =
      from(s in Snapshot,
        where:
          s.project_id == ^project_id and s.kind == :overlay and s.git_branch == ^branch and
            s.commit_sha != ^commit_sha and s.platform == ^(platform || "") and s.ran_at < ^before and
            s.expires_at > ^DateTime.utc_now(),
        order_by: [desc: s.ran_at],
        limit: 1
      )
      |> scheme_filter(scheme)
      |> Repo.one()

    with %Snapshot{} <- overlay, %Snapshot{} = checkpoint <- Repo.get(Snapshot, overlay.checkpoint_id) do
      {overlay, checkpoint}
    else
      _ -> nil
    end
  end

  defp scheme_filter(query, scheme) when scheme in [nil, ""], do: query
  defp scheme_filter(query, scheme), do: where(query, [s], s.scheme == ^scheme)

  @doc """
  The newest snapshot at `commit_sha` for the scope, a checkpoint over an
  overlay, as `%{checkpoint:, overlay:}` with the overlay nil for a
  checkpoint; nil when there's none.
  """
  def at(project_id, commit_sha, scheme, platform) do
    case checkpoint(project_id, commit_sha, scheme, platform) do
      %Snapshot{} = checkpoint -> %{checkpoint: checkpoint, overlay: nil}
      nil -> overlay_at(project_id, commit_sha, scheme, platform)
    end
  end

  defp overlay_at(project_id, commit_sha, scheme, platform) do
    overlay =
      from(s in Snapshot,
        where:
          s.project_id == ^project_id and s.commit_sha == ^commit_sha and s.kind == :overlay and
            s.platform == ^(platform || "") and s.expires_at > ^DateTime.utc_now(),
        order_by: [desc: s.ran_at],
        limit: 1
      )
      |> scheme_filter(scheme)
      |> Repo.one()

    overlay && %{checkpoint: Repo.get(Snapshot, overlay.checkpoint_id), overlay: overlay}
  end

  @doc """
  The repository files a test depends on in a snapshot (`at/4`), in path
  order, as `%{path:, executed:, target:}`: `executed` when the test or its
  suite's setup executed it, `target` when its module's processes executed
  it outside every test. Nil when the snapshot doesn't have the test.
  """
  def test_files(project_id, %{checkpoint: checkpoint, overlay: overlay}, test_case_id) do
    rows =
      query!(
        """
        SELECT toString(snapshot_id), test_idx, toString(status) FROM test_impact_snapshot_tests FINAL
        WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} AND test_case_id = {test_case_id:UUID}
        """,
        %{project_id: project_id, ids: layer_ids(checkpoint, overlay), test_case_id: test_case_id}
      )

    overlay_row = overlay && Enum.find(rows, fn [id, _idx, _status] -> id == overlay.id end)

    # Overridden: its own files are the overlay's; target-level ones may come from either.
    case_result =
      case {overlay_row, Enum.find(rows, fn [id, _idx, _status] -> id == checkpoint.id end)} do
        {nil, nil} ->
          nil

        {[_id, idx, _status], _} ->
          files(project_id, [overlay.id], idx, true) ++ files(project_id, [checkpoint.id], idx, false)

        {nil, [_id, idx, _status]} ->
          files(project_id, layer_ids(checkpoint, overlay), idx, true)
      end

    then(case_result, fn
      nil ->
        nil

      files ->
        files
        |> Enum.group_by(& &1.path)
        |> Enum.map(fn {path, rows} ->
          %{path: path, executed: Enum.any?(rows, & &1.executed), target: Enum.any?(rows, & &1.target)}
        end)
        |> Enum.sort_by(& &1.path)
    end)
  end

  defp files(project_id, ids, idx, executed?) do
    executed = if executed?, do: "bitmapContains(tests, {idx:UInt32})", else: "false"

    """
    SELECT path, max(#{executed}) AS executed, max(bitmapContains(target_tests, {idx:UInt32})) AS target
    FROM test_impact_snapshot_files
    WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)}
    GROUP BY path
    HAVING executed OR target
    """
    |> query!(%{project_id: project_id, ids: ids, idx: idx})
    |> Enum.map(fn [path, executed, target] ->
      %{path: path, executed: executed in [true, 1], target: target in [true, 1]}
    end)
  end

  defp layer_ids(checkpoint, nil), do: [checkpoint.id]
  defp layer_ids(checkpoint, overlay), do: [checkpoint.id, overlay.id]

  # Checkpoints

  defp write_checkpoint(project, runs) do
    run = Enum.max_by(runs, & &1.ran_at, NaiveDateTime)
    run_ids = runs |> Enum.map(& &1.test_run_id) |> Enum.sort()
    id = snapshot_id(["checkpoint", project.id, run.git_commit_sha, run.scheme, run.platform | run_ids])

    if !Repo.get(Snapshot, id) do
      expires_at = expires_at(run.ran_at)
      params = %{project_id: project.id, run_ids: run_ids, snapshot_id: id, expires_at: expires_at}

      execute!(
        """
        INSERT INTO test_impact_snapshot_tests
          (project_id, snapshot_id, test_idx, test_case_id, module_name, suite_name, status, files_hash, lines_hash, expires_at)
        WITH #{run_tests_sql()}
        SELECT {project_id:Int64}, {snapshot_id:UUID},
          toUInt32(row_number() OVER (ORDER BY m, s, n, test_case_id) - 1),
          test_case_id, m, s, status, files_hash, lines_hash, {expires_at:DateTime}
        FROM run_tests
        """,
        params
      )

      execute!(files_sql("snapshot_tests"), params)
      write_lines(project.id, params, run.ran_at)

      Repo.insert!(
        %Snapshot{
          id: id,
          project_id: project.id,
          repository_id: run.git_repository_id,
          commit_sha: run.git_commit_sha,
          kind: :checkpoint,
          scheme: run.scheme || "",
          platform: run.platform,
          git_branch: run.git_branch || "",
          test_run_ids: run_ids,
          tests_count: count(project.id, id),
          ran_at: utc(run.ran_at),
          expires_at: expires_at
        },
        # A commit's earlier checkpoints stay until they expire: the overlays
        # written against them read their numbering. Two folds of the commit
        # can write the same one at once.
        on_conflict: :nothing,
        conflict_target: :id
      )

      delete_expired(project.id)
    end

    id
  end

  # Overlays

  defp write_overlay(project, run) do
    with {:ok, impact_run} <- Storage.get_run(project.id, run.test_impact_run_id),
         baseline_sha when is_binary(baseline_sha) <- impact_run.baseline_sha,
         %Snapshot{} = checkpoint <- checkpoint(project.id, baseline_sha, run.scheme, run.platform),
         id = snapshot_id(["overlay", project.id, impact_run.id, checkpoint.id, run.test_run_id]),
         {:ok, changed_files} <- whole_diff(project, impact_run.commit_sha, baseline_sha) do
      if !Repo.get(Snapshot, id), do: insert_overlay(project, run, impact_run, checkpoint, id, changed_files)
      id
    else
      _ -> nil
    end
  end

  defp insert_overlay(project, run, impact_run, checkpoint, id, changed_files) do
    # Its tests not overridden are its checkpoint's, so it ends with it.
    expires_at = Enum.min([expires_at(run.ran_at), checkpoint.expires_at], DateTime)

    params = %{
      project_id: project.id,
      run_ids: [run.test_run_id],
      snapshot_id: id,
      checkpoint_id: checkpoint.id,
      expires_at: expires_at
    }

    execute!(
      """
      INSERT INTO test_impact_snapshot_tests
        (project_id, snapshot_id, test_idx, test_case_id, module_name, suite_name, status, files_hash, lines_hash, expires_at)
      WITH #{run_tests_sql()},
      checkpoint_tests AS (
        SELECT test_idx, test_case_id, status, files_hash, lines_hash FROM test_impact_snapshot_tests FINAL
        WHERE project_id = {project_id:Int64} AND snapshot_id = {checkpoint_id:UUID}
      )
      SELECT {project_id:Int64}, {snapshot_id:UUID},
        if(isNull(k.test_idx),
          (SELECT toUInt32(count()) FROM checkpoint_tests)
            + toUInt32(row_number() OVER (PARTITION BY isNull(k.test_idx) ORDER BY r.m, r.s, r.n, r.test_case_id) - 1),
          assumeNotNull(k.test_idx)),
        r.test_case_id, r.m, r.s, r.status, r.files_hash, r.lines_hash, {expires_at:DateTime}
      FROM run_tests AS r
      LEFT JOIN checkpoint_tests AS k ON k.test_case_id = r.test_case_id
      WHERE isNull(k.test_idx) OR toString(k.status) != r.status OR k.files_hash != r.files_hash
        OR k.lines_hash != r.lines_hash
      SETTINGS join_use_nulls = 1
      """,
      params
    )

    insert_stale(project.id, id, checkpoint, run, changed_files, expires_at)
    execute!(files_sql("snapshot_tests UNION ALL SELECT test_idx, m, s, n FROM checkpoint_module_tests"), params)
    write_lines(project.id, params, run.ran_at)

    Repo.insert!(
      %Snapshot{
        id: id,
        project_id: project.id,
        repository_id: run.git_repository_id,
        commit_sha: impact_run.commit_sha,
        kind: :overlay,
        checkpoint_id: checkpoint.id,
        base_sha: impact_run.baseline_sha,
        scheme: run.scheme || "",
        platform: run.platform,
        git_branch: impact_run.git_branch || run.git_branch || "",
        test_run_ids: [run.test_run_id],
        test_impact_run_id: impact_run.id,
        tests_count: checkpoint.tests_count,
        overridden_count: count(project.id, id),
        ran_at: utc(run.ran_at),
        expires_at: expires_at
      },
      on_conflict: :nothing,
      conflict_target: :id
    )
  end

  # The impact run's diff from its baseline, whole and without a tracked file:
  # only then does a test the run didn't execute hold at its commit unless the
  # diff touches it.
  defp whole_diff(project, commit_sha, baseline_sha) do
    with {:ok, diff} <- Storage.get_diff(project.id, commit_sha, baseline_sha),
         true <- diff.changed_files_count == length(diff.changed_files) do
      if Decision.tracked_path(project, diff.changed_files), do: :tracked, else: {:ok, diff.changed_files}
    end
  end

  @doc """
  The snapshot each of the runs was recorded in, by run id.
  """
  def for_runs(_project_id, []), do: %{}

  def for_runs(project_id, run_ids) do
    from(s in Snapshot,
      where: s.project_id == ^project_id and fragment("? && ?", s.test_run_ids, type(^run_ids, {:array, Ecto.UUID}))
    )
    |> Repo.all()
    |> Enum.flat_map(fn snapshot -> Enum.map(snapshot.test_run_ids, &{&1, snapshot}) end)
    |> Map.new()
  end

  # The checkpoint's tests the run didn't execute and the diff touches: their
  # evidence no longer holds at the overlay's commit.
  defp insert_stale(project_id, snapshot_id, checkpoint, run, changed_files, expires_at) do
    executed = executed_tests(project_id, run.test_run_id)

    project_id
    |> Candidate.evaluate(%{checkpoint: checkpoint, overlay: nil}, changed_files)
    |> Enum.reject(&(Candidate.unchanged?(&1) or &1.reason == :no_evidence or MapSet.member?(executed, &1.test_case_id)))
    |> Enum.map(& &1.idx)
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(fn idx ->
      execute!(
        """
        INSERT INTO test_impact_snapshot_tests
          (project_id, snapshot_id, test_idx, test_case_id, module_name, suite_name, status, files_hash, lines_hash, expires_at)
        SELECT project_id, {snapshot_id:UUID}, test_idx, test_case_id, module_name, suite_name, 'stale', 0, 0,
          {expires_at:DateTime}
        FROM test_impact_snapshot_tests FINAL
        WHERE project_id = {project_id:Int64} AND snapshot_id = {checkpoint_id:UUID} AND test_idx IN {idx:Array(UInt32)}
        """,
        %{
          project_id: project_id,
          snapshot_id: snapshot_id,
          checkpoint_id: checkpoint.id,
          idx: idx,
          expires_at: expires_at
        }
      )
    end)
  end

  defp executed_tests(project_id, run_id) do
    from(r in TestCaseRun,
      where: r.project_id == ^project_id and r.test_run_id == ^run_id and not is_nil(r.test_case_id),
      distinct: true,
      select: fragment("toString(?)", r.test_case_id)
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> MapSet.new()
  end

  # SQL

  # The run's repository files (its report's `run` scope, `is_test` for test
  # code), its evidence over them, and its tests with their status and a hash
  # of the files they and their suite's setup executed, and of the lines they
  # ran in them. The hashes are over each path's hash, grouped in the table's
  # order so groups stream: a shard's replaced report only repeats paths,
  # which the hashes ignore. A test the run only skipped didn't fail: it has
  # no evidence there. An overlay inserts with `join_use_nulls`, which makes
  # a test without evidence's `own` columns NULL instead of empty.
  defp run_tests_sql do
    """
    #{evidence_sql()},
    cases AS (
      SELECT assumeNotNull(test_case_id) AS test_case_id, any(module_name) AS m, any(suite_name) AS s, any(name) AS n,
        max(status = 'success') AS passed, max(status = 'failure') AS failed, max(is_flaky) AS flaky
      FROM test_case_runs
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)} AND test_case_id IS NOT NULL
      GROUP BY test_case_id
    ),
    scope_hashes AS (
      SELECT scope_kind, scope_id, groupArray(cityHash64(path)) AS hashes,
        groupArray(cityHash64(path, line_numbers)) AS line_hashes
      FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        AND scope_kind IN ('test', 'suite') AND path IN (SELECT path FROM report)
      GROUP BY project_id, test_run_id, shard_index, scope_kind, scope_id
    ),
    setup AS (
      SELECT scope_id, groupArrayArray(hashes) AS hashes, groupArrayArray(line_hashes) AS line_hashes
      FROM scope_hashes WHERE scope_kind = 'suite' GROUP BY scope_id
    ),
    own AS (
      SELECT o.scope_id AS scope_id, cityHash64(arraySort(arrayDistinct(arrayConcat(o.hashes, setup.hashes)))) AS files_hash,
        cityHash64(arraySort(arrayDistinct(arrayConcat(o.line_hashes, setup.line_hashes)))) AS lines_hash
      FROM (
        SELECT scope_id, groupArrayArray(hashes) AS hashes, groupArrayArray(line_hashes) AS line_hashes
        FROM scope_hashes WHERE scope_kind = 'test' GROUP BY scope_id
      ) AS o
      LEFT JOIN setup ON setup.scope_id = arrayStringConcat(arraySlice(splitByChar('\\x1F', o.scope_id), 1, 2), '\\x1F')
    ),
    run_tests AS (
      SELECT c.test_case_id AS test_case_id, c.m AS m, c.s AS s, c.n AS n,
        multiIf(c.failed AND NOT c.passed, 'failed', NOT c.passed OR ifNull(own.scope_id, '') = '', 'no_evidence',
          c.flaky, 'flaky', 'passed') AS status,
        ifNull(own.files_hash, 0) AS files_hash, ifNull(own.lines_hash, 0) AS lines_hash
      FROM cases AS c
      LEFT JOIN own ON own.scope_id = concat(c.m, '\\x1F', c.s, '\\x1F', c.n)
    )
    """
  end

  # The run's evidence over its repository files, as reported: a path a
  # shard's replaced report repeats is read twice, which every reader of it
  # tolerates (bitmaps, `DISTINCT`, target-only checks), so nothing holds the
  # whole evidence to deduplicate it.
  defp evidence_sql do
    """
    report AS (
      SELECT path, max(is_test) AS is_test FROM coverage_run_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
      GROUP BY path
    ),
    evidence AS (
      SELECT scope_kind, scope_id, path FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        AND scope_kind IN ('test', 'suite', 'target') AND path IN (SELECT path FROM report)
    )
    """
  end

  # The inverted index of the snapshot's tests that ran (not `stale`): who
  # executed each file, every test of the suites a test file belongs to, and
  # every test of a module whose processes executed it outside any test or
  # suite. `module_tests` lists the tests a suite or a module reaches: an
  # overlay's include its checkpoint's, as a suite's test file and a module's
  # target-level evidence belong to all of them.
  defp files_sql(module_tests) do
    """
    INSERT INTO test_impact_snapshot_files
      (project_id, snapshot_id, path, is_test, tests, suite_tests, target_tests, expires_at)
    WITH #{evidence_sql()},
    #{named_tests_sql()},
    checkpoint_module_tests AS (
      SELECT t.test_idx AS test_idx, t.module_name AS m, t.suite_name AS s, r.n AS n
      FROM test_impact_snapshot_tests AS t FINAL
      LEFT JOIN run_names AS r ON r.test_case_id = t.test_case_id
      WHERE t.project_id = {project_id:Int64} AND t.snapshot_id = {checkpoint_id:UUID}
        AND t.test_idx NOT IN (SELECT test_idx FROM snapshot_tests)
    ),
    module_tests AS (SELECT test_idx, m, s, n FROM #{module_tests}),
    pairs AS (
      SELECT e.path AS path, t.test_idx AS idx FROM evidence AS e
      INNER JOIN snapshot_tests AS t ON e.scope_id = concat(t.m, '\\x1F', t.s, '\\x1F', t.n)
      WHERE e.scope_kind = 'test'
      UNION ALL
      SELECT e.path AS path, t.test_idx AS idx FROM evidence AS e
      INNER JOIN snapshot_tests AS t ON e.scope_id = concat(t.m, '\\x1F', t.s)
      WHERE e.scope_kind = 'suite' AND t.s != ''
    ),
    test_file_scopes AS (
      SELECT DISTINCT path, scope_kind, scope_id, splitByChar('\\x1F', scope_id) AS parts FROM evidence
      WHERE scope_kind IN ('test', 'suite') AND path IN (SELECT path FROM report WHERE is_test)
    ),
    suite_pairs AS (
      SELECT f.path AS path, t.test_idx AS idx FROM test_file_scopes AS f
      INNER JOIN module_tests AS t ON t.m = f.parts[1] AND t.s = f.parts[2]
      WHERE f.parts[2] != ''
      UNION ALL
      SELECT f.path AS path, t.test_idx AS idx FROM test_file_scopes AS f
      INNER JOIN module_tests AS t ON f.scope_id = concat(t.m, '\\x1F', t.s, '\\x1F', t.n)
      WHERE f.scope_kind = 'test' AND f.parts[2] = ''
    ),
    target_paths AS (
      SELECT splitByChar('\\x1F', scope_id)[1] AS m, path FROM evidence
      GROUP BY m, path
      HAVING countIf(scope_kind != 'target') = 0
    ),
    target_pairs AS (
      SELECT p.path AS path, t.test_idx AS idx FROM target_paths AS p INNER JOIN module_tests AS t ON t.m = p.m
    ),
    all_pairs AS (
      SELECT path, idx, 1 AS kind FROM pairs
      UNION ALL SELECT path, idx, 2 AS kind FROM suite_pairs
      UNION ALL SELECT path, idx, 3 AS kind FROM target_pairs
    )
    SELECT {project_id:Int64}, {snapshot_id:UUID}, a.path, r.is_test,
      groupBitmapStateIf(a.idx, a.kind = 1),
      groupBitmapStateIf(a.idx, a.kind = 2),
      groupBitmapStateIf(a.idx, a.kind = 3),
      {expires_at:DateTime}
    FROM all_pairs AS a INNER JOIN report AS r ON r.path = a.path
    GROUP BY a.path, r.is_test
    """
  end

  # The lines each of the snapshot's tests that ran, each suite's setup and
  # each module's processes outside its tests ran per repository file, as
  # line sets: the snapshot points to each scope's set
  # (`test_impact_snapshot_lines`), and the sets the run's week doesn't hold
  # yet are written once (`test_impact_line_sets`) as the numbers of their
  # files' line patterns (`test_impact_line_patterns`), each file's distinct
  # lines written once a week under the week's path numbers
  # (`test_impact_line_paths`). A suite's and a module's sets are numbered as
  # their lowest test (`scope_keys_sql/0`); one with no test in the snapshot
  # has nothing to carry and isn't written.
  defp write_lines(project_id, params, ran_at) do
    epoch = epoch(ran_at)
    params = Map.merge(params, %{epoch: epoch, sets_expire_at: sets_expire_at(epoch)})

    execute!(line_refs_sql(), params)

    # Path and pattern numbers are allocated one writer at a time per
    # project, so the sets written after read every pattern they name.
    {:ok, _} =
      Repo.transaction(
        fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["test_impact_line_paths:#{project_id}"])
          execute!(paths_sql(), params)
          execute!(patterns_sql(), params)
        end,
        timeout: 2 * @write_timeout
      )

    execute!(line_sets_sql(), params)
  end

  # The run's repository files the week hasn't numbered yet, numbered after
  # the week's last.
  defp paths_sql do
    """
    INSERT INTO test_impact_line_paths (project_id, epoch, path, path_id, expires_at)
    WITH known AS (
      SELECT path, path_id FROM test_impact_line_paths
      WHERE project_id = {project_id:Int64} AND epoch = {epoch:Date}
    )
    SELECT {project_id:Int64}, {epoch:Date}, path,
      toUInt32((SELECT max(path_id) FROM known) + row_number() OVER (ORDER BY path)), {sets_expire_at:DateTime}
    FROM (
      SELECT DISTINCT path FROM coverage_run_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        AND path NOT IN (SELECT path FROM known)
    )
    """
  end

  # The files' lines of the sets the week doesn't hold yet that it hasn't
  # numbered either, numbered after the week's last in file order, so a set's
  # numbers, sorted, mostly step a little.
  defp patterns_sql do
    """
    INSERT INTO test_impact_line_patterns (project_id, epoch, pattern, path_id, line_ranges, expires_at)
    WITH #{new_set_lines_sql()},
    fresh AS (
      SELECT DISTINCT n.path_id AS path_id, k.ranges AS ranges
      FROM keyed AS k INNER JOIN numbers AS n ON n.path = k.path
      WHERE (n.path_id, k.ranges) NOT IN (SELECT path_id, line_ranges FROM known)
    )
    SELECT {project_id:Int64}, {epoch:Date},
      toUInt32((SELECT max(pattern) FROM known) + row_number() OVER (ORDER BY path_id, ranges)), path_id, ranges,
      {sets_expire_at:DateTime}
    FROM fresh
    """
  end

  # The sets the snapshot points to that the week doesn't hold yet, as their
  # files' pattern numbers.
  defp line_sets_sql do
    """
    INSERT INTO test_impact_line_sets (project_id, epoch, line_set, patterns, expires_at)
    WITH #{new_set_lines_sql()}
    SELECT {project_id:Int64}, {epoch:Date}, #{line_set_sql()} AS line_set, arraySort(groupArray(p.pattern)),
      {sets_expire_at:DateTime}
    FROM keyed AS k
    INNER JOIN numbers AS n ON n.path = k.path
    INNER JOIN known AS p ON p.path_id = n.path_id AND p.line_ranges = k.ranges
    GROUP BY k.scope, k.idx
    LIMIT 1 BY line_set
    """
  end

  # `keyed` (`keyed_lines_sql/1`) for the sets the snapshot points to that
  # the week doesn't hold yet, each from one scope that has it: only those
  # scopes' lines are read again. And the week's path numbers (`numbers`) and
  # patterns (`known`).
  defp new_set_lines_sql do
    """
    new_sets AS (
      SELECT toString(scope) AS scope, test_idx FROM test_impact_snapshot_lines
      WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
        AND line_set NOT IN (
          SELECT line_set FROM test_impact_line_sets WHERE project_id = {project_id:Int64} AND epoch = {epoch:Date}
        )
      LIMIT 1 BY line_set
    ),
    #{keyed_lines_sql("new_sets")},
    numbers AS (
      SELECT path, any(path_id) AS path_id FROM test_impact_line_paths
      WHERE project_id = {project_id:Int64} AND epoch = {epoch:Date}
      GROUP BY path
    ),
    known AS (
      SELECT pattern, path_id, line_ranges FROM test_impact_line_patterns
      WHERE project_id = {project_id:Int64} AND epoch = {epoch:Date}
    )
    """
  end

  defp line_refs_sql do
    """
    INSERT INTO test_impact_snapshot_lines (project_id, snapshot_id, scope, test_idx, epoch, line_set, expires_at)
    WITH #{keyed_lines_sql()}
    SELECT {project_id:Int64}, {snapshot_id:UUID}, k.scope, k.idx, {epoch:Date}, #{line_set_sql()}, {expires_at:DateTime}
    FROM keyed AS k
    GROUP BY k.scope, k.idx
    """
  end

  # A set is identified by its files and their lines, not by its scope or
  # anything else its run recorded, so identical evidence is shared. It
  # hashes each file's path and ranges, then the sorted hashes.
  defp line_set_sql do
    "sipHash64(arraySort(groupArray(reinterpretAsUInt128(sipHash128(k.path, k.ranges)))))"
  end

  # `keyed`: per scope (`scope`, `idx`), the lines it ran in each repository
  # file as ranges, only for the scopes a relation (`scope`, `test_idx`)
  # lists when one is given. A path a shard's replaced report repeats is
  # listed twice: readers union a scope's lines per file, so nothing
  # deduplicates them.
  defp keyed_lines_sql(scopes \\ nil) do
    """
    #{named_tests_sql()},
    #{scope_keys_sql()},
    #{scope_ids_sql(scopes)}
    report AS (
      SELECT path FROM coverage_run_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
      GROUP BY path
    ),
    scope_lines AS (
      SELECT scope_kind, scope_id, path, arraySort(line_numbers) AS lines FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        AND scope_kind IN ('test', 'suite', 'target') AND path IN (SELECT path FROM report)
        #{if scopes, do: "AND (scope_kind, scope_id) IN (SELECT kind, id FROM scope_ids)"}
    ),
    keyed_lines AS (
      SELECT l.path AS path, 'test' AS scope, t.test_idx AS idx, l.lines AS lines
      FROM scope_lines AS l INNER JOIN snapshot_tests AS t ON l.scope_id = concat(t.m, '\\x1F', t.s, '\\x1F', t.n)
      WHERE l.scope_kind = 'test'
      UNION ALL
      SELECT l.path, 'suite', k.test_idx, l.lines
      FROM scope_lines AS l INNER JOIN suite_keys AS k ON l.scope_id = concat(k.module_name, '\\x1F', k.suite_name)
      WHERE l.scope_kind = 'suite'
      UNION ALL
      SELECT l.path, 'target', k.test_idx, l.lines
      FROM scope_lines AS l INNER JOIN module_keys AS k ON l.scope_id = k.module_name
      WHERE l.scope_kind = 'target'
    ),
    keyed AS (
      SELECT path, scope, idx, #{ranges_sql("lines")} AS ranges FROM keyed_lines
    )
    """
  end

  @doc """
  SQL turning a sorted array of line numbers (`lines`, a column) into ranges
  `[first, last, first, last, …]`: a line starts one when it doesn't follow
  the previous, and ends one when the next doesn't follow it.
  """
  def ranges_sql(lines) do
    steps = "arrayMap(d -> d != 1, arrayDifference(#{lines}))"

    """
    if(empty(#{lines}), [], arrayFlatten(arrayMap((first, last) -> [first, last],
      arrayFilter((x, starts) -> starts, #{lines}, #{steps}),
      arrayFilter((x, ends) -> ends, #{lines}, arrayPushBack(arrayPopFront(#{steps}), 1)))))\
    """
  end

  # `scope_ids`: the evidence scope ids of the scopes a relation lists.
  defp scope_ids_sql(nil), do: ""

  defp scope_ids_sql(scopes) do
    """
    scope_ids AS (
      SELECT 'test' AS kind, concat(m, '\\x1F', s, '\\x1F', n) AS id FROM snapshot_tests
      WHERE ('test', test_idx) IN (SELECT scope, test_idx FROM #{scopes})
      UNION ALL
      SELECT 'suite', concat(module_name, '\\x1F', suite_name) FROM suite_keys
      WHERE ('suite', test_idx) IN (SELECT scope, test_idx FROM #{scopes})
      UNION ALL
      SELECT 'target', module_name FROM module_keys
      WHERE ('target', test_idx) IN (SELECT scope, test_idx FROM #{scopes})
    ),
    """
  end

  @doc """
  SQL defining `set_patterns` (`epoch`, `line_set`, `pattern`): the patterns
  of the line sets a `refs` relation (`epoch`, `line_set`) names, whose file
  (`path_id`) and lines (`line_ranges`, empty when only the file is known)
  `test_impact_line_patterns` holds. And `line_paths` (`epoch`, `path_id`,
  `path`): the paths of those weeks' numbers, to join once the patterns are
  narrowed or merged, since the sets share most of them.
  """
  def set_patterns_sql do
    """
    set_patterns AS (
      SELECT epoch, line_set, pattern FROM test_impact_line_sets
      ARRAY JOIN patterns AS pattern
      WHERE project_id = {project_id:Int64} AND (epoch, line_set) IN (SELECT epoch, line_set FROM refs)
    ),
    line_paths AS (
      SELECT epoch, path_id, any(path) AS path FROM test_impact_line_paths
      WHERE project_id = {project_id:Int64} AND epoch IN (SELECT epoch FROM refs)
      GROUP BY epoch, path_id
    )
    """
  end

  # The snapshot's tests that ran (not `stale`), named by the runs' test case
  # runs: a name is only matched against the runs' own evidence, which names
  # only tests that ran there.
  defp named_tests_sql do
    """
    run_names AS (
      SELECT assumeNotNull(test_case_id) AS test_case_id, any(name) AS n FROM test_case_runs
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)} AND test_case_id IS NOT NULL
      GROUP BY test_case_id
    ),
    snapshot_tests AS (
      SELECT t.test_idx AS test_idx, t.module_name AS m, t.suite_name AS s, r.n AS n
      FROM test_impact_snapshot_tests AS t FINAL
      INNER JOIN run_names AS r ON r.test_case_id = t.test_case_id
      WHERE t.project_id = {project_id:Int64} AND t.snapshot_id = {snapshot_id:UUID} AND t.status != 'stale'
    )
    """
  end

  @doc """
  SQL defining `suite_keys` (`module_name`, `suite_name`, `test_idx`) and
  `module_keys` (`module_name`, `test_idx`): the number a suite's or a
  module's rows of `test_impact_snapshot_lines` have, its lowest test's in
  the numbering of `{snapshot_id:UUID}`, and of its checkpoint
  `{checkpoint_id:UUID}` when it's an overlay (the zero UUID otherwise).
  """
  def scope_keys_sql do
    """
    numbering AS (
      SELECT test_idx, module_name, suite_name FROM test_impact_snapshot_tests
      WHERE project_id = {project_id:Int64} AND snapshot_id IN ({snapshot_id:UUID}, {checkpoint_id:UUID})
    ),
    suite_keys AS (
      SELECT module_name, suite_name, min(test_idx) AS test_idx FROM numbering WHERE suite_name != ''
      GROUP BY module_name, suite_name
    ),
    module_keys AS (SELECT module_name, min(test_idx) AS test_idx FROM numbering GROUP BY module_name)
    """
  end

  @doc """
  The names of the snapshot's tests numbered `idx`, as `%{idx => %{module,
  suite, name}}`, read from `test_cases` by the modules' range of its sort
  key. A test `test_cases` has no row for is missing: a caller that lists
  tests by name selects it instead.
  """
  def names(_project_id, _layers, []), do: %{}

  def names(project_id, %{checkpoint: checkpoint} = layers, idx) do
    overlay = Map.get(layers, :overlay)

    idx
    |> idx_chunks()
    |> Enum.flat_map(fn chunk ->
      query!(
        """
        WITH tests AS (
          SELECT test_idx, any(test_case_id) AS test_case_id, any(module_name) AS module_name,
            any(suite_name) AS suite_name
          FROM test_impact_snapshot_tests
          WHERE project_id = {project_id:Int64} AND snapshot_id IN ({checkpoint_id:UUID}, {overlay_id:UUID})
            AND test_idx IN (#{idx_sql()})
          GROUP BY test_idx
        )
        SELECT t.test_idx, t.module_name, t.suite_name, c.name FROM tests AS t
        INNER JOIN (
          SELECT DISTINCT id, name FROM test_cases
          WHERE project_id = {project_id:Int64} AND module_name IN (SELECT module_name FROM tests)
        ) AS c ON c.id = t.test_case_id
        """,
        %{
          project_id: project_id,
          checkpoint_id: checkpoint.id,
          overlay_id: if(overlay, do: overlay.id, else: @zero_uuid),
          idx: chunk
        }
      )
    end)
    |> Map.new(fn [i, module, suite, name] -> {i, %{module: module, suite: suite, name: name}} end)
  end

  @doc false
  # Test numbers as flat `[first, last, …]` arrays of consecutive runs, a
  # query's worth each. Tests of a suite and module are numbered
  # contiguously, so a skip list of any size fits in few ranges.
  def idx_chunks(idx) do
    idx
    |> Enum.uniq()
    |> Enum.sort()
    |> idx_ranges()
    |> Enum.chunk_every(@ranges_chunk)
    |> Enum.map(&Enum.flat_map(&1, fn {first, last} -> [first, last] end))
  end

  @doc false
  # Expands the ranges of `idx_chunks/1` in the `Array(UInt32)` parameter
  # `param` back into `test_idx` rows.
  def idx_sql(param \\ "idx") do
    idx = "{#{param}:Array(UInt32)}"

    """
    SELECT arrayJoin(arrayFlatten(arrayMap(i -> range(#{idx}[2 * i - 1], #{idx}[2 * i] + 1),
      range(1, intDiv(length(#{idx}), 2) + 1)))) AS test_idx
    """
  end

  defp idx_ranges([]), do: []

  defp idx_ranges([first | rest]) do
    {ranges, current} =
      Enum.reduce(rest, {[], {first, first}}, fn
        idx, {ranges, {a, b}} when idx == b + 1 -> {ranges, {a, idx}}
        idx, {ranges, range} -> {[range | ranges], {idx, idx}}
      end)

    Enum.reverse([current | ranges])
  end

  defp count(project_id, snapshot_id) do
    [[count]] =
      query!(
        """
        SELECT count() FROM test_impact_snapshot_tests FINAL
        WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
        """,
        %{project_id: project_id, snapshot_id: snapshot_id}
      )

    count
  end

  @doc false
  # Paths as a query's worth each, measured as the driver sends them in the
  # request URL: each quoted, its quotes and backslashes doubled, then
  # URL-encoded, where a `/` takes three bytes, and a comma. Long paths make a
  # fixed count of them too large for one parameter.
  def path_chunks(paths) do
    Enum.chunk_while(
      paths,
      {[], 0},
      fn path, {chunk, size} ->
        bytes = encoded_size(path, 9)

        if chunk != [] and size + bytes > @param_bytes,
          do: {:cont, Enum.reverse(chunk), {[path], bytes}},
          else: {:cont, {[path | chunk], size + bytes}}
      end,
      fn
        {[], _size} -> {:cont, {[], 0}}
        {chunk, _size} -> {:cont, Enum.reverse(chunk), {[], 0}}
      end
    )
  end

  # The path's bytes once quoted and URL-encoded, counted without building
  # either (`acc` starts with its quotes and comma, 3 bytes each): a byte
  # `URI.encode_www_form/1` keeps, or turns into `+`, is 1, a quote or
  # backslash 6 once doubled, any other 3.
  defp encoded_size(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in [?-, ?., ?_, ?~, ?\s], do: encoded_size(rest, acc + 1)

  defp encoded_size(<<c, rest::binary>>, acc) when c in [?', ?\\], do: encoded_size(rest, acc + 6)
  defp encoded_size(<<_c, rest::binary>>, acc), do: encoded_size(rest, acc + 3)
  defp encoded_size(<<>>, acc), do: acc

  @doc false
  def query!(sql, params), do: IngestRepo.query!(sql, params, settings: [select_sequential_consistency: 1]).rows

  defp execute!(sql, params) do
    params = Map.put_new(params, :checkpoint_id, @zero_uuid)
    # ClickHouse's `DateTime` parameters take whole seconds.
    params = Map.update(params, :expires_at, nil, &DateTime.to_unix/1)
    params = Map.update(params, :sets_expire_at, nil, &DateTime.to_unix/1)
    IngestRepo.query!(sql, params, settings: @settings, timeout: @write_timeout)
  end

  # The runs whose results are processed: they have test case runs, written
  # after their evidence. A fold can run before, at the run's creation, and a
  # snapshot it wrote would hold none of the run's tests, while its id, derived
  # from the runs, would keep the fold after processing from writing another.
  defp processed(_project_id, []), do: MapSet.new()

  defp processed(project_id, run_ids) do
    run_ids
    |> Coverage.id_chunks(1)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(r in TestCaseRun,
          where: r.project_id == ^project_id and r.test_run_id in ^ids,
          distinct: true,
          select: r.test_run_id
        ),
        settings: [select_sequential_consistency: 1]
      )
    end)
    |> MapSet.new()
  end

  defp details(_project_id, []), do: %{}

  defp details(project_id, run_ids) do
    platforms =
      run_ids
      |> Coverage.id_chunks(1)
      |> Enum.flat_map(fn ids ->
        ClickHouseRepo.all(
          from(r in CoverageRun,
            where: r.project_id == ^project_id and r.test_run_id in ^ids,
            group_by: r.test_run_id,
            select: {r.test_run_id, fragment("argMax(?, ?)", r.platform, r.version)}
          )
        )
      end)
      |> Map.new()

    impact_runs =
      run_ids
      |> Coverage.id_chunks(1)
      |> Enum.flat_map(fn ids ->
        ClickHouseRepo.all(
          from(t in Test,
            where: t.project_id == ^project_id and t.id in ^ids,
            group_by: t.id,
            select: {t.id, fragment("toString(argMax(?, ?))", t.test_impact_run_id, t.inserted_at)}
          )
        )
      end)
      |> Map.new(fn {id, impact_run_id} -> {id, if(impact_run_id in [nil, ""], do: nil, else: impact_run_id)} end)

    Map.new(run_ids, fn id ->
      {id, %{platform: Map.get(platforms, id, ""), test_impact_run_id: Map.get(impact_runs, id)}}
    end)
  end

  defp delete_expired(project_id) do
    Repo.delete_all(from(s in Snapshot, where: s.project_id == ^project_id and s.expires_at <= ^DateTime.utc_now()))
  end

  defp snapshot_id(parts) do
    <<a::binary-6, _::4, b::bits-12, _::2, c::bits-62, _::binary>> =
      :crypto.hash(:sha256, Enum.map_join(parts, <<0>>, &to_string/1))

    Ecto.UUID.load!(<<a::binary, 5::4, b::bits, 2::2, c::bits>>)
  end

  defp fresh?(ran_at), do: DateTime.after?(expires_at(ran_at), DateTime.utc_now())

  defp expires_at(ran_at), do: ran_at |> utc() |> DateTime.add(@retention_days * 86_400, :second)

  # The week whose line sets a snapshot of a run at `ran_at` points to: the
  # Monday that started it. A week's sets expire `@retention_days` after it
  # ends, after every snapshot of a run in it.
  defp epoch(ran_at), do: ran_at |> utc() |> DateTime.to_date() |> Date.beginning_of_week()

  defp sets_expire_at(epoch), do: DateTime.new!(Date.add(epoch, 7 + @retention_days), ~T[00:00:00], "Etc/UTC")

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
