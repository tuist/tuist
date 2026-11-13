defmodule Tuist.TestImpactAnalysis.Baselines do
  @moduledoc """
  Resolves the baseline of coverage-based test selection: the nearest
  ancestor of the checked-out commit with a full run of the requested scope
  and a complete file listing, within the evidence window.

  The walk starts from the checked-out commit, or, when the server's history
  doesn't have it (GitHub's synthetic merge commit), from the parents the
  client sent, one commit further away. It reads the commit graph
  (`Tuist.GitHistory.ancestors/3`) nearest first and the project's commit
  coverage (`Tuist.Tests.CoverageCommit`) beside it, the same measured set
  `Tuist.Tests.Coverage.Commits.nearest_measured_ancestor/5` reads. Commits
  without coverage are walked but not counted; at most 20 commits with
  coverage may sit between the checkout and the baseline, the baseline
  included.

  A full run is a run at the commit that:

  - ran the requested scheme, which the commit's measured set lists in
    `schemes` and not in `partial_schemes`;
  - ran it whole: its coverage isn't partial, so no `-only-testing` narrowed
    it and every shard reported (`Tuist.Tests.CoverageRun`);
  - ran on the requested platform.

  It needn't have uploaded test-scoped evidence: each test's evidence comes
  from whichever run recorded it, and tests without any are selected by the
  `no_evidence` rule, as Swift Testing tests and targets that don't link
  TestCoverageAttribution always are.

  The commit also needs a complete file listing
  (`Tuist.GitHistory.listing_complete?/2`), which the baseline's blobs are
  read from: a commit with a full run whose files can't be read whole (no
  file changes written, and a missing, expired or truncated listing) is
  passed over, and the walk goes on to the next ancestor.

  A commit's measured set is only written once its runs' coverage is folded,
  so a run still being processed isn't eligible yet.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.GitHistory.Commit
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageRun

  @window_measured_commits 20
  @walk_depths [64, 256, 1_024]
  @max_ancestor_shas 200

  @doc """
  The baseline for a checkout, as `{:ok, baseline}` with its `sha`, the
  `repository_id` the walk ran in, the full runs at it (`run_ids`), the
  evidence window's commits (`window_shas`, the checked-out commit's
  ancestors down to the baseline's depth) and how many commits with coverage
  it sits back (`distance`). Otherwise `{:error, reason}`:

  - `:history_unknown`: the history has none of the checked-out commit, the
    parents and the ancestors sent, so the walk can't start. The client
    deepens its checkout and repeats the request with `ancestor_shas`;
  - `:no_baseline`: no full run on the platform at a commit with a complete
    file listing is an ancestor within the history window, or the project
    has no coverage to walk from;
  - `:baseline_too_old`: the nearest such run is more than #{@window_measured_commits}
    commits with coverage back.

  `scope` has the `commit_sha`, and optionally `parent_shas`,
  `ancestor_shas` (the checkout's ancestors the client has, nearest first:
  the first #{@max_ancestor_shas} count, each as far back as its position in
  the list, which is exact for linear history and approximate across
  merges), `platform`
  (empty when absent, matching runs that recorded none) and `scheme` (any
  scheme when absent). With `baseline_sha:` only that commit can be the
  baseline: what the runs request uses to rebuild the window for the
  baseline the client diffed against.
  """
  def resolve(%Project{} = project, scope, opts \\ []) do
    commit_sha = Map.fetch!(scope, :commit_sha)
    parent_shas = Map.get(scope, :parent_shas) || []
    ancestor_shas = scope |> Map.get(:ancestor_shas) |> List.wrap() |> Enum.take(@max_ancestor_shas)
    scope = %{platform: Map.get(scope, :platform) || "", scheme: Map.get(scope, :scheme)}

    case starts(project, commit_sha, parent_shas, ancestor_shas) do
      {:error, reason} ->
        {:error, reason}

      {repository_id, starts} ->
        max_depth = GitHistory.settings(project).window_commits
        depths = Enum.filter(@walk_depths, &(&1 < max_depth)) ++ [max_depth]
        walk(project, repository_id, starts, scope, Keyword.get(opts, :baseline_sha), depths, max_depth)
    end
  end

  # The repository is the one of the project's coverage that has the
  # checked-out commit, or else most of its parents and ancestors. Ancestors
  # the history lacks carry no coverage, so only the known ones are walked
  # from, each at its distance: 1 for a parent, its position for an ancestor.
  defp starts(project, commit_sha, parent_shas, ancestor_shas) do
    repositories =
      Repo.all(
        from(c in CoverageCommit,
          where: c.project_id == ^project.id and not is_nil(c.repository_id),
          distinct: true,
          select: c.repository_id
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

    case decide(project, repository_id, ancestors, scope, fixed, exhausted) do
      :undecided -> walk(project, repository_id, starts, scope, fixed, deeper, max_depth)
      {:ok, baseline} -> {:ok, Map.put(baseline, :repository_id, repository_id)}
      {:error, _reason} = error -> error
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

  defp decide(project, repository_id, ancestors, scope, fixed, exhausted) do
    {ranked, counted} = rank(ancestors, measured(project.id, Enum.map(ancestors, &elem(&1, 0))))
    candidates = Enum.filter(ranked, &(candidate?(&1.commit, scope) and (is_nil(fixed) or &1.sha == fixed)))
    runs = project.id |> full_runs(candidates, scope) |> with_complete_listing(repository_id)
    {within, beyond} = Enum.split_with(candidates, &(&1.rank <= @window_measured_commits))

    case Enum.find(within, &Map.has_key?(runs, &1.sha)) do
      nil ->
        verdict(beyond, runs, exhausted or counted >= @window_measured_commits, exhausted)

      baseline ->
        {:ok,
         %{
           sha: baseline.sha,
           run_ids: Map.fetch!(runs, baseline.sha),
           window_shas: for({sha, depth} <- ancestors, depth <= baseline.depth, do: sha),
           distance: baseline.rank
         }}
    end
  end

  # Why there's no baseline, once the walk saw the whole window. Telling a
  # baseline too old from none needs the walk to reach a full run past it.
  defp verdict(_beyond, _runs, false = _window_complete, _exhausted), do: :undecided

  defp verdict(beyond, runs, true = _window_complete, exhausted) do
    cond do
      Enum.any?(beyond, &Map.has_key?(runs, &1.sha)) -> {:error, :baseline_too_old}
      exhausted -> {:error, :no_baseline}
      true -> :undecided
    end
  end

  # A commit's rank is how many commits with coverage sit back to it, itself
  # included; the checked-out commit's is zero.
  defp rank(ancestors, measured) do
    ancestors
    |> Enum.filter(fn {sha, _depth} -> Map.has_key?(measured, sha) end)
    |> Enum.map_reduce(0, fn {sha, depth}, count ->
      count = if depth == 0, do: count, else: count + 1
      {%{sha: sha, depth: depth, rank: count, commit: Map.fetch!(measured, sha)}, count}
    end)
  end

  # The walked commits with coverage: a measured set with runs. A commit whose
  # every scheme was skipped whole has a row without runs and isn't counted.
  defp measured(_project_id, []), do: %{}

  defp measured(project_id, shas) do
    shas
    |> Coverage.id_chunks(1)
    |> Enum.flat_map(fn chunk ->
      Repo.all(
        from(c in CoverageCommit,
          where:
            c.project_id == ^project_id and c.git_commit_sha in ^chunk and fragment("cardinality(?) > 0", c.test_run_ids),
          select: %{
            sha: c.git_commit_sha,
            schemes: c.schemes,
            partial_schemes: c.partial_schemes,
            test_run_ids: c.test_run_ids
          }
        )
      )
    end)
    |> Map.new(&{&1.sha, &1})
  end

  defp candidate?(commit, %{scheme: nil}), do: commit.schemes != []

  defp candidate?(commit, %{scheme: scheme}), do: scheme in commit.schemes and scheme not in commit.partial_schemes

  # Per candidate commit, its full runs on the platform, as
  # `%{sha => run_ids}`: the commit is in the map when it has any.
  defp full_runs(_project_id, [], _scope), do: %{}

  defp full_runs(project_id, candidates, scope) do
    sha_by_run =
      for %{sha: sha, commit: commit} <- candidates, run_id <- commit.test_run_ids, into: %{}, do: {run_id, sha}

    run_ids = Map.keys(sha_by_run)
    full = run_ids |> chunked(&whole_runs(project_id, &1, scope)) |> MapSet.new()

    for run_id <- run_ids, MapSet.member?(full, run_id), reduce: %{} do
      acc -> Map.update(acc, Map.fetch!(sha_by_run, run_id), [run_id], &(&1 ++ [run_id]))
    end
  end

  defp chunked(ids, fun), do: ids |> Coverage.id_chunks(1) |> Enum.flat_map(fun)

  # Selection reads the baseline's blobs, so a path its files lack would read
  # as changed and select every test that ran it.
  defp with_complete_listing(runs, _repository_id) when runs == %{}, do: runs

  defp with_complete_listing(runs, repository_id) do
    complete =
      runs
      |> Map.keys()
      |> Coverage.id_chunks(2)
      |> Enum.flat_map(&GitHistory.complete_listings(repository_id, &1))

    Map.take(runs, complete)
  end

  defp whole_runs(project_id, run_ids, scope) do
    query =
      from(r in CoverageRun,
        where: r.project_id == ^project_id and r.test_run_id in ^run_ids,
        group_by: r.test_run_id,
        having:
          fragment("NOT argMax(?, ?)", r.partial, r.version) and
            fragment("argMax(?, ?) = ?", r.platform, r.version, ^scope.platform),
        select: fragment("toString(?)", r.test_run_id)
      )

    query =
      case scope.scheme do
        nil -> query
        scheme -> having(query, [r], fragment("argMax(?, ?) = ?", r.scheme, r.version, ^scheme))
      end

    ClickHouseRepo.all(query)
  end
end
