defmodule Tuist.TestImpactAnalysis.Baselines do
  @moduledoc """
  Resolves the baseline of coverage-based test selection: the nearest
  ancestor of the checked-out commit with a checkpoint of the requested
  scope (`Tuist.TestImpactAnalysis.Snapshot`), which a fold writes for every
  full run whose results are processed and keeps 31 days.

  The walk starts from the checked-out commit, or, when the server's history
  doesn't have it (GitHub's synthetic merge commit), from the parents the
  client sent, one commit further away. It reads the commit graph
  (`Tuist.GitHistory.ancestors/3`) nearest first, a little deeper each time,
  and the checkpoints among the commits it reached in one read per step.
  Distance isn't capped by commits: the 31-day retention, the history
  window (`window_commits`) and the diff's 5,000-file limit bound it.

  A checkpoint is of the scope when it's on the requested platform (empty
  matches runs that recorded none, `:any` every platform) and of the
  requested scheme (any scheme when absent). A checkpoint holds every full run of its scope at the
  commit, so tests without evidence are in it and selected as
  `no_evidence`, as Swift Testing tests and targets that don't link
  TestCoverageAttribution always are.
  """
  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Commit
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Snapshot

  @walk_depths [64, 256, 1_024]
  @max_ancestor_shas 200

  @doc """
  The baseline for a checkout, as `{:ok, baseline}` with its `sha`, the
  `repository_id` the walk ran in, its `checkpoint`, the full runs the
  checkpoint holds (`run_ids`) and how many commits back it sits
  (`distance`). Otherwise `{:error, reason}`:

  - `:history_unknown`: the history has none of the checked-out commit, the
    parents and the ancestors sent, so the walk can't start. The client
    deepens its checkout and repeats the request with `ancestor_shas`;
  - `:no_baseline`: no ancestor within the history window has a live
    checkpoint of the scope, or the project has no live checkpoint to walk
    from.

  `scope` has the `commit_sha`, and optionally `parent_shas`,
  `ancestor_shas` (the checkout's ancestors the client has, nearest first:
  the first #{@max_ancestor_shas} count, each as far back as its position in
  the list, which is exact for linear history and approximate across
  merges), `platform` and `scheme`. With `baseline_sha:` only that commit
  can be the baseline: what the runs request uses to find the checkpoint of
  the baseline the client diffed against. With `ancestors_only: true` the
  checked-out commit itself can't be: what coverage carry uses, whose fold
  may already have written the commit's own checkpoint.
  """
  def resolve(%Project{} = project, scope, opts \\ []) do
    commit_sha = Map.fetch!(scope, :commit_sha)
    parent_shas = Map.get(scope, :parent_shas) || []
    ancestor_shas = scope |> Map.get(:ancestor_shas) |> List.wrap() |> Enum.take(@max_ancestor_shas)

    scope = %{
      platform: Map.get(scope, :platform) || "",
      scheme: Map.get(scope, :scheme),
      ancestors_only: Keyword.get(opts, :ancestors_only, false)
    }

    case starts(project, commit_sha, parent_shas, ancestor_shas) do
      {:error, reason} ->
        {:error, reason}

      {repository_id, starts} ->
        max_depth = GitHistory.settings(project).window_commits
        depths = Enum.filter(@walk_depths, &(&1 < max_depth)) ++ [max_depth]
        walk(project, repository_id, starts, scope, Keyword.get(opts, :baseline_sha), depths, max_depth)
    end
  end

  # The repository is the one of the project's checkpoints that has the
  # checked-out commit, or else most of its parents and ancestors. Ancestors
  # the history lacks carry no coverage, so only the known ones are walked
  # from, each at its distance: 1 for a parent, its position for an ancestor.
  defp starts(project, commit_sha, parent_shas, ancestor_shas) do
    repositories =
      Repo.all(
        from(s in Snapshot,
          where: s.project_id == ^project.id and s.kind == :checkpoint and s.expires_at > ^DateTime.utc_now(),
          distinct: true,
          select: s.repository_id
        )
      )

    known =
      Repo.all(
        from(c in Commit,
          where: c.repository_id in ^repositories and c.sha in ^Enum.uniq([commit_sha | parent_shas ++ ancestor_shas]),
          select: {c.repository_id, c.sha}
        )
      )

    cond do
      repositories == [] -> {:error, :no_baseline}
      known == [] -> {:error, :history_unknown}
      true -> start(known, commit_sha, distances(parent_shas, ancestor_shas))
    end
  end

  defp distances(parent_shas, ancestor_shas) do
    ancestor_shas
    |> Enum.with_index(1)
    |> Map.new()
    |> Map.merge(Map.new(parent_shas, &{&1, 1}))
  end

  defp start(known, commit_sha, distances) do
    case Enum.find(known, &(elem(&1, 1) == commit_sha)) do
      {repository_id, _sha} ->
        {repository_id, [{commit_sha, 0}]}

      nil ->
        known
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.max_by(fn {repository_id, shas} -> {length(shas), repository_id} end)
        |> then(fn {repository_id, shas} -> {repository_id, Enum.map(shas, &{&1, Map.fetch!(distances, &1)})} end)
    end
  end

  # Walks a little deeper each time, so the common case (a baseline a few
  # commits back) reads a few dozen commits rather than the history window.
  defp walk(project, repository_id, starts, scope, fixed, [depth | deeper], max_depth) do
    ancestors = ancestors(repository_id, starts, depth)
    exhausted = deeper == [] or Enum.all?(ancestors, fn {_sha, d} -> d < depth end)
    candidates = if fixed, do: Enum.filter(ancestors, &(elem(&1, 0) == fixed)), else: ancestors
    candidates = if scope.ancestors_only, do: Enum.reject(candidates, &(elem(&1, 1) == 0)), else: candidates
    checkpoints = checkpoints(project.id, repository_id, Enum.map(candidates, &elem(&1, 0)), scope)

    case Enum.find(candidates, &Map.has_key?(checkpoints, elem(&1, 0))) do
      {sha, distance} ->
        checkpoint = Map.fetch!(checkpoints, sha)

        {:ok,
         %{
           sha: sha,
           repository_id: repository_id,
           checkpoint: checkpoint,
           run_ids: checkpoint.test_run_ids,
           distance: distance
         }}

      # A fixed baseline the walk reached without a checkpoint stays without one.
      nil when exhausted or (fixed != nil and candidates != []) ->
        {:error, :no_baseline}

      nil ->
        walk(project, repository_id, starts, scope, fixed, deeper, max_depth)
    end
  end

  defp ancestors(repository_id, starts, depth) do
    starts
    |> Enum.flat_map(fn {sha, offset} ->
      repository_id
      |> GitHistory.ancestors(sha, max_depth: max(depth - offset, 0))
      |> Enum.map(fn {ancestor, d} -> {ancestor, d + offset} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {sha, depths} -> {sha, Enum.min(depths)} end)
    |> Enum.sort_by(fn {sha, d} -> {d, sha} end)
  end

  # The newest live checkpoint of the scope at each of `shas` that has one.
  defp checkpoints(_project_id, _repository_id, [], _scope), do: %{}

  defp checkpoints(project_id, repository_id, shas, scope) do
    query =
      from(s in Snapshot,
        where:
          s.project_id == ^project_id and s.repository_id == ^repository_id and s.kind == :checkpoint and
            s.commit_sha in ^shas and s.expires_at > ^DateTime.utc_now(),
        order_by: [asc: s.ran_at, asc: s.inserted_at]
      )

    query = if scope.scheme in [nil, ""], do: query, else: where(query, [s], s.scheme == ^scope.scheme)
    query = if scope.platform == :any, do: query, else: where(query, [s], s.platform == ^scope.platform)
    query |> Repo.all() |> Map.new(&{&1.commit_sha, &1})
  end
end
