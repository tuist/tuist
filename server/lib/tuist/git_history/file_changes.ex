defmodule Tuist.GitHistory.FileChanges do
  @moduledoc """
  A listed commit's files, stored as the paths it changed
  (`Tuist.GitHistory.FileChange`) rather than as its whole listing.

  A commit takes part once its listing is stored whole (not truncated) and a
  ref owns it. Its rows are keyed by its place on the first-parent tree and
  read along its **chain** (`Tuist.GitHistory.chain/2`): its ref up to its
  position, then each ref it forks from up to the fork, the nearer ref
  winning for a path. A commit's files are each path's newest row along its
  chain, without the paths whose newest row has no blob.

  The rows a commit writes are what its listing changes from what the chain
  holds just below it: a row per path whose blob or mode differs, and a row
  without a blob per path below it the listing no longer has. The first
  listed commit of a chain writes every file.

  Listings arrive in any order, and a commit written below others would
  change what they read. So every write that adds or removes rows first
  gives the written commits right above the place (`above/3`) a row of their
  own for each path involved, holding what they read until then. Their
  files stay what their listings said, and the paths between two commits'
  rows are at least the paths that differ between them.

  The place a commit's rows were written for is kept on its listing
  (`changes_ref_id`, `changes_position`), with how many rows it holds
  (`changes_count`): what a ref's commits add up to since some position is
  what reading its files from there costs. A commit whose place changed (a
  fast-forward, a rebuild of the refs) is queued again and written at the
  new place from its listing, or, once the listing expired, from the rows it
  left at the old one. Only rows that would move up their own ref (a commit
  that arrived late was slotted in below them) are not copied but retired:
  every commit above would be copied onto the rows of the next, so those
  commits' files are unknown until they are listed again.

  The rows of a ref that forks from none are kept. Any other ref's rows
  expire together, since a commit's files read every row below it:
  `changes_expires_at` on the listing says until when. That is the file
  retention after the ref was last renewed: a write on a ref whose rows have
  less than half of it left gives them all of it again, so a branch that
  keeps receiving commits (a development or release branch) keeps its rows.

  One repository's writes run one at a time, under its ref lock, so a
  commit's place holds while its rows are written against what is stored
  below it.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.GitHistory.Commit
  alias Tuist.GitHistory.CommitFile
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.FileChange
  alias Tuist.GitHistory.Ref
  alias Tuist.GitHistory.Workers.FileChangesWorker
  alias Tuist.IngestRepo
  alias Tuist.Repo

  @consistent [select_sequential_consistency: 1]
  @kept ~U[2100-01-01 00:00:00Z]
  @columns "repository_id, ref_id, position, generation, sha, path, git_blob_id, mode, expires_at, row_version, is_deleted"

  @doc "Queues the commit's file changes to be written at its place."
  def enqueue(repository_id, sha), do: FileChangesWorker.enqueue(repository_id, sha)

  @doc """
  Queues the listed commits whose file changes are not written at the place
  they hold, lowest position first: all of the repository's, or those among
  `shas`.
  """
  def enqueue_moved(repository_id, shas \\ nil)

  def enqueue_moved(_repository_id, []), do: :ok

  def enqueue_moved(repository_id, shas) do
    query =
      from(l in CommitListing,
        join: c in Commit,
        on: c.repository_id == l.repository_id and c.sha == l.sha,
        where: l.repository_id == ^repository_id and not l.truncated,
        where: fragment("(?, ?) IS DISTINCT FROM (?, ?)", l.changes_ref_id, l.changes_position, c.ref_id, c.position),
        order_by: [asc_nulls_first: c.position],
        select: l.sha
      )

    query = if shas, do: where(query, [l], l.sha in ^Enum.uniq(shas)), else: query
    query |> Repo.all() |> Enum.each(&enqueue(repository_id, &1))
  end

  @doc """
  Writes the commit's file changes at the place it holds, retiring the rows
  it left at a place it no longer holds. Returns `:written`; `:moved` when
  the rows were copied from its old place, or `:deferred` while a commit
  below it is queued to move first; `:current` when they are already there;
  `:pending` while no ref owns the commit; `:unavailable` when its listing's
  rows do not add up to its file count; or `:skipped` when it has no whole
  listing to write from, or would be copied above a commit that is not
  going to move, or up its own ref (its rows are retired).
  """
  def write(repository_id, sha) do
    GitHistory.with_refs_lock(repository_id, fn ->
      listing = Repo.one(from(l in CommitListing, where: l.repository_id == ^repository_id and l.sha == ^sha))
      if listing && not listing.truncated, do: write_at_place(listing, commit(repository_id, sha)), else: :skipped
    end)
  end

  defp commit(repository_id, sha) do
    Repo.one(
      from(c in Commit,
        where: c.repository_id == ^repository_id and c.sha == ^sha and not is_nil(c.ref_id),
        select: %{place: {c.ref_id, c.position}, generation: c.generation}
      )
    )
  end

  defp write_at_place(listing, commit) do
    place = commit && commit.place
    written = written(listing)

    cond do
      place && written == place ->
        :current

      is_nil(place) ->
        if written, do: retire(listing, written)
        mark(listing, nil, nil, nil)
        :pending

      staged?(listing) ->
        write_listing(listing, commit, written)

      written ->
        move(listing, commit, written)

      true ->
        :skipped
    end
  end

  defp written(%CommitListing{changes_ref_id: ref_id, changes_position: position, changes_expires_at: expires_at})
       when is_integer(ref_id) and is_integer(position) do
    if DateTime.after?(expires_at, DateTime.utc_now()), do: {ref_id, position}
  end

  defp written(_listing), do: nil

  # A day early: the listing's files expire on their own, part by part.
  defp staged?(listing) do
    days = Environment.coverage_retention_days().files
    DateTime.after?(listing.inserted_at, DateTime.add(DateTime.utc_now(), -(days - 1), :day))
  end

  # A write over a partial read of the listing (a lagging replica, a part
  # that expired) would record every file it missed as gone.
  defp write_listing(listing, commit, written) do
    if listed_files(listing) == listing.files_count do
      if written, do: retire(listing, written)
      vacate(listing, commit.place)
      expires_at = expires_at(listing.repository_id, commit.place)
      count = insert_changes(listing, commit, expires_at)
      preserve_above(listing, commit.place, :below)
      mark(listing, commit.place, expires_at, count)
      :written
    else
      :unavailable
    end
  end

  defp listed_files(listing) do
    ClickHouseRepo.one(
      from(f in CommitFile,
        where: f.repository_id == ^listing.repository_id and f.sha == ^listing.sha,
        select: fragment("uniqExact(?)", f.path)
      ),
      settings: @consistent
    ) || 0
  end

  defp insert_changes(listing, %{place: {ref_id, position}} = commit, expires_at) do
    insert(
      """
      SELECT {repository_id:Int64}, {ref_id:Int64}, {position:UInt32}, {generation:UInt32}, {sha:String},
        if(l.listed = 1, l.path, s.path), l.git_blob_id, l.mode, {expires_at:DateTime},
        #{version_sql({ref_id, position})}, 0
      FROM (
        SELECT path, argMax(git_blob_id, inserted_at) AS git_blob_id, argMax(mode, inserted_at) AS mode, 1 AS listed
        FROM git_commit_files
        WHERE repository_id = {repository_id:Int64} AND sha = {sha:String}
        GROUP BY path
        HAVING git_blob_id != ''
      ) AS l
      FULL OUTER JOIN (#{state_sql(GitHistory.chain(commit.place, :below))}) AS s ON s.path = l.path
      WHERE l.git_blob_id != s.git_blob_id OR l.mode != s.mode
      """,
      %{
        repository_id: listing.repository_id,
        ref_id: ref_id,
        position: position,
        generation: commit.generation,
        sha: listing.sha,
        expires_at: expires_at
      }
    )
  end

  # Rows that move up their own ref (a commit was slotted in below them)
  # cannot be copied a commit at a time: they would land on, or be read
  # over, the rows the commits above are still to copy. Retired, they leave
  # the commit's files unknown rather than another commit's.
  defp move(listing, %{place: {ref_id, position}}, {ref_id, old_position} = written) when position > old_position do
    retire(listing, written)
    mark(listing, nil, nil, nil)
    :skipped
  end

  defp move(listing, commit, written) do
    case moving_below(listing.repository_id, commit.place) do
      [] ->
        copy(listing, commit, written)
        :moved

      shas ->
        if FileChangesWorker.queued?(listing.repository_id, shas), do: :deferred, else: :skipped
    end
  end

  # The commits below the place that are still to move there. Rows copied
  # above one of them would be read over a chain that lacks it, and stay
  # wrong once it lands.
  defp moving_below(repository_id, place) do
    below =
      place
      |> GitHistory.chain(:below)
      |> Enum.reduce(dynamic(false), fn %{ref_id: ref_id, hi: hi}, acc ->
        dynamic([l, c], ^acc or (c.ref_id == ^ref_id and c.position <= ^hi))
      end)

    Repo.all(
      from(l in CommitListing,
        join: c in Commit,
        on: c.repository_id == l.repository_id and c.sha == l.sha,
        where: l.repository_id == ^repository_id and not l.truncated and l.changes_expires_at > ^DateTime.utc_now(),
        where: fragment("(?, ?) IS DISTINCT FROM (?, ?)", l.changes_ref_id, l.changes_position, c.ref_id, c.position),
        where: ^below,
        select: l.sha
      )
    )
  end

  # The commit's place moved but its listing is gone: the rows it stored at
  # its old place are kept as they were, compared with what was below it
  # there.
  defp copy(listing, %{place: {ref_id, position} = place} = commit, {old_ref_id, old_position} = written) do
    vacate(listing, place)
    expires_at = expires_at(listing.repository_id, place)

    count =
      insert(
        """
          SELECT repository_id, {ref_id:Int64}, {position:UInt32}, {generation:UInt32}, sha, path, git_blob_id, mode,
          {expires_at:DateTime}, #{version_sql(place)}, 0
        FROM git_file_changes FINAL
        WHERE repository_id = {repository_id:Int64} AND ref_id = {old_ref_id:Int64} AND position = {old_position:UInt32}
          AND sha = {sha:String} AND expires_at > now()
        """,
        %{
          repository_id: listing.repository_id,
          ref_id: ref_id,
          position: position,
          generation: commit.generation,
          sha: listing.sha,
          expires_at: expires_at,
          old_ref_id: old_ref_id,
          old_position: old_position
        }
      )

    preserve_above(listing, place, :below)
    retire(listing, written)
    mark(listing, place, expires_at, count)
  end

  # Retires the rows the commit left at a place it no longer holds.
  defp retire(listing, place) do
    preserve_above(listing, place, :at)
    delete(listing.repository_id, place, "sha = {sha:String}", %{sha: listing.sha})
  end

  # Each place has one owner at a time: what another commit left at this one
  # (a branch rewritten, the refs rebuilt) goes before the commit's own rows.
  defp vacate(listing, place) do
    preserve_above(listing, place, :at)
    delete(listing.repository_id, place, "sha != {sha:String}", %{sha: listing.sha})
  end

  defp delete(repository_id, {ref_id, position}, condition, params) do
    insert(
      """
      SELECT repository_id, ref_id, position, generation, sha, path, git_blob_id, mode, expires_at, row_version + 1, 1
      FROM git_file_changes FINAL
      WHERE repository_id = {repository_id:Int64} AND ref_id = {ref_id:Int64} AND position = {position:UInt32}
        AND #{condition}
      """,
      Map.merge(params, %{repository_id: repository_id, ref_id: ref_id, position: position})
    )
  end

  # Gives each written commit right above the place a row for every path the
  # place has rows for and it has none, holding what it read there so far:
  # the place's own rows before they are retired (`:at`), or what is below
  # the place after rows were added to it (`:below`).
  defp preserve_above(listing, {ref_id, position} = place, which) do
    for commit <- above(listing.repository_id, place, listing.sha) do
      {above_ref_id, above_position} = commit.place
      at = "repository_id = {repository_id:Int64} AND ref_id = {ref_id:Int64} AND position = {position:UInt32}"

      added =
        insert(
          """
          SELECT {repository_id:Int64}, {above_ref_id:Int64}, {above_position:UInt32}, {generation:UInt32}, {sha:String},
            p.path, s.git_blob_id, s.mode, {expires_at:DateTime}, #{version_sql(commit.place)}, 0
          FROM (SELECT DISTINCT path FROM git_file_changes FINAL WHERE #{at} AND expires_at > now()) AS p
          LEFT JOIN (
            #{state_sql(GitHistory.chain(place, which), "path IN (SELECT path FROM git_file_changes FINAL WHERE #{at})")}
          ) AS s ON s.path = p.path
          WHERE p.path NOT IN (
            SELECT path FROM git_file_changes FINAL
            WHERE repository_id = {repository_id:Int64} AND ref_id = {above_ref_id:Int64}
              AND position = {above_position:UInt32} AND expires_at > now()
          )
          """,
          %{
            repository_id: listing.repository_id,
            ref_id: ref_id,
            position: position,
            above_ref_id: above_ref_id,
            above_position: above_position,
            generation: commit.generation,
            sha: commit.sha,
            expires_at: commit.expires_at
          }
        )

      if added > 0 do
        Repo.update_all(
          from(l in CommitListing, where: l.repository_id == ^listing.repository_id and l.sha == ^commit.sha),
          inc: [changes_count: added]
        )
      end
    end
  end

  # The commits whose rows were written over what the place holds: the next
  # written commit above it on its ref, and the first written commit of each
  # ref that forks from it at or above the place and below that one, through
  # the forks that have none of their own. Only commits written where they
  # sit: one that is still to move reads nothing at its old place. The forks
  # are read in one query: a default branch has a ref per pull request.
  defp above(repository_id, {ref_id, position}, sha) do
    now = DateTime.utc_now()

    next =
      Repo.one(
        from(l in CommitListing,
          join: c in Commit,
          on: c.repository_id == l.repository_id and c.sha == l.sha,
          where: l.repository_id == ^repository_id and l.sha != ^sha and l.changes_expires_at > ^now,
          where: l.changes_ref_id == ^ref_id and l.changes_position > ^position,
          where: c.ref_id == l.changes_ref_id and c.position == l.changes_position,
          order_by: [asc: l.changes_position],
          limit: 1,
          select: %{
            sha: l.sha,
            place: {l.changes_ref_id, l.changes_position},
            expires_at: l.changes_expires_at,
            generation: c.generation
          }
        )
      )

    first_written = """
    LEFT JOIN LATERAL (
      SELECT l.sha, l.changes_position, l.changes_expires_at, c.generation
      FROM git_commit_listings l
      JOIN git_commits c ON c.repository_id = l.repository_id AND c.sha = l.sha
        AND c.ref_id = l.changes_ref_id AND c.position = l.changes_position
      WHERE l.repository_id = $1 AND l.changes_ref_id = r.id AND l.changes_expires_at > $2 AND l.sha <> $3
      ORDER BY l.changes_position
      LIMIT 1
    ) f ON true
    """

    %{rows: forks} =
      Repo.query!(
        """
        WITH RECURSIVE forks (ref_id, sha, position, expires_at, generation) AS (
          SELECT r.id, f.sha, f.changes_position, f.changes_expires_at, f.generation
          FROM git_refs r
          #{first_written}
          WHERE r.parent_ref_id = $4 AND r.fork_position >= $5 AND ($6::integer IS NULL OR r.fork_position < $6)
          UNION
          SELECT r.id, f.sha, f.changes_position, f.changes_expires_at, f.generation
          FROM forks x
          JOIN git_refs r ON r.parent_ref_id = x.ref_id AND r.id <> $4
            AND (x.position IS NULL OR r.fork_position < x.position)
          #{first_written}
        )
        SELECT sha, ref_id, position, expires_at, generation FROM forks WHERE sha IS NOT NULL
        """,
        [repository_id, now, sha, ref_id, position, next && elem(next.place, 1)]
      )

    List.wrap(next) ++
      for [sha, ref_id, position, expires_at, generation] <- forks do
        %{sha: sha, place: {ref_id, position}, expires_at: DateTime.truncate(expires_at, :second), generation: generation}
      end
  end

  # Kept on a ref that forks from none. On any other, no later than the rows
  # below it on the refs of its chain that fork: its files read them all. A
  # ref among those whose rows have less than half the retention left is
  # renewed first, as far as the other refs of the chain allow, so a ref
  # that keeps receiving commits keeps its rows, and one that stops loses
  # them together.
  defp expires_at(repository_id, place) do
    chain = GitHistory.chain(place, :below)
    refs = Enum.map(chain, & &1.ref_id)
    roots = Repo.all(from(r in Ref, where: r.id in ^refs and is_nil(r.parent_ref_id), select: r.id))

    case Enum.reject(chain, &(&1.ref_id in roots)) do
      [] ->
        @kept

      forked ->
        now = DateTime.truncate(DateTime.utc_now(), :second)
        days = Environment.coverage_retention_days().files
        own = DateTime.add(now, days, :day)
        renewable = DateTime.add(now, div(days * 86_400, 2), :second)

        below =
          Repo.all(
            from(l in CommitListing,
              where: l.repository_id == ^repository_id and l.changes_expires_at > ^now,
              where: ^within(forked),
              group_by: l.changes_ref_id,
              select: {l.changes_ref_id, min(l.changes_expires_at)}
            )
          )

        {renewed, kept} = Enum.split_with(below, fn {_ref_id, expires_at} -> DateTime.before?(expires_at, renewable) end)
        expires_at = Enum.min([own | Enum.map(kept, &elem(&1, 1))], DateTime)
        renew(repository_id, Enum.map(renewed, &elem(&1, 0)), expires_at)
        expires_at
    end
  end

  # Extending is the safe direction: whichever version of a row a merge
  # keeps, none of them expires before the rows that read it.
  defp renew(_repository_id, [], _expires_at), do: :ok

  defp renew(repository_id, ref_ids, expires_at) do
    insert(
      """
      SELECT repository_id, ref_id, position, generation, sha, path, git_blob_id, mode, {expires_at:DateTime},
        row_version + 1, 0
      FROM git_file_changes FINAL
      WHERE repository_id = {repository_id:Int64} AND ref_id IN {ref_ids:Array(Int64)} AND expires_at > now()
      """,
      %{repository_id: repository_id, ref_ids: ref_ids, expires_at: expires_at}
    )

    Repo.update_all(
      from(l in CommitListing,
        where: l.repository_id == ^repository_id and l.changes_ref_id in ^ref_ids,
        where: l.changes_expires_at > ^DateTime.utc_now()
      ),
      set: [changes_expires_at: expires_at]
    )
  end

  defp within(segments) do
    Enum.reduce(segments, dynamic(false), fn %{ref_id: ref_id, hi: hi}, acc ->
      dynamic([l], ^acc or (l.changes_ref_id == ^ref_id and l.changes_position <= ^hi))
    end)
  end

  @doc """
  Where the commit's files can be read: its place when its file changes are
  written there and kept, or nil.
  """
  def current(repository_id, sha) do
    Repo.one(
      from(l in CommitListing,
        join: c in Commit,
        on: c.repository_id == l.repository_id and c.sha == l.sha,
        where: l.repository_id == ^repository_id and l.sha == ^sha and not l.truncated,
        where: l.changes_ref_id == c.ref_id and l.changes_position == c.position,
        where: l.changes_expires_at > ^DateTime.utc_now(),
        select: {c.ref_id, c.position}
      )
    )
  end

  # An `in` list is bound as one array parameter, which ClickHouse refuses
  # past 128 KiB: a chunk holds this many values at most, and fewer when
  # they are long.
  @bound_paths 900
  @bound_bytes 100_000

  @doc """
  The files of the commit at `place` with their blobs, as
  `%{path:, git_blob_id:}`: all of them, or those `:match` (a pattern from
  `Tuist.Tests.Coverage.ExcludedPaths.pattern/1`) matches, those directly
  inside `:directories` (as `Path.dirname/1` names them), or `:paths`.
  """
  def files(repository_id, place, opts \\ []) do
    query = state_query(repository_id, GitHistory.chain(place, :at))
    opts |> narrowed() |> Enum.flat_map(&ClickHouseRepo.all(&1.(query)))
  end

  @doc "The blob of each of `paths` at `place`, by path; a path the commit lacks is absent."
  def blobs(repository_id, place, paths), do: blobs_along(repository_id, GitHistory.chain(place, :at), paths)

  # Past one request's worth of bound paths, the whole state read once is
  # cheaper than a lookup per chunk.
  defp blobs_along(repository_id, chain, paths) do
    query = state_query(repository_id, chain)

    if length(paths) > @bound_paths do
      query |> ClickHouseRepo.all() |> Map.new(&{&1.path, &1.git_blob_id}) |> Map.take(paths)
    else
      [paths: paths]
      |> narrowed()
      |> Enum.flat_map(&ClickHouseRepo.all(&1.(query)))
      |> Map.new(&{&1.path, &1.git_blob_id})
    end
  end

  @doc """
  The files that differ between the commits at two places, by path, as
  `%{path:, from:, to:}` with the blob at each, nil where the commit lacks
  the path, narrowed as `files/3` is. Only the paths with a row on one
  commit's chain and not the other's are compared.
  """
  def changed(repository_id, from_place, to_place, opts \\ []) do
    from_chain = GitHistory.chain(from_place, :at)
    to_chain = GitHistory.chain(to_place, :at)

    case between(from_chain, to_chain) do
      [] ->
        []

      ranges ->
        query =
          from(c in FileChange,
            hints: ["FINAL"],
            where: c.repository_id == ^repository_id and c.expires_at > fragment("now()"),
            where: ^rows_within(ranges),
            distinct: true,
            select: %{path: c.path}
          )

        paths = opts |> narrowed() |> Enum.flat_map(&ClickHouseRepo.all(&1.(query))) |> Enum.map(& &1.path) |> Enum.uniq()
        from = blobs_along(repository_id, from_chain, paths)
        to = blobs_along(repository_id, to_chain, paths)

        for path <- Enum.sort(paths), from[path] != to[path], do: %{path: path, from: from[path], to: to[path]}
    end
  end

  # The positions on one chain and not the other, per ref.
  defp between(from_chain, to_chain) do
    from = Map.new(from_chain, &{&1.ref_id, &1.hi})
    to = Map.new(to_chain, &{&1.ref_id, &1.hi})

    for ref_id <- Enum.uniq(Map.keys(from) ++ Map.keys(to)),
        [lo, hi] = Enum.sort([Map.get(from, ref_id, 0), Map.get(to, ref_id, 0)]),
        lo < hi,
        do: %{ref_id: ref_id, lo: lo, hi: hi}
  end

  defp narrowed(opts) do
    case Enum.find(opts, fn {key, _value} -> key in [:match, :directories, :paths] end) do
      {:match, pattern} when is_binary(pattern) ->
        [&where(&1, [c], fragment("match(?, ?)", c.path, ^pattern))]

      {:directories, directories} ->
        for chunk <- bound(directories),
            do:
              &where(
                &1,
                [c],
                fragment("if(position(?, '/') > 0, replaceRegexpOne(?, '/[^/]*$', ''), '.')", c.path, c.path) in ^chunk
              )

      {:paths, paths} ->
        for chunk <- bound(paths), do: &where(&1, [c], c.path in ^chunk)

      _ ->
        [& &1]
    end
  end

  defp bound(values) do
    values
    |> Enum.uniq()
    |> Enum.chunk_while(
      {[], 0, 0},
      fn value, {chunk, count, bytes} ->
        size = byte_size(value) + 3

        if count == @bound_paths or (count > 0 and bytes + size > @bound_bytes),
          do: {:cont, chunk, {[value], 1, size}},
          else: {:cont, {[value | chunk], count + 1, bytes + size}}
      end,
      fn
        {[], _count, _bytes} = acc -> {:cont, acc}
        {chunk, _count, _bytes} = acc -> {:cont, chunk, acc}
      end
    )
  end

  # Each path's newest row along the chain, the nearest ref first, without
  # the paths that row says are gone.
  defp state_query(repository_id, chain) do
    refs = Enum.map(chain, & &1.ref_id)

    from(c in FileChange,
      hints: ["FINAL"],
      where: c.repository_id == ^repository_id and c.expires_at > fragment("now()"),
      where: ^rows_within(chain),
      group_by: c.path,
      having:
        fragment(
          "argMax(?, (-toInt64(indexOf(?, ?)), ?)) != ''",
          c.git_blob_id,
          type(^refs, {:array, :integer}),
          c.ref_id,
          c.position
        ),
      select: %{
        path: c.path,
        git_blob_id:
          fragment(
            "argMax(?, (-toInt64(indexOf(?, ?)), ?))",
            c.git_blob_id,
            type(^refs, {:array, :integer}),
            c.ref_id,
            c.position
          )
      }
    )
  end

  defp rows_within(segments) do
    Enum.reduce(segments, dynamic(false), fn %{ref_id: ref_id, hi: hi} = segment, acc ->
      lo = Map.get(segment, :lo, 0)
      dynamic([c], ^acc or (c.ref_id == ^ref_id and c.position > ^lo and c.position <= ^hi))
    end)
  end

  defp mark(listing, place, expires_at, count) do
    {ref_id, position} = place || {nil, nil}

    Repo.update_all(
      from(l in CommitListing, where: l.repository_id == ^listing.repository_id and l.sha == ^listing.sha),
      set: [changes_ref_id: ref_id, changes_position: position, changes_expires_at: expires_at, changes_count: count]
    )
  end

  # Each path's newest row along the chain, the nearest ref first, without
  # the paths that row says are gone.
  defp state_sql(chain, condition \\ "1") do
    refs = Enum.map_join(chain, ", ", & &1.ref_id)
    newest = "(-toInt64(indexOf([#{refs}], ref_id)), position)"

    segments =
      Enum.map_join(chain, " OR ", fn %{ref_id: ref_id, hi: hi} -> "(ref_id = #{ref_id} AND position <= #{hi})" end)

    """
    SELECT path, argMax(git_blob_id, #{newest}) AS git_blob_id, argMax(mode, #{newest}) AS mode
    FROM git_file_changes FINAL
    WHERE repository_id = {repository_id:Int64} AND expires_at > now() AND (#{segments}) AND #{condition}
    GROUP BY path
    HAVING git_blob_id != ''
    """
  end

  # Newer than every row the place ever held, whichever node's clock wrote it.
  defp version_sql({ref_id, position}) do
    """
    greatest(#{System.os_time(:microsecond)}, (
      SELECT max(row_version) + 1 FROM git_file_changes
      WHERE repository_id = {repository_id:Int64} AND ref_id = #{ref_id} AND position = #{position}
    ))
    """
  end

  # Returns how many rows were written.
  defp insert(select, params) do
    IngestRepo.query!("INSERT INTO git_file_changes (#{@columns}) #{select}", params, settings: @consistent).num_rows ||
      0
  end
end
