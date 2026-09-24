defmodule Tuist.GitHistory do
  @moduledoc """
  A repository's commit graph, as far back as the history window reaches,
  and the file listing of the commits that were measured.

  Coverage is a property of a commit, so comparisons need to know how commits
  relate, not only which commit a run ran on: a commit's coverage is compared
  with an ancestor of its merge base with the base branch, never with an
  unrelated commit, and a branch's history is the first-parent walk from its
  head. The graph is what proves that ancestry.

  The graph belongs to a **repository** (`Tuist.GitHistory.Repository`), the
  normalized remote a run reports, scoped to the account: several projects
  can share one, and a project's runs may come from more than one. Rows come
  from two sources. The client uploads the commits it can see in its checkout
  (`missing_shas/2` tells it which ones the server lacks, so uploads only add
  what is new and repeating one changes nothing), and the VCS provider fills
  what the client could not send. Both write the same tables.

  Every walk is bounded by the project's settings (`settings/1`): a window in
  days and commits, applied to what is stored and to how far a walk goes.
  Generation numbers (Git's commit-graph ones, computed on write) let a walk
  looking for one of a set of commits stop descending below the lowest of
  them.

  A commit's file listing (`Tuist.GitHistory.CommitFile`) is uploaded once per
  commit by the first clean checkout that measured it, and answers what files
  exist at the commit, which of them the project tracks
  (`tracked_files/3`), and what blob a path had at an ancestor.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHistory.Commit
  alias Tuist.GitHistory.CommitFile
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.CommitParent
  alias Tuist.GitHistory.Ref
  alias Tuist.GitHistory.Repository
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.ExcludedPaths

  @defaults %{
    window_days: 365,
    window_commits: 5_000,
    deepen_budget_seconds: 60,
    upload_batch_size: 500,
    tracked_file_globs: [],
    commit_file_limit: 50_000
  }

  @insert_chunk_size 5_000

  @doc """
  The history settings in effect for a project: the server defaults (from
  configuration, see `Tuist.Environment.git_history_defaults/1`) with the
  project's own overrides on top.

  - `window_days` and `window_commits`: how far back history is kept, uploaded
    and walked, whichever bound is hit first;
  - `deepen_budget_seconds`: how long a client may spend deepening a shallow
    clone;
  - `upload_batch_size`: commits per upload request;
  - `tracked_file_globs`: the files, beyond the sources a test compiles, whose
    identity a commit's evidence depends on (dependency manifests, generator
    configuration, fixtures, snapshots), read off the commit's file listing;
    only the project sets them, since they differ per repository;
  - `commit_file_limit`: how many files of a commit's tree a client lists
    before marking the listing truncated.
  """
  def settings(%Project{} = project) do
    defaults = Map.merge(@defaults, Environment.git_history_defaults())

    overrides =
      %{
        window_days: project.git_history_window_days,
        window_commits: project.git_history_window_commits,
        tracked_file_globs: project.tracked_file_globs
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(defaults, overrides)
  end

  def settings(nil), do: Map.merge(@defaults, Environment.git_history_defaults())

  @doc """
  The key a remote URL identifies a repository by: host, owner and name,
  lowercased, without the scheme, credentials, port or `.git`. Nil for
  anything that is not a remote (a local path, an empty string).

      iex> Tuist.GitHistory.repository_key("git@github.com:Tuist/tuist.git")
      "github.com/tuist/tuist"
      iex> Tuist.GitHistory.repository_key("https://x-token@github.com/tuist/tuist/")
      "github.com/tuist/tuist"
  """
  def repository_key(url) when is_binary(url) do
    url = String.trim(url)

    uri =
      case Regex.run(~r/^(?:[^@\/]+@)?([^:\/]+):(?!\/\/)(.+)$/, url) do
        [_, host, path] -> %URI{host: host, path: "/" <> path}
        _ -> URI.parse(url)
      end

    with %URI{host: host, path: path} when is_binary(host) and host != "" and is_binary(path) <- uri,
         path = path |> String.trim("/") |> String.replace_suffix(".git", "") |> String.trim("/"),
         true <- path != "" do
      String.downcase("#{host}/#{path}")
    else
      _ -> nil
    end
  end

  def repository_key(_url), do: nil

  @doc """
  The id of the account's repository for a remote URL, created on first
  sight, or nil when the URL names no repository.
  """
  def repository_id(account_id, url) do
    case repository_key(url) do
      nil ->
        nil

      key ->
        now = DateTime.truncate(DateTime.utc_now(), :second)

        Repo.insert_all(
          Repository,
          [%{account_id: account_id, key: key, inserted_at: now, updated_at: now}],
          on_conflict: :nothing,
          conflict_target: [:account_id, :key]
        )

        Repo.one!(from(r in Repository, where: r.account_id == ^account_id and r.key == ^key, select: r.id))
    end
  end

  @doc "Of the given SHAs, the ones the repository has no commit for."
  def missing_shas(_repository_id, []), do: []

  def missing_shas(repository_id, shas) do
    shas = Enum.uniq(shas)

    known =
      Repo.all(from(c in Commit, where: c.repository_id == ^repository_id and c.sha in ^shas, select: c.sha))

    shas -- known
  end

  @doc """
  Stores commits and their parent edges. Each commit is a map with `sha`,
  `parents` (SHAs, first parent first) and `committed_at`. Commits already
  stored are left as they are, so an upload can be repeated. Generation
  numbers are computed from the parents stored so far and from the batch
  itself, so uploading oldest first gives exact numbers; a parent that is
  never stored counts as generation 0.
  """
  def record_commits(_repository_id, _object_format, []), do: :ok

  def record_commits(repository_id, object_format, commits) do
    commits = commits |> Enum.uniq_by(& &1.sha) |> Enum.sort_by(& &1.committed_at, DateTime)
    parent_shas = commits |> Enum.flat_map(& &1.parents) |> Enum.uniq()

    known_generations =
      from(c in Commit,
        where: c.repository_id == ^repository_id and c.sha in ^parent_shas,
        select: {c.sha, c.generation}
      )
      |> Repo.all()
      |> Map.new()

    {rows, _generations} =
      Enum.map_reduce(commits, known_generations, fn commit, generations ->
        generation = 1 + Enum.reduce(commit.parents, 0, &max(Map.get(generations, &1, 0), &2))
        now = DateTime.truncate(DateTime.utc_now(), :second)

        row = %{
          repository_id: repository_id,
          sha: commit.sha,
          object_format: object_format,
          committed_at: DateTime.truncate(commit.committed_at, :second),
          generation: generation,
          inserted_at: now,
          updated_at: now
        }

        {row, Map.put(generations, commit.sha, generation)}
      end)

    edges =
      Enum.flat_map(commits, fn commit ->
        commit.parents
        |> Enum.with_index()
        |> Enum.map(fn {parent, position} ->
          %{repository_id: repository_id, child_sha: commit.sha, parent_sha: parent, position: position}
        end)
      end)

    {:ok, :ok} =
      Repo.transaction(fn ->
        rows |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(Commit, &1, on_conflict: :nothing))
        edges |> Enum.chunk_every(1_000) |> Enum.each(&Repo.insert_all(CommitParent, &1, on_conflict: :nothing))
        :ok
      end)

    :ok
  end

  @doc """
  Records the newest commit seen on a branch, advancing the branch's ref to
  it (`advance_ref/5`): the default branch as the root of the repository's
  first-parent tree, any other branch as forking from it. The head is the
  checkout's commit, and a re-run of an older commit's job checks out that
  commit, so a head the branch already holds leaves it where it is.
  """
  def record_branch_head(repository_id, branch, sha, default_branch)
      when is_binary(branch) and branch != "" and is_binary(sha) and sha != "" do
    parent = if branch == default_branch or default_branch in [nil, ""], do: nil, else: default_branch
    advance_ref(repository_id, branch, parent, sha, only_forward: true)
  end

  def record_branch_head(_repository_id, _branch, _sha, _default_branch), do: :ok

  @doc "The ref of a repository by name (a branch, or `pull/<number>`), or nil."
  def ref(repository_id, name), do: Repo.one(from(r in Ref, where: r.repository_id == ^repository_id and r.name == ^name))

  @doc "The ref with the id, or nil."
  def get_ref(nil), do: nil
  def get_ref(ref_id), do: Repo.get(Ref, ref_id)

  @doc "The name of a pull request's ref."
  def pull_request_ref(number), do: "pull/#{number}"

  @doc """
  Where a commit sits on the first-parent tree: `{ref_id, position}` on the
  segment of the ref that owns it, or nil when no ref does.
  """
  def position(repository_id, sha) do
    Repo.one(
      from(c in Commit,
        where: c.repository_id == ^repository_id and c.sha == ^sha and not is_nil(c.ref_id),
        select: {c.ref_id, c.position}
      )
    )
  end

  @doc """
  The commits a ref owns, newest first, as `{sha, position, committed_at}`:
  the default branch's first-parent history, or what another ref added above
  its fork. `:limit` caps them (200 by default); `:at_or_below`, `:below` and
  `:above` bound the positions and `:since`/`:until` when the commits were
  made (`DateTime`); `order: :asc` reads them oldest first.
  """
  def ref_commits(ref_id, opts \\ []) do
    ref_id
    |> ref_commits_query(opts)
    |> order_by([c], [{^Keyword.get(opts, :order, :desc), c.position}])
    |> limit(^Keyword.get(opts, :limit, 200))
    |> select([c], {c.sha, c.position, c.committed_at})
    |> Repo.all()
  end

  @doc "Whether the ref owns a commit within the bounds `ref_commits/2` takes."
  def ref_commits?(ref_id, opts), do: ref_id |> ref_commits_query(opts) |> Repo.exists?()

  defp ref_commits_query(ref_id, opts) do
    Enum.reduce(opts, from(c in Commit, where: c.ref_id == ^ref_id), fn
      {:at_or_below, position}, query -> where(query, [c], c.position <= ^position)
      {:below, position}, query -> where(query, [c], c.position < ^position)
      {:above, position}, query -> where(query, [c], c.position > ^position)
      {:since, nil}, query -> query
      {:since, since}, query -> where(query, [c], c.committed_at >= ^since)
      {:until, nil}, query -> query
      {:until, until}, query -> where(query, [c], c.committed_at <= ^until)
      _option, query -> query
    end)
  end

  @doc """
  Advances a ref to a new head, keeping every commit's place on the
  first-parent tree: the head's first-parent chain is walked back to the
  first commit the ref, or the ref it forks from, already owns.

  - The ref's own commit: an append. What the ref held above it was
    rewritten (a force-push) and is released; the new commits follow it.
  - Its parent's commit: a fork, or a rebase. The ref's commits are released
    and it forks there.
  - Nothing, for the default branch (no parent): its whole walked history is
    numbered from the oldest commit.

  Only the default branch takes over commits another ref owns (a
  fast-forward merge): that ref is released and advanced again from its own
  head, forking above them. Any other ref stops at the first commit some ref
  owns, so two refs never trade commits back and forth; one that stops on a
  sibling's commit forks where the sibling does and owns only what it added.

  `parent` names the ref this one forks from (nil for the default branch).
  With `only_forward: true` a head the ref already owns leaves it as it is:
  a late report of an older commit does not move the ref back. The walk is
  bounded by `:max_depth` (the default `window_commits`). A head the graph
  does not know yet is recorded without positions.
  """
  def advance_ref(repository_id, name, parent, head_sha, opts \\ []) do
    {:ok, :ok} =
      Repo.transaction(
        fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["git_refs:#{repository_id}"])
          parent_ref = parent && upsert_ref(repository_id, parent, nil)
          ref = upsert_ref(repository_id, name, parent_ref && parent_ref.id)

          cond do
            not known?(repository_id, head_sha) ->
              Repo.update_all(from(r in Ref, where: r.id == ^ref.id), set: [head_sha: head_sha, updated_at: now()])

            Keyword.get(opts, :only_forward, false) and position_ref(repository_id, head_sha) == ref.id ->
              :ok

            true ->
              advance(repository_id, ref, head_sha, is_nil(ref.parent_ref_id), opts)
              sync_coverage(repository_id)
          end

          :ok
        end,
        timeout: to_timeout(minute: 2)
      )

    :ok
  end

  defp position_ref(repository_id, sha) do
    case position(repository_id, sha) do
      {ref_id, _position} -> ref_id
      nil -> nil
    end
  end

  # The parent keeps the parent it has: a ref named as someone's parent is
  # created as a root until it is advanced with a parent of its own.
  defp upsert_ref(repository_id, name, parent_ref_id) do
    now = now()

    Repo.insert_all(
      Ref,
      [
        %{
          repository_id: repository_id,
          name: name,
          parent_ref_id: parent_ref_id,
          fork_position: 0,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:repository_id, :name]
    )

    ref = ref(repository_id, name)

    if not is_nil(parent_ref_id) and ref.parent_ref_id != parent_ref_id and parent_ref_id != ref.id do
      Repo.update_all(from(r in Ref, where: r.id == ^ref.id), set: [parent_ref_id: parent_ref_id])
      %{ref | parent_ref_id: parent_ref_id}
    else
      ref
    end
  end

  defp advance(repository_id, %Ref{} = ref, head_sha, takeover?, opts) do
    max_depth = Keyword.get(opts, :max_depth) || settings(nil).window_commits
    walk = walk(repository_id, ref, head_sha, takeover?, max_depth)
    anchor = Enum.find(walk, &anchored?(&1, ref, takeover?))
    anchor_depth = if anchor, do: anchor.depth, else: length(walk)

    {base, fork} = settle(ref, anchor)

    new = Enum.filter(walk, &(&1.depth < anchor_depth))
    losers = new |> Enum.map(& &1.ref_id) |> Enum.reject(&(is_nil(&1) or &1 == ref.id)) |> Enum.uniq()
    Enum.each(losers, &release(from(c in Commit, where: c.ref_id == ^&1)))

    Repo.query!(
      """
      UPDATE git_commits c SET ref_id = $2, position = v.position
      FROM unnest($3::varchar[], $4::integer[]) AS v (sha, position)
      WHERE c.repository_id = $1 AND c.sha = v.sha
      """,
      [
        repository_id,
        ref.id,
        Enum.map(new, & &1.sha),
        Enum.map(new, &(base + anchor_depth - &1.depth))
      ]
    )

    Repo.update_all(from(r in Ref, where: r.id == ^ref.id),
      set: [head_sha: head_sha, fork_position: fork, updated_at: now()]
    )

    # A ref that lost commits to a fast-forward forks again above them. It
    # never takes commits back, so the re-forks end.
    for %Ref{head_sha: loser_head} = loser <- Enum.map(losers, &get_ref/1), loser_head do
      advance(repository_id, loser, loser_head, false, opts)
    end
  end

  # Where the ref's new commits start, and where it forks, from the commit
  # the walk stopped at, releasing what the ref no longer holds.
  defp settle(ref, nil) do
    release(from(c in Commit, where: c.ref_id == ^ref.id))
    {0, 0}
  end

  defp settle(%{id: ref_id} = ref, %{ref_id: ref_id, position: position}) do
    release(from(c in Commit, where: c.ref_id == ^ref_id and c.position > ^position))
    {position, ref.fork_position}
  end

  defp settle(%{parent_ref_id: parent_id} = ref, %{ref_id: parent_id, position: position}) do
    release(from(c in Commit, where: c.ref_id == ^ref.id))
    {position, position}
  end

  # A sibling's commit: fork where the sibling forked.
  defp settle(ref, anchor) do
    release(from(c in Commit, where: c.ref_id == ^ref.id))
    sibling = get_ref(anchor.ref_id)
    fork = if sibling.parent_ref_id == ref.parent_ref_id, do: sibling.fork_position, else: 0
    {fork, fork}
  end

  # The default branch walks through other refs' commits, taking them over,
  # until it reaches its own; any other ref stops at the first owned commit.
  defp anchored?(%{ref_id: nil}, _ref, _takeover?), do: false
  defp anchored?(%{ref_id: ref_id}, ref, true), do: ref_id in [ref.id, ref.parent_ref_id]
  defp anchored?(_row, _ref, false), do: true

  defp walk(repository_id, ref, head_sha, takeover?, max_depth) do
    %{rows: rows} =
      Repo.query!(
        """
        WITH RECURSIVE chain (sha, depth, ref_id, position) AS (
          SELECT c.sha, 0, c.ref_id, c.position
          FROM git_commits c WHERE c.repository_id = $1 AND c.sha = $2
          UNION ALL
          SELECT p.parent_sha, ch.depth + 1, c.ref_id, c.position
          FROM chain ch
          JOIN git_commit_parents p ON p.repository_id = $1 AND p.child_sha = ch.sha AND p.position = 0
          JOIN git_commits c ON c.repository_id = $1 AND c.sha = p.parent_sha
          WHERE ch.depth < $3
            AND (ch.ref_id IS NULL OR ($4 AND ch.ref_id <> ALL ($5::bigint[])))
        )
        SELECT sha, depth, ref_id, position FROM chain ORDER BY depth
        """,
        [repository_id, head_sha, max_depth, takeover?, Enum.reject([ref.id, ref.parent_ref_id], &is_nil/1)]
      )

    Enum.map(rows, fn [sha, depth, ref_id, position] -> %{sha: sha, depth: depth, ref_id: ref_id, position: position} end)
  end

  defp release(query), do: Repo.update_all(query, set: [ref_id: nil, position: nil])

  # A commit's coverage keeps a copy of its place, so a branch's history
  # outlives the graph's window; it follows every move while the commit is in
  # the graph.
  defp sync_coverage(repository_id) do
    Repo.query!(
      """
      UPDATE coverage_commits cc SET ref_id = c.ref_id, position = c.position
      FROM git_commits c
      WHERE cc.repository_id = $1 AND c.repository_id = $1 AND c.sha = cc.git_commit_sha
        AND (cc.ref_id IS DISTINCT FROM c.ref_id OR cc.position IS DISTINCT FROM c.position)
      """,
      [repository_id]
    )
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  @doc "Whether the repository has a commit stored for the SHA."
  def known?(repository_id, sha) do
    Repo.exists?(from(c in Commit, where: c.repository_id == ^repository_id and c.sha == ^sha))
  end

  @doc """
  The ancestors of a commit, itself included at depth 0, as `{sha, depth}`
  with the shortest depth per SHA. Bounded by `:max_depth` (the default
  `window_commits`) and, when `:min_generation` is given, to commits at or
  above that generation.
  """
  def ancestors(repository_id, sha, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth) || settings(nil).window_commits
    min_generation = Keyword.get(opts, :min_generation, 0)

    %{rows: rows} =
      Repo.query!(
        """
        WITH RECURSIVE walk (sha, depth) AS (
          SELECT $2::varchar, 0
          UNION
          SELECT p.parent_sha, w.depth + 1
          FROM walk w
          JOIN git_commit_parents p ON p.repository_id = $1 AND p.child_sha = w.sha
          JOIN git_commits c ON c.repository_id = $1 AND c.sha = p.parent_sha
          WHERE w.depth < $3 AND c.generation >= $4
        )
        SELECT sha, min(depth) FROM walk GROUP BY sha ORDER BY min(depth), sha
        """,
        [repository_id, sha, max_depth, min_generation]
      )

    Enum.map(rows, fn [sha, depth] -> {sha, depth} end)
  end

  @doc """
  The first-parent chain of a commit, itself first at depth 0, as
  `{sha, depth, committed_at}`: what a branch's history is, in Git's own
  order, with merged branches' commits left to the branches they came from.
  Bounded by `:max_depth` (the default `window_commits`).
  """
  def first_parent_chain(repository_id, sha, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth) || settings(nil).window_commits

    %{rows: rows} =
      Repo.query!(
        """
        WITH RECURSIVE chain (sha, depth) AS (
          SELECT $2::varchar, 0
          UNION ALL
          SELECT p.parent_sha, ch.depth + 1
          FROM chain ch
          JOIN git_commit_parents p ON p.repository_id = $1 AND p.child_sha = ch.sha AND p.position = 0
          JOIN git_commits c ON c.repository_id = $1 AND c.sha = p.parent_sha
          WHERE ch.depth < $3
        )
        SELECT ch.sha, ch.depth, c.committed_at
        FROM chain ch
        LEFT JOIN git_commits c ON c.repository_id = $1 AND c.sha = ch.sha
        ORDER BY ch.depth
        """,
        [repository_id, sha, max_depth]
      )

    Enum.map(rows, fn [sha, depth, committed_at] -> {sha, depth, committed_at} end)
  end

  @doc """
  Of `candidates`, the one closest to `sha` along its ancestry (the commit
  itself counts, at distance 0), as `{sha, distance}`, or nil when none is an
  ancestor within the walk bounds. The walk never descends below the lowest
  candidate generation.
  """
  def nearest_ancestor(repository_id, sha, candidates, opts \\ [])

  def nearest_ancestor(_repository_id, _sha, [], _opts), do: nil

  def nearest_ancestor(repository_id, sha, candidates, opts) do
    candidates = MapSet.new(candidates)

    min_generation =
      Repo.one(
        from(c in Commit,
          where: c.repository_id == ^repository_id and c.sha in ^MapSet.to_list(candidates),
          select: min(c.generation)
        )
      ) || 0

    repository_id
    |> ancestors(sha, Keyword.put(opts, :min_generation, min_generation))
    |> Enum.find(fn {ancestor, _depth} -> MapSet.member?(candidates, ancestor) end)
  end

  @doc """
  The merge base of two commits from the stored graph: the common ancestor
  with the smallest combined distance, or nil when the graph does not connect
  them within the walk bounds. Best effort; the client's `git merge-base` is
  authoritative when it can run.
  """
  def merge_base(repository_id, sha_a, sha_b, opts \\ []) do
    ancestors_b = Map.new(ancestors(repository_id, sha_b, opts))

    repository_id
    |> ancestors(sha_a, opts)
    |> Enum.filter(fn {sha, _depth} -> Map.has_key?(ancestors_b, sha) end)
    |> Enum.min_by(fn {sha, depth} -> depth + Map.fetch!(ancestors_b, sha) end, fn -> nil end)
    |> case do
      nil -> nil
      {sha, _depth} -> sha
    end
  end

  @doc """
  Drops commits older than `window_days`, with their parent edges. Edges
  pointing at a dropped commit are kept: they mark where the window ends.
  """
  def prune(repository_id, window_days) do
    cutoff = DateTime.add(DateTime.utc_now(), -window_days * 86_400, :second)

    Repo.transaction(fn ->
      expired =
        from(c in Commit, where: c.repository_id == ^repository_id and c.committed_at < ^cutoff, select: c.sha)

      Repo.delete_all(
        from(p in CommitParent, where: p.repository_id == ^repository_id and p.child_sha in subquery(expired))
      )

      {count, _} =
        Repo.delete_all(from(c in Commit, where: c.repository_id == ^repository_id and c.committed_at < ^cutoff))

      count
    end)
  end

  @doc "Of the given SHAs, the ones whose file listing the repository lacks."
  def missing_listings(_repository_id, []), do: []

  def missing_listings(repository_id, shas) do
    shas = Enum.uniq(shas)

    stored =
      Repo.all(
        from(l in CommitListing,
          where: l.repository_id == ^repository_id and l.sha in ^shas,
          select: l.sha
        )
      )

    shas -- stored
  end

  @doc "Whether the commit's file listing is stored."
  def listing_stored?(repository_id, sha) do
    Repo.exists?(from(l in CommitListing, where: l.repository_id == ^repository_id and l.sha == ^sha))
  end

  @doc """
  Stores part of a commit's file listing: `files` are maps with `path`,
  `git_blob_id` and `mode`. The client sends a large listing in several
  requests and marks the last with `complete: true`, which records the
  listing as stored (`truncated:` when the client stopped at the limit).
  Repeating a request changes nothing: rows replace their equals and the
  listing row is written once.
  """
  def record_listing(repository_id, sha, files, opts \\ []) do
    now = NaiveDateTime.utc_now()

    files
    |> Stream.map(fn file ->
      %{
        repository_id: repository_id,
        sha: sha,
        path: Map.fetch!(file, :path),
        git_blob_id: Map.get(file, :git_blob_id) || "",
        mode: Map.get(file, :mode) || 0,
        inserted_at: now
      }
    end)
    |> Stream.chunk_every(@insert_chunk_size)
    |> Enum.each(&IngestRepo.insert_all(CommitFile, &1))

    if Keyword.get(opts, :complete, true) do
      files_count = Keyword.get_lazy(opts, :files_count, fn -> listing_size(repository_id, sha) end)

      Repo.insert_all(
        CommitListing,
        [
          %{
            repository_id: repository_id,
            sha: sha,
            files_count: files_count,
            truncated: Keyword.get(opts, :truncated, false),
            inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:repository_id, :sha]
      )
    end

    :ok
  end

  defp listing_size(repository_id, sha) do
    ClickHouseRepo.one(
      from(f in CommitFile,
        where: f.repository_id == ^repository_id and f.sha == ^sha,
        select: fragment("uniqExact(?)", f.path)
      ),
      settings: [select_sequential_consistency: 1]
    ) || 0
  end

  @doc """
  The files of a commit with their blobs, by path, optionally narrowed to
  the paths one glob pattern matches (`match:` a pattern from
  `Tuist.Tests.Coverage.ExcludedPaths.pattern/1`).
  """
  def commit_files(repository_id, sha, opts \\ []) do
    query =
      from(f in CommitFile,
        where: f.repository_id == ^repository_id and f.sha == ^sha,
        group_by: f.path,
        select: %{path: f.path, git_blob_id: fragment("argMax(?, ?)", f.git_blob_id, f.inserted_at)},
        order_by: f.path
      )

    query =
      case Keyword.get(opts, :match) do
        nil -> query
        pattern -> where(query, [f], fragment("match(?, ?)", f.path, ^pattern))
      end

    ClickHouseRepo.all(query)
  end

  @doc """
  The tracked files of a commit for a project: the paths in the commit's
  listing that the project's `tracked_file_globs` match, with their blobs.
  Empty when the project tracks nothing or the listing is not stored.
  """
  def tracked_files(%Project{} = project, repository_id, sha) do
    case settings(project).tracked_file_globs do
      [] -> []
      globs -> commit_files(repository_id, sha, match: ExcludedPaths.pattern(globs))
    end
  end

  @doc """
  The blob of each of `paths` at a commit, keyed by path, from the commit's
  listing; a path the listing lacks is absent.
  """
  @blob_paths_chunk 900

  def blobs_at(_repository_id, _sha, []), do: %{}

  def blobs_at(repository_id, sha, paths) do
    # One HTTP form field per bound path, and ClickHouse refuses a request
    # over `http_max_fields` (1000 by default).
    paths
    |> Enum.chunk_every(@blob_paths_chunk)
    |> Enum.flat_map(fn chunk ->
      ClickHouseRepo.all(
        from(f in CommitFile,
          where: f.repository_id == ^repository_id and f.sha == ^sha and f.path in ^chunk,
          group_by: f.path,
          select: {f.path, fragment("argMax(?, ?)", f.git_blob_id, f.inserted_at)}
        )
      )
    end)
    |> Map.new()
  end
end
