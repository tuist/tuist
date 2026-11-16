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

  Both are built inside ClickHouse from the run's `coverage_files`: the
  repository files of its report (its `run` scope), and its `test`, `suite`
  and `target` evidence over them. A test without evidence of its own in
  any of those files is `no_evidence`, which always selects it. A map is
  written under an id derived from what it's built from, so a fold that
  repeats writes nothing, and it's indexed in PostgreSQL only once its rows
  are in.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Instrumentation
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun

  @retention_days 31
  @paths_per_query 1_000
  @insert_chunk_size 10_000
  # Ranges per query, under ClickHouse's 128 KiB limit on a parameter.
  @ranges_chunk 5_000
  @zero_uuid "00000000-0000-0000-0000-000000000000"
  @settings [
    insert_quorum: "auto",
    insert_quorum_timeout: 10_000,
    select_sequential_consistency: 1,
    optimize_aggregation_in_order: 1,
    max_threads: 4,
    max_insert_threads: 2
  ]

  @doc "How long a snapshot is kept after its run, in days."
  def retention_days, do: @retention_days

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
      {full, partial} = Enum.split_with(runs, &(Map.get(&1, :partial) == false))

      # A scope's checkpoint holds every full run of it at the commit: a run
      # repeated without evidence doesn't hide the one that collected it.
      full
      |> Enum.group_by(&{&1.git_repository_id, &1.git_commit_sha, &1.scheme || "", &1.platform})
      |> Enum.each(fn {_scope, runs} -> write_checkpoint(project, runs) end)

      for run <- partial, run.test_impact_run_id, do: write_overlay(project, run)
    end

    :ok
  end

  @doc """
  Records the snapshots of the project's commits measured in the last `days`
  days from their runs' retained evidence, as their folds would have.
  """
  def backfill(%Project{} = project, days \\ 1) do
    since = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    from(c in CoverageCommit, where: c.project_id == ^project.id and c.ran_at >= ^since, select: c.git_commit_sha)
    |> Repo.all()
    |> Enum.each(&record(project, Commits.runs(project.id, &1)))
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
      order_by: [desc: s.ran_at],
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
      execute!(lines_sql(), params)

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
        on_conflict: {:replace, [:id, :repository_id, :git_branch, :test_run_ids, :tests_count, :ran_at, :expires_at]},
        conflict_target: {:unsafe_fragment, "(project_id, commit_sha, scheme, platform) WHERE kind = 'checkpoint'"}
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
    expires_at = expires_at(run.ran_at)

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
    execute!(lines_sql(), params)

    Repo.insert!(%Snapshot{
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
    })
  end

  # The impact run's diff from its baseline, whole and without a tracked file:
  # only then does a test the run didn't execute hold at its commit unless the
  # diff touches it.
  defp whole_diff(project, commit_sha, baseline_sha) do
    with {:ok, diff} <- Storage.get_diff(project.id, commit_sha, baseline_sha),
         true <- diff.changed_files_count == length(diff.changed_files) do
      tracked = Input.new(%{tracked_file_globs: GitHistory.settings(project).tracked_file_globs})
      if Enum.any?(diff.changed_files, &Input.tracked?(tracked, &1.path)), do: :tracked, else: {:ok, diff.changed_files}
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
      SELECT path, max(is_test) AS is_test FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)} AND scope_kind = 'run'
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
  # ranges. A suite's and a module's rows are numbered as their lowest test
  # (`scope_keys_sql/0`); one with no test in the snapshot has nothing to
  # carry and isn't written.
  defp lines_sql do
    """
    INSERT INTO test_impact_snapshot_lines (project_id, snapshot_id, path, scope, test_idx, line_ranges, expires_at)
    WITH report AS (
      SELECT path FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)} AND scope_kind = 'run'
      GROUP BY path
    ),
    -- A path a shard's replaced report repeats is written twice: readers
    -- union a scope's lines per file, so nothing deduplicates them here.
    scope_lines AS (
      SELECT scope_kind, scope_id, path, arraySort(line_numbers) AS lines FROM coverage_files
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
        AND scope_kind IN ('test', 'suite', 'target') AND path IN (SELECT path FROM report)
    ),
    #{named_tests_sql()},
    #{scope_keys_sql()},
    keyed AS (
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
    )
    SELECT {project_id:Int64}, {snapshot_id:UUID}, path, scope, idx,
      arrayFlatten(arrayMap(r -> [r[1], r[-1]],
        arraySplit((x, start) -> start, lines, arrayMap((x, i) -> i = 1 OR x != lines[i - 1] + 1, lines, arrayEnumerate(lines))))),
      {expires_at:DateTime}
    FROM keyed
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
  # Expands the `{idx:Array(UInt32)}` ranges of `idx_chunks/1` back into
  # `test_idx` rows.
  def idx_sql do
    """
    SELECT arrayJoin(arrayFlatten(arrayMap(i -> range({idx:Array(UInt32)}[2 * i - 1], {idx:Array(UInt32)}[2 * i] + 1),
      range(1, intDiv(length({idx:Array(UInt32)}), 2) + 1)))) AS test_idx
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
  def paths_per_query, do: @paths_per_query

  @doc false
  def query!(sql, params), do: IngestRepo.query!(sql, params, settings: [select_sequential_consistency: 1]).rows

  defp execute!(sql, params) do
    params = Map.put_new(params, :checkpoint_id, @zero_uuid)
    # ClickHouse's `DateTime` parameters take whole seconds.
    params = Map.update(params, :expires_at, nil, &DateTime.to_unix/1)
    IngestRepo.query!(sql, params, settings: @settings)
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

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
