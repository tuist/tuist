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
    {moved, kept} = project.id |> rows_of(sha) |> Enum.split_with(&({&1.ref_id, &1.position} != place))
    retired = retire(moved)

    {outcome, changed?} =
      if summary && complete?(summary),
        do: write_complete(project, summary, place, moved, kept),
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

  defp write_complete(project, summary, place, moved, kept) do
    case final_files(project, summary) do
      # The targets last: they mark the files as written.
      {:ok, files} ->
        written =
          if place,
            do: write_files(project.id, summary, place, files),
            else: {{:ok, %{rows: 0, checkpoint: false}}, false}

        write_targets(summary, place, files)
        written

      # Kept where the commit now is, and tried again for its own figures.
      :unavailable when not is_nil(place) and moved != [] and kept == [] ->
        {_outcome, changed?} = copy(summary, place, moved)
        {:unavailable, changed?}

      :unavailable ->
        {:unavailable, false}
    end
  end

  # The figures the commit's pages show, provided they add up to its
  # published totals.
  defp final_files(project, summary) do
    files = Commits.final_files(project.id, summary.git_commit_sha, consistent: true)

    {covered, executable} =
      if Commits.carried?(summary),
        do: {summary.reported_covered_lines, summary.reported_executable_lines},
        else: {summary.covered_lines, summary.executable_lines}

    if sum(files, :covered_lines) == covered and sum(files, :executable_lines) == executable,
      do: {:ok, files},
      else: :unavailable
  end

  defp sum(files, field), do: files |> Enum.map(&Map.fetch!(&1, field)) |> Enum.sum()

  defp write_files(project_id, summary, place, files) do
    below = read_state(project_id, chain(place, :below))

    current =
      for %{executable_lines: executable} = file <- files, executable > 0, into: %{}, do: {file.path, figure(file)}

    changed = Enum.reject(current, fn {path, figure} -> Map.get(below.files, path) == figure end)
    lost = for {path, _figure} <- below.files, not Map.has_key?(current, path), do: {path, {0, 0}}
    checkpoint? = below.delta_rows + length(changed) + length(lost) >= map_size(current)

    {kind, rows, base} =
      if checkpoint?,
        do: {"checkpoint", Enum.to_list(current) ++ lost, ""},
        else: {"delta", changed ++ lost, base_sha(summary.project_id, place)}

    rows =
      Enum.map(rows, fn {path, {covered, executable}} ->
        %{
          project_id: project_id,
          ref_id: elem(place, 0),
          position: elem(place, 1),
          path: path,
          git_commit_sha: summary.git_commit_sha,
          base_sha: base,
          kind: kind,
          covered_lines: covered,
          executable_lines: executable,
          commit_version: summary.version,
          committed_at: usec(summary.committed_at)
        }
      end)

    {{:ok, %{rows: length(rows), checkpoint: checkpoint?}}, replace_at(project_id, place, rows)}
  end

  defp figure(file), do: {file.covered_lines, file.executable_lines}

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

  # The commit's rows wherever they are, by its SHA.
  defp rows_of(project_id, sha) do
    ClickHouseRepo.all(
      from(d in CoverageFileDelta,
        hints: ["FINAL"],
        where: d.project_id == ^project_id and d.git_commit_sha == ^sha
      ),
      settings: @consistent ++ @final_filter
    )
  end

  defp write_targets(summary, place, files) do
    {ref_id, position} = place || {0, 0}

    targets =
      case Commits.targets_of(files) do
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

  # The commit's chain as ranges of positions per ref, nearest first:
  # `:at` includes the commit's own position, `:below` stops under it.
  defp chain({ref_id, position}, which) do
    hi = if which == :at, do: position, else: position - 1
    chain(ref_id, hi, MapSet.new([ref_id]))
  end

  defp chain(ref_id, hi, seen) do
    segment = %{ref_id: ref_id, hi: hi}

    case Repo.get(Ref, ref_id) do
      %Ref{parent_ref_id: parent_id, fork_position: fork} when not is_nil(parent_id) ->
        if MapSet.member?(seen, parent_id),
          do: [segment],
          else: [segment | chain(parent_id, fork, MapSet.put(seen, parent_id))]

      _ ->
        [segment]
    end
  end

  # What the chain holds per path, from its nearest checkpoint up, and how
  # many delta rows that took.
  # The delta rows counted are the commit's own ref's: a ref that forked reads
  # its parent's checkpoint until its own deltas would cost as much, so a
  # short-lived branch never stores a snapshot of its own.
  defp read_state(project_id, [%{ref_id: own_ref} | _] = chain) do
    segments = from_checkpoint(project_id, chain, @consistent)

    rows =
      if segments == [] do
        []
      else
        ClickHouseRepo.all(
          from(d in state_query(project_id, segments),
            select_merge: %{delta_rows: fragment("countIf(? = 'delta' AND ? = ?)", d.kind, d.ref_id, ^own_ref)}
          ),
          settings: @consistent
        )
      end

    %{
      files: for(%{executable_lines: executable} = row <- rows, executable > 0, into: %{}, do: {row.path, figure(row)}),
      delta_rows: rows |> Enum.map(& &1.delta_rows) |> Enum.sum()
    }
  end

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
