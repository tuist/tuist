defmodule Tuist.GitHistory do
  @moduledoc """
  A project's commit graph, as far back as its history window reaches.

  Coverage comparisons need to know how commits relate, not only which commit
  a run ran on: a pull request's coverage is compared with the newest full run
  on its base branch at the merge base or an ancestor of it, and never with an
  unrelated run. The graph is what proves that ancestry.

  Rows come from two sources. The client uploads the commits it can see in its
  checkout (`missing_shas/2` tells it which ones the server lacks, so uploads
  only add what is new and repeating one changes nothing), and the VCS
  provider fills what the client could not send. Both write the same tables.

  Every walk is bounded by the project's settings (`settings/1`): a window in
  days and commits, applied to what is stored and to how far a walk goes.
  Generation numbers (Git's commit-graph ones, computed on write) let a walk
  looking for one of a set of commits stop descending below the lowest of
  them.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.GitHistory.BranchHead
  alias Tuist.GitHistory.Commit
  alias Tuist.GitHistory.CommitParent
  alias Tuist.GitHistory.Providers
  alias Tuist.GitHistory.Workers.CompleteHistoryWorker
  alias Tuist.Projects.Project
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias Tuist.Tests.Test
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  # The files whose identity a run's evidence depends on beyond the sources a
  # test compiles: dependency manifests and lockfiles, Tuist's generator
  # configuration, toolchain pins, test plans and build settings, and snapshot
  @defaults %{
    window_days: 365,
    window_commits: 5_000,
    deepen_budget_seconds: 60,
    upload_batch_size: 500,
    provider_fallback: true,
    provider_page_budget: 20,
    tracked_file_globs: [],
    tracked_file_limit: 5_000
  }

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
  - `tracked_file_globs`: the files a run snapshots with their blobs
    (`Tuist.Tests.TestRunTrackedFile`), which only the project sets since what
    a run's evidence depends on beyond its sources differs per repository, and
    `tracked_file_limit`, how many a client records before marking the
    snapshot truncated.
  """
  def settings(%Project{} = project) do
    defaults = Map.merge(@defaults, Environment.git_history_defaults())

    overrides =
      %{
        window_days: project.git_history_window_days,
        window_commits: project.git_history_window_commits,
        provider_fallback: project.git_history_provider_fallback,
        tracked_file_globs: project.tracked_file_globs
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(defaults, overrides)
  end

  def settings(nil), do: Map.merge(@defaults, Environment.git_history_defaults())

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
  :github_app_installation` preloaded.
  """
  def enqueue_completion(%Project{} = project, %Test{} = run) do
    complete? = run.history_source != "client" or run.merge_base_sha in [nil, ""]

    if complete? and settings(project).provider_fallback and provider_connection(project) do
      %{project_id: project.id, test_run_id: run.id}
      |> CompleteHistoryWorker.new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  @doc "Of the given SHAs, the ones the project has no commit for."
  def missing_shas(_project_id, []), do: []

  def missing_shas(project_id, shas) do
    shas = Enum.uniq(shas)

    known =
      Repo.all(from(c in Commit, where: c.project_id == ^project_id and c.sha in ^shas, select: c.sha))

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
  def record_commits(_project_id, _object_format, []), do: :ok

  def record_commits(project_id, object_format, commits) do
    commits = commits |> Enum.uniq_by(& &1.sha) |> Enum.sort_by(& &1.committed_at, DateTime)
    parent_shas = commits |> Enum.flat_map(& &1.parents) |> Enum.uniq()

    known_generations =
      from(c in Commit,
        where: c.project_id == ^project_id and c.sha in ^parent_shas,
        select: {c.sha, c.generation}
      )
      |> Repo.all()
      |> Map.new()

    {rows, _generations} =
      Enum.map_reduce(commits, known_generations, fn commit, generations ->
        generation = 1 + Enum.reduce(commit.parents, 0, &max(Map.get(generations, &1, 0), &2))
        now = DateTime.truncate(DateTime.utc_now(), :second)

        row = %{
          project_id: project_id,
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
          %{project_id: project_id, child_sha: commit.sha, parent_sha: parent, position: position}
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
  def record_branch_head(project_id, branch, sha) when is_binary(branch) and branch != "" and is_binary(sha) do
    Repo.insert_all(
      BranchHead,
      [%{project_id: project_id, branch: branch, sha: sha, seen_at: DateTime.truncate(DateTime.utc_now(), :second)}],
      on_conflict: {:replace, [:sha, :seen_at]},
      conflict_target: [:project_id, :branch]
    )

    :ok
  end

  def record_branch_head(_project_id, _branch, _sha), do: :ok

  @doc "The newest commit recorded for a branch, or nil."
  def branch_head(project_id, branch) do
    Repo.one(from(h in BranchHead, where: h.project_id == ^project_id and h.branch == ^branch, select: h.sha))
  end

  @doc "Whether the project has a commit stored for the SHA."
  def known?(project_id, sha) do
    Repo.exists?(from(c in Commit, where: c.project_id == ^project_id and c.sha == ^sha))
  end

  @doc """
  The ancestors of a commit, itself included at depth 0, as `{sha, depth}`
  with the shortest depth per SHA. Bounded by `:max_depth` (the project's
  `window_commits` by default) and, when `:min_generation` is given, to
  commits at or above that generation.
  """
  def ancestors(project_id, sha, opts \\ []) do
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
          JOIN git_commit_parents p ON p.project_id = $1 AND p.child_sha = w.sha
          JOIN git_commits c ON c.project_id = $1 AND c.sha = p.parent_sha
          WHERE w.depth < $3 AND c.generation >= $4
        )
        SELECT sha, min(depth) FROM walk GROUP BY sha ORDER BY min(depth), sha
        """,
        [project_id, sha, max_depth, min_generation]
      )

    Enum.map(rows, fn [sha, depth] -> {sha, depth} end)
  end

  @doc """
  Of `candidates`, the one closest to `sha` along its ancestry (the commit
  itself counts, at distance 0), as `{sha, distance}`, or nil when none is an
  ancestor within the walk bounds. The walk never descends below the lowest
  candidate generation.
  """
  def nearest_ancestor(project_id, sha, candidates, opts \\ [])

  def nearest_ancestor(_project_id, _sha, [], _opts), do: nil

  def nearest_ancestor(project_id, sha, candidates, opts) do
    candidates = MapSet.new(candidates)

    min_generation =
      Repo.one(
        from(c in Commit,
          where: c.project_id == ^project_id and c.sha in ^MapSet.to_list(candidates),
          select: min(c.generation)
        )
      ) || 0

    project_id
    |> ancestors(sha, Keyword.put(opts, :min_generation, min_generation))
    |> Enum.find(fn {ancestor, _depth} -> MapSet.member?(candidates, ancestor) end)
  end

  @doc "Whether `ancestor` is `sha` or one of its ancestors within the walk bounds."
  def ancestor?(project_id, ancestor, sha, opts \\ []) do
    nearest_ancestor(project_id, sha, [ancestor], opts) != nil
  end

  @doc """
  The merge base of two commits from the stored graph: the common ancestor
  with the smallest combined distance, or nil when the graph does not connect
  them within the walk bounds. Best effort; the client's `git merge-base` is
  authoritative when it can run.
  """
  def merge_base(project_id, sha_a, sha_b, opts \\ []) do
    ancestors_b = Map.new(ancestors(project_id, sha_b, opts))

    project_id
    |> ancestors(sha_a, opts)
    |> Enum.filter(fn {sha, _depth} -> Map.has_key?(ancestors_b, sha) end)
    |> Enum.min_by(fn {sha, depth} -> depth + Map.fetch!(ancestors_b, sha) end, fn -> nil end)
    |> case do
      nil -> nil
      {sha, _depth} -> sha
    end
  end

  @doc """
  Drops commits older than the project's window in days, with their parent
  edges. Edges pointing at a dropped commit are kept: they mark where the
  window ends.
  """
  def prune(%Project{id: project_id} = project) do
    cutoff = DateTime.add(DateTime.utc_now(), -settings(project).window_days * 86_400, :second)

    Repo.transaction(fn ->
      expired = from(c in Commit, where: c.project_id == ^project_id and c.committed_at < ^cutoff, select: c.sha)
      Repo.delete_all(from(p in CommitParent, where: p.project_id == ^project_id and p.child_sha in subquery(expired)))
      {count, _} = Repo.delete_all(from(c in Commit, where: c.project_id == ^project_id and c.committed_at < ^cutoff))
      count
    end)
  end
end
