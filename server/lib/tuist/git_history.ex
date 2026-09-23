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
  alias Tuist.GitHistory.BranchHead
  alias Tuist.GitHistory.Commit
  alias Tuist.GitHistory.CommitFile
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.CommitParent
  alias Tuist.GitHistory.Providers
  alias Tuist.GitHistory.Repository
  alias Tuist.GitHistory.Workers.CompleteHistoryWorker
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Test
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  @defaults %{
    window_days: 365,
    window_commits: 5_000,
    deepen_budget_seconds: 60,
    upload_batch_size: 500,
    provider_fallback: true,
    provider_page_budget: 20,
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
  - `provider_fallback`: whether the server completes history from the VCS
    provider, and `provider_page_budget`, the API pages one run may spend;
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

  @doc """
  The repository of a project's connected VCS repository (for the provider
  fallback, which knows the repository by its handle), or nil.
  """
  def repository_id_for_connection(%Project{vcs_connection: %VCSConnection{} = connection} = project) do
    repository_id(
      project.account_id,
      "https://#{provider_host(connection.provider)}/#{connection.repository_full_handle}"
    )
  end

  def repository_id_for_connection(_project), do: nil

  defp provider_host(:github), do: "github.com"
  defp provider_host(provider), do: to_string(provider)

  @doc """
  The project's VCS connection when it can answer history questions: a
  repository connected through a GitHub App installation with credentials.
  Expects `vcs_connection: :github_app_installation` preloaded.
  """
  def provider_connection(%Project{
        vcs_connection: %VCSConnection{github_app_installation: %GitHubAppInstallation{} = installation} = connection
      }) do
    if VCS.github_app_credentials(installation), do: connection
  end

  def provider_connection(_project), do: nil

  @doc "The `Tuist.GitHistory.Provider` for a connection."
  def provider(%VCSConnection{provider: :github}), do: Providers.GitHub

  @doc """
  Enqueues the completion of a run's history from the VCS provider when the
  client did not send it all, the project has a connected repository and its
  settings allow the fallback. `project` needs `vcs_connection:
  :github_app_installation` preloaded. A run from another repository than
  the connected one (a fork, a mirror) is left alone: the provider could not
  answer for it.
  """
  def enqueue_completion(%Project{} = project, %Test{} = run) do
    incomplete? = run.history_source != "client" or run.merge_base_sha in [nil, ""]

    with true <- incomplete? and settings(project).provider_fallback,
         %VCSConnection{} <- provider_connection(project),
         true <- run.git_repository_id in [nil, 0] or run.git_repository_id == repository_id_for_connection(project) do
      %{project_id: project.id, test_run_id: run.id}
      |> CompleteHistoryWorker.new()
      |> Oban.insert()
    else
      _ -> :skipped
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

  @doc "Records the newest commit seen on a branch."
  def record_branch_head(repository_id, branch, sha) when is_binary(branch) and branch != "" and is_binary(sha) do
    Repo.insert_all(
      BranchHead,
      [
        %{repository_id: repository_id, branch: branch, sha: sha, seen_at: DateTime.truncate(DateTime.utc_now(), :second)}
      ],
      on_conflict: {:replace, [:sha, :seen_at]},
      conflict_target: [:repository_id, :branch]
    )

    :ok
  end

  def record_branch_head(_repository_id, _branch, _sha), do: :ok

  @doc "The newest commit recorded for a branch, or nil."
  def branch_head(repository_id, branch) do
    Repo.one(from(h in BranchHead, where: h.repository_id == ^repository_id and h.branch == ^branch, select: h.sha))
  end

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
  The commits of a branch, newest first, as `first_parent_chain/3` from the
  branch's recorded head; empty when no head is recorded.
  """
  def branch_commits(repository_id, branch, opts \\ []) do
    case branch_head(repository_id, branch) do
      nil -> []
      head -> first_parent_chain(repository_id, head, opts)
    end
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

  @doc "Whether `ancestor` is `sha` or one of its ancestors within the walk bounds."
  def ancestor?(repository_id, ancestor, sha, opts \\ []) do
    nearest_ancestor(repository_id, sha, [ancestor], opts) != nil
  end

  @doc """
  The first parent of a commit, or nil when the graph does not know it: what
  a commit on its own base branch is compared with.
  """
  def first_parent(repository_id, sha) do
    Repo.one(
      from(p in CommitParent,
        where: p.repository_id == ^repository_id and p.child_sha == ^sha and p.position == 0,
        select: p.parent_sha
      )
    )
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

  @doc "The listing row of a commit (`files_count`, `truncated`, `inserted_at`), or nil."
  def listing(repository_id, sha) do
    Repo.one(from(l in CommitListing, where: l.repository_id == ^repository_id and l.sha == ^sha))
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
