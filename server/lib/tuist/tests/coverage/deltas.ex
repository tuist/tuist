defmodule Tuist.Tests.Coverage.Deltas do
  @moduledoc """
  A complete commit's per-file coverage, stored once per change
  (`Tuist.Tests.CoverageFileDelta`) rather than merged from its runs' rows on
  every read, and its per-target totals (`Tuist.Tests.CoverageCommitTarget`).

  A commit takes part when it is complete (its pipeline signalled it
  finished) with a comparable figure (`Commits.comparable/1`) and a ref owns
  it. Its rows are keyed by its place on the first-parent tree, copied from
  `coverage_commits`, and read along its **chain**: its ref up to its
  position, then each ref it forks from up to the fork, the nearer ref
  winning for a path. A commit's files are each path's newest row along its
  chain, from the nearest checkpoint up.

  The rows a commit writes are what its final figures (`Commits.final_files/3`:
  coverage carried in for skipped tests applied) change from what the chain
  holds just below it: a row per changed path, and a tombstone
  (`executable_lines = 0`) per path below it the commit no longer has. When
  the delta rows its ref holds since the ref's last checkpoint would reach
  the commit's file count, it writes all of its files instead, a checkpoint.
  A ref that forked reads from its parent's checkpoint until then, so a
  short-lived branch stores no snapshot, and a read costs at most about
  three snapshots' rows.

  Whatever changes the rows below a commit invalidates its own, so every
  write that changes rows re-queues the commits right above it: the next
  complete commit on its ref and the first complete commit of each ref that
  forks between the two (`next_commits/2`). Above those the figures read the
  same, so nothing further moves. A commit whose place changes (a
  fast-forward, a rebuild of the refs) retires the rows at its old place and
  writes them at the new one.

  One project's writes run one at a time (`with_project_lock/2`), so a
  commit's rows are always computed against what is stored below it. A write
  only goes ahead when the files it read add up to the commit's published
  totals: the runs' rows expire, and replicas lag, and a write over a partial
  read would turn every missing file into a tombstone.

  Readers fall back to the raw rows while a commit's rows are not current
  (`current/2`): a commit without a ref, one not complete yet, one whose
  newest version or place has not been written.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.GitHistory.Ref
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Workers.DeltaWorker
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageCommitTarget
  alias Tuist.Tests.CoverageFileDelta

  require Logger

  # A write reads what every earlier write left; the pages read whatever the
  # replica has. A filter on a column that differs between a key's versions
  # (its kind, its commit) must see only the version `FINAL` keeps.
  @consistent [select_sequential_consistency: 1]
  @final_filter [optimize_move_to_prewhere_if_final: 0]
  @insert_chunk_size 5_000

  @doc "Queues the commit's rows to be (re)written, a few seconds from now so close folds are written once."
  def enqueue(project_id, sha), do: DeltaWorker.enqueue(project_id, sha)

  @doc "Whether the commit has rows to write: complete, with a comparable figure."
  def complete?(%{complete: true} = summary),
    do: summary.executable_lines > 0 or (summary.reported_kind == "reported" and summary.reported_executable_lines > 0)

  def complete?(_summary), do: false

  defp place(%{ref_id: ref_id, position: position} = summary) when is_integer(ref_id) and is_integer(position),
    do: if(complete?(summary), do: {ref_id, position})

  defp place(_summary), do: nil

  @doc "Runs `fun` holding the project's delta lock, once any other write of the project's finished."
  def with_project_lock(project_id, fun) do
    {:ok, result} =
      Repo.transaction(
        fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["coverage_deltas:#{project_id}"])
          fun.()
        end,
        timeout: to_timeout(minute: 5)
      )

    result
  end

  @doc """
  Writes the commit's rows and targets for its published version, retiring
  rows it left at a place it no longer holds, and re-queues the commits
  above whatever changed unless `cascade: false`. Call it holding the
  project's lock (`with_project_lock/2`). Returns `{:ok, %{rows:, checkpoint:}}`,
  `:skipped` when the commit has nothing to write, `:unavailable` when its
  runs' rows do not add up to its totals, or `:deferred` when a write is
  still pending for a commit below it on its chain (only while cascading).
  """
  def write(%Project{} = project, sha, opts \\ []) do
    summary = Commits.summary(project.id, sha)
    place = summary && place(summary)

    if (Keyword.get(opts, :cascade, true) and place) && pending_below?(project.id, sha, place),
      do: :deferred,
      else: write_at_place(project, sha, summary, place, opts)
  end

  # A pending write below a commit can be a cascade fixing a commit whose rows
  # are stale for a moment; computing over the chain then would keep that
  # moment, and the cascade, which stops where figures read the same again,
  # would never come back to it.
  defp pending_below?(project_id, sha, place) do
    pending =
      Repo.all(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(DeltaWorker) and j.state in ["available", "scheduled", "retryable"],
          where: fragment("(?->>'project_id')::bigint = ?", j.args, ^project_id),
          where: fragment("?->>'git_commit_sha' <> ?", j.args, ^sha),
          select: fragment("?->>'git_commit_sha'", j.args)
        )
      )

    pending != [] and
      Repo.exists?(
        from(c in CoverageCommit,
          where: c.project_id == ^project_id and c.git_commit_sha in ^pending and c.complete,
          where: ^below(chain(place, :below))
        )
      )
  end

  defp below(chain) do
    Enum.reduce(chain, dynamic(false), fn %{ref_id: ref_id, hi: hi}, acc ->
      dynamic([c], ^acc or (c.ref_id == ^ref_id and c.position <= ^hi))
    end)
  end

  defp write_at_place(project, sha, summary, place, opts) do
    moved = moved_rows(project.id, sha, place)
    retired = retire(moved)

    {outcome, changed?} =
      if summary && complete?(summary),
        do: write_complete(project, summary, place, moved),
        else: {:skipped, false}

    if Keyword.get(opts, :cascade, true) do
      places = if changed?, do: [place | retired], else: retired
      cascade(project.id, places, [sha])
    end

    outcome
  end

  defp cascade(project_id, places, written) do
    places
    |> Enum.flat_map(&next_commits(project_id, &1))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in written))
    |> Enum.each(&enqueue(project_id, &1))
  end

  defp write_complete(project, summary, place, moved) do
    case final_files(project, summary) do
      # The targets last: they mark the files as written.
      {:ok, source} ->
        written =
          if place,
            do: write_files(project.id, summary, place, source),
            else: {{:ok, %{rows: 0, checkpoint: false}}, false}

        if written != {:unavailable, false}, do: write_targets(summary, place, source.targets)
        written

      # Kept where the commit now is, and tried again for its own figures.
      :unavailable when not is_nil(place) and moved != [] ->
        if held_at?(project.id, summary.git_commit_sha, place) do
          {:unavailable, false}
        else
          {_outcome, changed?} = copy(summary, place, moved)
          {:unavailable, changed?}
        end

      :unavailable ->
        {:unavailable, false}
    end
  end

  # Where the figures the commit's pages show come from, with its targets,
  # provided they add up to its published totals. A commit coverage was
  # carried into reads them in Elixir (`Commits.final_files/3`: the carried
  # fold decides some of them) and sends them along with the write; any other
  # reads its runs' rows, and the write reads them again in ClickHouse, so
  # its files never reach Elixir.
  defp final_files(project, summary) do
    {covered, executable} =
      if Commits.carried?(summary),
        do: {summary.reported_covered_lines, summary.reported_executable_lines},
        else: {summary.covered_lines, summary.executable_lines}

    source =
      if Commits.carried?(summary),
        do: carried_source(project, summary),
        else: measured_source(project.id, summary)

    if source.covered_lines == covered and source.executable_lines == executable,
      do: {:ok, source},
      else: :unavailable
  end

  defp carried_source(project, summary) do
    files = Commits.final_files(project.id, summary.git_commit_sha, consistent: true)

    %{
      files: files,
      covered_lines: sum(files, :covered_lines),
      executable_lines: sum(files, :executable_lines),
      targets: Commits.targets_of(files)
    }
  end

  defp measured_source(project_id, summary) do
    case Commits.run_ids(project_id, summary.git_commit_sha) do
      [] ->
        %{sql: nil, covered_lines: 0, executable_lines: 0, targets: []}

      run_ids ->
        sql =
          Coverage.inline_sql(
            Coverage.merged_files_query_for_runs(project_id, run_ids, Coverage.excluded(project_id, []))
          )

        # Each file once for the totals, and once per target it belongs to.
        rows =
          """
          SELECT entry.1, entry.2, toUInt32(count()), toUInt64(sum(covered_lines)), toUInt64(sum(executable_lines))
          FROM (#{sql})
          ARRAY JOIN arrayConcat([(toUInt8(1), '')], arrayMap(t -> (toUInt8(0), toString(t)), targets)) AS entry
          GROUP BY entry.1, entry.2
          """
          |> ClickHouseRepo.query!(%{}, settings: @consistent)
          |> Map.fetch!(:rows)

        {totals, targets} = Enum.split_with(rows, fn [total | _] -> total == 1 end)
        [[_total, _name, _files, covered, executable]] = if totals == [], do: [[1, "", 0, 0, 0]], else: totals

        %{
          sql: sql,
          covered_lines: covered,
          executable_lines: executable,
          targets:
            Enum.map(targets, fn [_total, name, files, covered, executable] ->
              %{name: name, files_count: files, covered_lines: covered, executable_lines: executable}
            end)
        }
    end
  end

  defp sum(files, field), do: files |> Enum.map(&Map.fetch!(&1, field)) |> Enum.sum()

  @input "input('path String, covered_lines UInt64, executable_lines UInt64')"

  # Writes, in one `INSERT ... SELECT`, what the commit's files change from
  # what the chain holds just below it: a row per changed path and a
  # tombstone per path below it the commit no longer has, or all of its files
  # (a checkpoint) once the delta rows its ref holds since the ref's last
  # checkpoint would reach its file count. What is already at the place and
  # not written again is retired, and nothing is written when the place holds
  # exactly those rows already. The files come from `source`: the runs' rows,
  # read again here, or the carried commit's figures, sent as the query's
  # input. A read that no longer adds up to the totals `final_files/2`
  # checked (a replica behind, a report landing in between) stops the write
  # before it writes anything.
  defp write_files(project_id, summary, place, source) do
    before = place_state(project_id, place)
    version = max(before.max_version + 1, System.os_time(:microsecond))

    {current, body} =
      case source do
        %{files: files} ->
          {"SELECT path, covered_lines, executable_lines FROM #{@input}", [input_body(files)]}

        %{sql: sql} ->
          {"SELECT path, covered_lines, executable_lines FROM (#{sql})", %{}}
      end

    sql = """
    INSERT INTO coverage_file_deltas (project_id, ref_id, position, path, git_commit_sha, base_sha, kind,
      covered_lines, executable_lines, commit_version, committed_at, row_version, is_deleted)
    SELECT #{project_id}, #{elem(place, 0)}, #{elem(place, 1)}, path,
      if(in_rows, #{literal(summary.git_commit_sha)}, e_sha),
      if(in_rows, if(checkpoint, '', #{literal(base_sha(project_id, place))}), e_base),
      if(in_rows, new_kind, e_kind),
      if(in_rows, n_covered, e_covered), if(in_rows, n_executable, e_executable),
      if(in_rows, toUInt64(#{summary.version}), e_version),
      if(in_rows, fromUnixTimestamp64Micro(toInt64(#{to_usec(summary.committed_at)}), 'UTC'), e_committed_at),
      toUInt64(#{version}), toUInt8(NOT in_rows)
    FROM (
      SELECT *, sum(toUInt64(differs)) OVER () AS differences
      FROM (
        SELECT *, if(checkpoint, 'checkpoint', 'delta') AS new_kind,
          (in_rows != e_found) OR (in_rows AND (n_covered != e_covered OR n_executable != e_executable
            OR new_kind != e_kind OR e_sha != #{literal(summary.git_commit_sha)})) AS differs
        FROM (
          SELECT *, delta_rows + changes >= current AS checkpoint,
            if(delta_rows + changes >= current, n_found OR lost, changed OR lost) AS in_rows
          FROM (
            SELECT *,
              sum(b_delta_rows) OVER () AS delta_rows,
              sum(toUInt64(changed OR lost)) OVER () AS changes,
              sum(toUInt64(n_found)) OVER () AS current,
              sum(n_all_covered) OVER () AS covered_total,
              sum(n_all_executable) OVER () AS executable_total
            FROM (
              SELECT path,
                n.covered_lines AS n_all_covered, n.executable_lines AS n_all_executable,
                n.present AND n.executable_lines > 0 AS n_found,
                toUInt32(if(n_found, n.covered_lines, 0)) AS n_covered,
                toUInt32(if(n_found, n.executable_lines, 0)) AS n_executable,
                b.executable_lines > 0 AS b_live,
                b.delta_rows AS b_delta_rows,
                n_found AND NOT (b_live AND b.covered_lines = n_covered AND b.executable_lines = n_executable) AS changed,
                b_live AND NOT n_found AS lost,
                e.present AS e_found, e.covered_lines AS e_covered, e.executable_lines AS e_executable,
                e.kind AS e_kind, e.git_commit_sha AS e_sha, e.base_sha AS e_base, e.commit_version AS e_version,
                e.committed_at AS e_committed_at
              FROM (SELECT *, true AS present FROM (#{current})) AS n
              FULL OUTER JOIN (#{below_sql(project_id, place)}) AS b USING (path)
              FULL OUTER JOIN (#{at_place_sql(project_id, place)}) AS e USING (path)
            )
          )
        )
      )
    )
    WHERE throwIf(covered_total != #{source.covered_lines} OR executable_total != #{source.executable_lines},
        'coverage_rows_unavailable') = 0
      AND differences > 0 AND (in_rows OR e_found)
    """

    # The input follows the statement in the request's body, from the byte
    # after `FORMAT RowBinary`.
    sql = if body == %{}, do: sql, else: String.trim_trailing(sql) <> " FORMAT RowBinary"

    opts = [settings: @consistent ++ @final_filter ++ [join_use_nulls: 0], timeout: to_timeout(minute: 2)]
    opts = if body == %{}, do: opts, else: opts ++ [command: :insert, encode: false, cast_params: []]

    case IngestRepo.query(sql, body, opts) do
      {:ok, _result} ->
        after_write = place_state(project_id, place)
        changed? = {after_write.count, after_write.figures} != {before.count, before.figures}
        {{:ok, %{rows: after_write.count, checkpoint: after_write.checkpoint}}, changed?}

      {:error, %{message: message} = error} ->
        if String.contains?(message, "coverage_rows_unavailable"), do: {:unavailable, false}, else: raise(error)
    end
  end

  defp input_body(files) do
    files
    |> Enum.map(&[&1.path, &1.covered_lines, &1.executable_lines])
    |> Ch.RowBinary.encode_rows(["String", "UInt64", "UInt64"])
    |> IO.iodata_to_binary()
  end

  # What the chain holds per path just below the place, from its nearest
  # checkpoint up, and how many of its rows are the commit's own ref's delta
  # rows: a ref that forked reads its parent's checkpoint until its own
  # deltas would cost as much, so a short-lived branch never stores a
  # snapshot of its own.
  defp below_sql(project_id, place) do
    [%{ref_id: own_ref} | _] = chain = chain(place, :below)

    case from_checkpoint(project_id, chain, @consistent) do
      [] ->
        "SELECT '' AS path, toUInt32(0) AS covered_lines, toUInt32(0) AS executable_lines, toUInt64(0) AS delta_rows WHERE 0"

      segments ->
        Coverage.inline_sql(
          from(d in state_query(project_id, segments),
            select_merge: %{delta_rows: fragment("countIf(? = 'delta' AND ? = ?)", d.kind, d.ref_id, ^own_ref)}
          )
        )
    end
  end

  defp at_place_sql(project_id, {ref_id, position}) do
    """
    SELECT path, covered_lines, executable_lines, toString(kind) AS kind, git_commit_sha, base_sha, commit_version,
      committed_at, true AS present
    FROM coverage_file_deltas FINAL
    WHERE project_id = #{project_id} AND ref_id = #{ref_id} AND position = #{position}
    """
  end

  # What the place holds: how many rows, a fingerprint of their figures,
  # whether they are a checkpoint, and the newest row version written there
  # (retired rows included), which a write must exceed.
  defp place_state(project_id, {ref_id, position}) do
    where = "project_id = #{project_id} AND ref_id = #{ref_id} AND position = #{position}"

    [[count, figures, checkpoint, max_version]] =
      """
      SELECT count(), groupBitXor(cityHash64(path, covered_lines, executable_lines)), countIf(kind = 'checkpoint') > 0,
        (SELECT max(row_version) FROM coverage_file_deltas WHERE #{where})
      FROM coverage_file_deltas FINAL WHERE #{where}
      """
      |> ClickHouseRepo.query!(%{}, settings: @consistent ++ @final_filter)
      |> Map.fetch!(:rows)

    %{count: count, figures: figures, checkpoint: checkpoint in [true, 1], max_version: max_version}
  end

  defp literal(value), do: "'" <> String.replace(value, ["\\", "'"], &("\\" <> &1)) <> "'"

  defp to_usec(at), do: at |> usec() |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

  # The commit's place moved but its runs' rows are gone: what it stored at
  # its old place is kept as it was, compared with what was below it there.
  defp copy(summary, place, moved) do
    rows = Enum.map(moved, &Map.merge(&1, %{ref_id: elem(place, 0), position: elem(place, 1), is_deleted: 0}))
    changed? = replace_at(summary.project_id, place, rows)

    targets =
      summary.project_id
      |> current_targets(summary.git_commit_sha, @consistent)
      |> Enum.map(&Map.merge(&1, %{ref_id: elem(place, 0), position: elem(place, 1)}))

    insert(CoverageCommitTarget, targets)

    Logger.info("Coverage deltas of #{summary.git_commit_sha} copied to its new place without its runs' rows")
    {{:ok, %{rows: length(rows), checkpoint: false}}, changed?}
  end

  # Writes `rows` as everything the place holds: each place has one owner at
  # a time, so what is there and not in `rows` (another commit's after a
  # rebase, or a path that no longer differs) is retired. Returns whether the
  # figures there changed.
  defp replace_at(project_id, {ref_id, position}, rows) do
    existing =
      ClickHouseRepo.all(
        from(d in CoverageFileDelta,
          hints: ["FINAL"],
          where: d.project_id == ^project_id and d.ref_id == ^ref_id and d.position == ^position
        ),
        settings: @consistent
      )

    if stored(existing) == stored(rows) do
      false
    else
      version = row_version(existing)
      paths = MapSet.new(rows, & &1.path)
      retired = for row <- existing, not MapSet.member?(paths, row.path), do: %{delta_row(row) | is_deleted: 1}
      insert(CoverageFileDelta, Enum.map(rows, &Map.merge(delta_row(&1), %{row_version: version, is_deleted: 0})))
      insert(CoverageFileDelta, Enum.map(retired, &%{&1 | row_version: version}))
      figures(existing) != figures(rows)
    end
  end

  defp stored(rows),
    do: Map.new(rows, &{&1.path, {&1.covered_lines, &1.executable_lines, to_string(&1.kind), &1.git_commit_sha}})

  defp figures(rows), do: Map.new(rows, &{&1.path, {&1.covered_lines, &1.executable_lines}})

  @delta_fields ~w(project_id ref_id position path git_commit_sha base_sha kind covered_lines executable_lines commit_version committed_at row_version is_deleted)a

  defp delta_row(row) do
    row
    |> Map.take(@delta_fields)
    |> Map.update!(:kind, &to_string/1)
    |> Map.put_new(:row_version, 0)
    |> Map.put_new(:is_deleted, 0)
  end

  # Newer than every row it supersedes, whichever node's clock wrote them.
  defp row_version(rows), do: Enum.reduce(rows, System.os_time(:microsecond), &max(&1.row_version + 1, &2))

  # Retires the rows a commit left at places it no longer holds, returning
  # those places.
  defp retire([]), do: []

  defp retire(rows) do
    version = row_version(rows)
    insert(CoverageFileDelta, Enum.map(rows, &%{delta_row(&1) | row_version: version, is_deleted: 1}))
    rows |> Enum.map(&{&1.ref_id, &1.position}) |> Enum.uniq()
  end

  defp insert(_schema, []), do: :ok

  defp insert(schema, rows),
    do: rows |> Enum.chunk_every(@insert_chunk_size) |> Enum.each(&IngestRepo.insert_all(schema, &1))

  # The commit's rows anywhere but its place, by its SHA: rows left behind
  # by a move, usually none. The rows at its place stay in ClickHouse.
  defp moved_rows(project_id, sha, place) do
    query =
      from(d in CoverageFileDelta, hints: ["FINAL"], where: d.project_id == ^project_id and d.git_commit_sha == ^sha)

    query =
      case place do
        nil -> query
        {ref_id, position} -> from(d in query, where: not (d.ref_id == ^ref_id and d.position == ^position))
      end

    ClickHouseRepo.all(query, settings: @consistent ++ @final_filter)
  end

  defp held_at?(project_id, sha, {ref_id, position}) do
    ClickHouseRepo.exists?(
      from(d in CoverageFileDelta,
        hints: ["FINAL"],
        where: d.project_id == ^project_id and d.git_commit_sha == ^sha,
        where: d.ref_id == ^ref_id and d.position == ^position
      ),
      settings: @consistent ++ @final_filter
    )
  end

  defp write_targets(summary, place, targets) do
    {ref_id, position} = place || {0, 0}

    targets =
      case targets do
        # A marker, so the commit reads as written.
        [] -> [%{name: "", files_count: 0, covered_lines: 0, executable_lines: 0}]
        targets -> targets
      end

    insert(
      CoverageCommitTarget,
      Enum.map(targets, fn target ->
        %{
          project_id: summary.project_id,
          git_commit_sha: summary.git_commit_sha,
          target: target.name,
          files_count: target.files_count,
          covered_lines: target.covered_lines,
          executable_lines: target.executable_lines,
          commit_version: summary.version,
          ref_id: ref_id,
          position: position,
          committed_at: usec(summary.committed_at)
        }
      end)
    )
  end

  @target_fields ~w(project_id git_commit_sha target files_count covered_lines executable_lines commit_version ref_id position committed_at)a

  defp current_targets(project_id, sha, settings) do
    rows =
      ClickHouseRepo.all(
        from(t in CoverageCommitTarget,
          hints: ["FINAL"],
          where: t.project_id == ^project_id and t.git_commit_sha == ^sha
        ),
        settings: settings
      )

    case rows do
      [] ->
        []

      rows ->
        version = rows |> Enum.map(& &1.commit_version) |> Enum.max()
        rows |> Enum.filter(&(&1.commit_version == version)) |> Enum.map(&Map.take(&1, @target_fields))
    end
  end

  # The previous complete commit, what a delta row records it was compared
  # with: the newest one below the commit on its ref, then on each ref it
  # forks from at or below the fork.
  defp base_sha(project_id, place) do
    place
    |> chain(:below)
    |> Enum.find_value("", fn %{ref_id: ref_id, hi: hi} ->
      from(c in CoverageCommit,
        where: c.project_id == ^project_id and c.ref_id == ^ref_id and c.position <= ^hi and c.complete,
        order_by: [desc: c.position],
        limit: 1,
        select: c.git_commit_sha
      )
      |> Commits.comparable()
      |> Repo.one()
    end)
  end

  @doc """
  The commits whose rows were computed over what the place holds: the next
  complete commit above it on its ref and the first complete commit of each
  ref forking from it at or above the place and below that one, by SHA.
  """
  def next_commits(project_id, {ref_id, position}) do
    complete = Commits.comparable(from(c in CoverageCommit, where: c.project_id == ^project_id and c.complete))

    next =
      Repo.one(
        from(c in complete,
          where: c.ref_id == ^ref_id and c.position > ^position,
          order_by: [asc: c.position],
          limit: 1,
          select: %{sha: c.git_commit_sha, position: c.position}
        )
      )

    forks =
      from(r in Ref, where: r.parent_ref_id == ^ref_id and r.fork_position >= ^position, select: r.id)

    forks = if next, do: where(forks, [r], r.fork_position < ^next.position), else: forks

    firsts =
      Repo.all(
        from(c in complete,
          where: c.ref_id in subquery(forks),
          distinct: [asc: c.ref_id],
          order_by: [asc: c.ref_id, asc: c.position],
          select: c.git_commit_sha
        )
      )

    if(next, do: [next.sha], else: []) ++ firsts
  end

  defp chain(place, which), do: GitHistory.chain(place, which)

  # The chain cut at its nearest checkpoint: the segments nearer than the
  # checkpoint whole, and the checkpoint's own from its position up.
  defp from_checkpoint(project_id, chain, settings) do
    chain = Enum.filter(chain, &(&1.hi >= 0))

    checkpoints =
      if chain == [] do
        %{}
      else
        from(d in CoverageFileDelta,
          hints: ["FINAL"],
          where: d.project_id == ^project_id and d.kind == "checkpoint",
          where: ^within(Enum.map(chain, &Map.put(&1, :lo, 0))),
          group_by: d.ref_id,
          select: {d.ref_id, max(d.position)}
        )
        |> ClickHouseRepo.all(settings: settings ++ @final_filter)
        |> Map.new()
      end

    {segments, _found?} =
      Enum.map_reduce(chain, false, fn
        _segment, true ->
          {nil, true}

        %{ref_id: ref_id} = segment, false ->
          case Map.get(checkpoints, ref_id) do
            nil -> {Map.put(segment, :lo, 0), false}
            position -> {Map.put(segment, :lo, position), true}
          end
      end)

    Enum.reject(segments, &is_nil/1)
  end

  defp within(segments) do
    Enum.reduce(segments, dynamic(false), fn %{ref_id: ref_id, lo: lo, hi: hi}, acc ->
      dynamic([d], ^acc or (d.ref_id == ^ref_id and d.position >= ^lo and d.position <= ^hi))
    end)
  end

  # Each path's newest row along the segments, the nearest ref first.
  defp state_query(project_id, segments) do
    refs = Enum.map(segments, & &1.ref_id)

    from(d in CoverageFileDelta,
      hints: ["FINAL"],
      where: d.project_id == ^project_id,
      where: ^within(segments),
      group_by: d.path,
      select: %{
        path: d.path,
        covered_lines:
          fragment(
            "argMax(?, (-toInt64(indexOf(?, ?)), ?))",
            d.covered_lines,
            type(^refs, {:array, :integer}),
            d.ref_id,
            d.position
          ),
        executable_lines:
          fragment(
            "argMax(?, (-toInt64(indexOf(?, ?)), ?))",
            d.executable_lines,
            type(^refs, {:array, :integer}),
            d.ref_id,
            d.position
          )
      }
    )
  end

  @doc """
  Where the commit's file rows can be read: its place when its rows are
  current (written for its published version at the place it holds), or
  nil. `summary` is the commit's published row (`Commits.summary/2`).
  """
  def current(_project_id, nil), do: nil

  def current(project_id, summary) do
    with {ref_id, position} = place <- place(summary),
         [%{ref_id: ^ref_id, position: ^position} | _] <- written(project_id, summary) do
      place
    else
      _ -> nil
    end
  end

  # Of the commits, the version and place each one's rows were last written
  # for, by SHA, in one read: what `current/2` checks one commit at a time.
  defp written_places(project_id, shas) do
    from(t in CoverageCommitTarget,
      hints: ["FINAL"],
      where: t.project_id == ^project_id and t.git_commit_sha in ^shas,
      distinct: true,
      select: {t.git_commit_sha, t.commit_version, t.ref_id, t.position}
    )
    |> ClickHouseRepo.all()
    |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))
    |> Map.new(fn {sha, written} -> {sha, Enum.max_by(written, &elem(&1, 0))} end)
  end

  # The targets rows of the commit's published version, the marker of a
  # write for it.
  defp written(project_id, summary) do
    project_id
    |> current_targets(summary.git_commit_sha, [])
    |> Enum.filter(&(&1.commit_version == summary.version))
  end

  @doc """
  The commit's files as `Commits.final_files/3` lists them (path and line
  totals, by path), or nil when its rows are not current.
  """
  def files(project_id, sha) do
    summary = Commits.summary(project_id, sha)

    case current(project_id, summary) do
      nil ->
        nil

      place ->
        ClickHouseRepo.all(from(f in subquery(files_query(project_id, place)), order_by: f.path))
    end
  end

  # The commit's files with executable lines, path and line totals.
  defp files_query(project_id, place) do
    from(f in subquery(state_query(project_id, from_checkpoint(project_id, chain(place, :at), []))),
      where: f.executable_lines > 0,
      select: %{path: f.path, covered_lines: f.covered_lines, executable_lines: f.executable_lines}
    )
  end

  @doc """
  One page of the commit's files and their number, as `Commits.list_files/5`
  reads them (`search:`, `sort:`), or nil when its rows are not current.
  """
  def list_files(project_id, sha, page, page_size, opts \\ []) do
    summary = Commits.summary(project_id, sha)

    case current(project_id, summary) do
      nil ->
        nil

      place ->
        query = project_id |> files_query(place) |> subquery() |> Commits.search_paths(Keyword.get(opts, :search, ""))

        [files, count] =
          Tuist.Tasks.parallel_tasks([
            fn ->
              ClickHouseRepo.all(
                from(f in query,
                  order_by: ^Commits.files_order(Keyword.get(opts, :sort, {:coverage, :asc})),
                  limit: ^page_size,
                  offset: ^((page - 1) * page_size)
                )
              )
            end,
            fn -> ClickHouseRepo.one(from(f in query, select: count(f.path))) || 0 end
          ])

        {files, count}
    end
  end

  @doc """
  The commit's targets as `Commits.targets/3` lists them, least covered
  first, or nil when none were written for its published version.
  """
  def targets(project_id, sha) do
    summary = Commits.summary(project_id, sha)

    case summary && complete?(summary) && written(project_id, summary) do
      rows when is_list(rows) and rows != [] ->
        rows
        |> Enum.reject(&(&1.target == ""))
        |> Enum.map(
          &%{
            name: &1.target,
            files_count: &1.files_count,
            covered_lines: &1.covered_lines,
            executable_lines: &1.executable_lines
          }
        )
        |> Enum.sort_by(&{&1.covered_lines / max(&1.executable_lines, 1), &1.name})

      _ ->
        nil
    end
  end

  @doc """
  The files whose coverage moved most from `from_sha` to `to_sha`, at most
  `count`, as `Commits.changed_files/5` ranks them, or nil when either
  commit's rows are not current. On one ref, only the paths with rows
  between the two are compared.
  """
  def changed_files(project_id, from_sha, to_sha, count) do
    with from_place when not is_nil(from_place) <- current(project_id, Commits.summary(project_id, from_sha)),
         to_place when not is_nil(to_place) <- current(project_id, Commits.summary(project_id, to_sha)) do
      query =
        from(n in subquery(files_query(project_id, to_place)),
          join: o in subquery(files_query(project_id, from_place)),
          on: o.path == n.path,
          where:
            fragment(
              "round(? / ? * 100, 1) != round(? / ? * 100, 1)",
              n.covered_lines,
              n.executable_lines,
              o.covered_lines,
              o.executable_lines
            ),
          order_by: [
            desc:
              fragment("abs(? / ? - ? / ?)", n.covered_lines, n.executable_lines, o.covered_lines, o.executable_lines),
            desc: fragment("abs(toInt64(?) - toInt64(?))", n.covered_lines, o.covered_lines),
            asc: n.path
          ],
          limit: ^count,
          select: %{
            path: n.path,
            covered_lines: n.covered_lines,
            executable_lines: n.executable_lines,
            previous_covered_lines: o.covered_lines,
            previous_executable_lines: o.executable_lines
          }
        )

      query
      |> between(project_id, from_place, to_place)
      |> ClickHouseRepo.all()
      |> Enum.map(fn row ->
        change =
          Float.round(
            Coverage.percentage(row.covered_lines, row.executable_lines) -
              Coverage.percentage(row.previous_covered_lines, row.previous_executable_lines),
            1
          )

        Map.put(row, :change, change)
      end)
    else
      _ -> nil
    end
  end

  # Along one ref a path whose figure moved has a row above the older
  # commit and at or below the newer one.
  defp between(query, project_id, {ref_id, from_position}, {ref_id, to_position}) when from_position < to_position do
    paths =
      from(d in CoverageFileDelta,
        hints: ["FINAL"],
        where:
          d.project_id == ^project_id and d.ref_id == ^ref_id and d.position > ^from_position and
            d.position <= ^to_position,
        distinct: true,
        select: d.path
      )

    where(query, [n], n.path in subquery(paths))
  end

  defp between(query, _project_id, _from_place, _to_place), do: query

  @doc """
  A file's coverage at each of the commits whose rows are current, keyed by
  SHA, as `%{covered_lines:, executable_lines:}`, or nil at a commit without
  the file. `summaries` are the commits' published rows by SHA
  (`Commits.by_shas/2`). One path's rows along the commits' chains, read
  once.
  """
  def file_figures(_project_id, _path, summaries) when map_size(summaries) == 0, do: %{}

  def file_figures(project_id, path, summaries) do
    written = written_places(project_id, Map.keys(summaries))
    parents = %{}

    {places, _parents} =
      Enum.flat_map_reduce(summaries, parents, fn {sha, summary}, parents ->
        with {ref_id, position} = place <- place(summary),
             {version, ^ref_id, ^position} <- Map.get(written, sha),
             true <- version == summary.version do
          parents = Map.put_new_lazy(parents, ref_id, fn -> tl(chain({ref_id, 0}, :at)) end)
          {[{sha, [%{ref_id: ref_id, hi: elem(place, 1)} | parents[ref_id]]}], parents}
        else
          _ -> {[], parents}
        end
      end)

    refs = places |> Enum.flat_map(fn {_sha, chain} -> Enum.map(chain, & &1.ref_id) end) |> Enum.uniq()

    rows =
      if refs == [] do
        []
      else
        ClickHouseRepo.all(
          from(d in CoverageFileDelta,
            hints: ["FINAL"],
            where: d.project_id == ^project_id and d.path == ^path,
            where: fragment("? IN (?)", d.ref_id, type(^refs, {:array, :integer})),
            select: %{
              ref_id: d.ref_id,
              position: d.position,
              covered_lines: d.covered_lines,
              executable_lines: d.executable_lines
            }
          )
        )
      end

    Map.new(places, fn {sha, chain} ->
      case newest_along(rows, chain) do
        %{executable_lines: executable} = row when executable > 0 ->
          {sha, %{covered_lines: row.covered_lines, executable_lines: executable}}

        _ ->
          {sha, nil}
      end
    end)
  end

  defp newest_along(rows, chain) do
    Enum.find_value(chain, fn %{ref_id: ref_id, hi: hi} ->
      rows
      |> Enum.filter(&(&1.ref_id == ref_id and &1.position <= hi))
      |> Enum.max_by(& &1.position, fn -> nil end)
    end)
  end

  @doc """
  Writes the rows of the project's complete commits whose runs' rows are
  still kept, ref by ref, the refs that fork from none first and each ref's
  oldest commit first. History before that window keeps commit totals only.
  Returns how many commits were written and how many could not be.
  """
  def backfill(%Project{} = project) do
    cutoff = DateTime.add(DateTime.utc_now(), -(Environment.coverage_retention_days().files - 1), :day)

    commits =
      from(c in CoverageCommit,
        left_join: r in Ref,
        on: r.id == c.ref_id,
        where: c.project_id == ^project.id and c.complete and c.ran_at >= ^cutoff,
        order_by: [asc: is_nil(c.ref_id), asc: not is_nil(r.parent_ref_id), asc: c.ref_id, asc: c.position],
        select: %{sha: c.git_commit_sha, ref_id: c.ref_id, position: c.position}
      )
      |> Commits.comparable()
      |> Repo.all()

    {counts, written} =
      Enum.reduce(commits, {%{written: 0, unavailable: 0}, []}, fn commit, {counts, written} ->
        case with_project_lock(project.id, fn -> write(project, commit.sha, cascade: false) end) do
          {:ok, _rows} -> {Map.update!(counts, :written, &(&1 + 1)), [commit | written]}
          :unavailable -> {Map.update!(counts, :unavailable, &(&1 + 1)), written}
          :skipped -> {counts, written}
        end
      end)

    # Commits that completed while it ran were written over a chain it has
    # since filled in below them.
    places =
      for %{ref_id: ref_id} = commit <- written, not is_nil(ref_id), reduce: %{} do
        acc -> Map.update(acc, ref_id, commit.position, &max(&1, commit.position))
      end

    cascade(project.id, Enum.to_list(places), Enum.map(written, & &1.sha))
    counts
  end

  @doc "Backfills every project with complete commits (`backfill/1`), returning the counts by project id."
  def backfill_all do
    from(c in CoverageCommit, where: c.complete, distinct: true, select: c.project_id)
    |> Repo.all()
    |> Enum.flat_map(fn project_id ->
      case Projects.get_project_by_id(project_id) do
        nil -> []
        project -> [{project_id, backfill(project)}]
      end
    end)
    |> Map.new()
  end

  defp usec(%DateTime{microsecond: {value, _precision}} = at), do: DateTime.to_naive(%{at | microsecond: {value, 6}})
end
