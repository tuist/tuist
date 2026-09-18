defmodule Tuist.Tests.Coverage.History do
  @moduledoc """
  Coverage over the project's history: a branch commit by commit, every
  branch's head, and a pull request's commits.

  Branch membership comes from the repository's commit graph
  (`Tuist.GitHistory`), not from the branch a run was labelled with: the
  commits of a branch are the first-parent walk from its recorded head, so
  a commit measured on a pull request is on `main` once the branch is
  fast-forwarded, and a merged branch's commits stay with the pull request.
  A branch whose head the graph does not know (a run that sent a commit but
  no history) falls back to the measured commits labelled with it, in time
  order, and says so (`ordered_by: :time`).

  A commit **chains** into the trend when it is complete (the client
  signalled its pipeline finished) or, failing a signal, when it measured
  the same schemes, each as fully, as the previous chained commit: two
  commits measured alike compare as a whole; anything else only compares
  per scheme. The first measured commit chains on its own. Unchained commits
  stay in the history with their measured set and out of the chart.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Test

  @doc """
  The repository the project's measured commits belong to (the newest
  published commit's), or nil when none named one.
  """
  def repository_id(project_id) do
    ClickHouseRepo.one(
      from(c in subquery(Commits.commits_query(project_id)),
        where: c.git_repository_id > 0,
        order_by: [desc: c.inserted_at],
        limit: 1,
        select: c.git_repository_id
      )
    )
  end

  @doc """
  The commits of a branch, newest first, each with its measurement when
  there is one: `%{git_commit_sha, depth, committed_at, measured, chained,
  coverage, ...}` (the `Tuist.Tests.Coverage.Commits.commits_query/1` fields
  when measured). `ordered_by` in the result says whether the order is the
  graph's (`:graph`) or, without a recorded head, the runs' time (`:time`).
  `since` and `until` bound the measurements considered (`NaiveDateTime`);
  `limit` caps the commits returned (the newest), 200 by default.
  """
  def branch_history(%Project{} = project, branch, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    measured = measured_by_sha(project.id, opts)
    repository_id = repository_id(project.id)

    graph =
      if repository_id,
        do: GitHistory.branch_commits(repository_id, branch, max_depth: limit),
        else: []

    {commits, ordered_by} =
      case graph do
        [] ->
          {project.id |> labelled_commits(branch, measured, opts) |> Enum.take(limit), :time}

        chain ->
          {Enum.map(chain, fn {sha, depth, committed_at} ->
             %{git_commit_sha: sha, depth: depth, committed_at: committed_at}
           end), :graph}
      end

    commits =
      commits
      |> Enum.map(fn commit ->
        case Map.get(measured, commit.git_commit_sha) do
          nil -> Map.merge(commit, %{measured: false, chained: false})
          row -> commit |> Map.merge(row) |> Map.put(:measured, true)
        end
      end)
      |> chain()

    %{commits: commits, ordered_by: ordered_by}
  end

  # Oldest first for the chaining rule, then back to newest first.
  defp chain(commits) do
    commits
    |> Enum.reverse()
    |> Enum.map_reduce(nil, fn commit, previous ->
      cond do
        not commit.measured ->
          {commit, previous}

        commit.complete or is_nil(previous) or same_measured_set?(commit, previous) ->
          {Map.put(commit, :chained, true), commit}

        true ->
          {Map.put(commit, :chained, false), previous}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp same_measured_set?(a, b), do: a.schemes == b.schemes and a.partial_schemes == b.partial_schemes

  @doc """
  One point per chained commit of the branch, oldest first, with the
  totals: what the trend chart draws. With `scheme:`, the points are that
  scheme's own totals (its newest full run at each commit) at the commits
  that measured it fully.
  """
  def branch_points(%Project{} = project, branch, opts \\ []) do
    {scheme, opts} = Keyword.pop(opts, :scheme)

    points =
      project
      |> branch_history(branch, opts)
      |> Map.fetch!(:commits)
      |> Enum.filter(& &1.chained)
      |> Enum.reverse()

    case scheme do
      nil ->
        points

      scheme ->
        totals = scheme_totals_by_sha(project.id, scheme, Enum.map(points, & &1.git_commit_sha))

        points
        |> Enum.filter(&Map.has_key?(totals, &1.git_commit_sha))
        |> Enum.map(fn point -> point |> Map.merge(Map.fetch!(totals, point.git_commit_sha)) |> with_coverage() end)
    end
  end

  # The newest full run of the scheme at each of the commits, keyed by SHA.
  defp scheme_totals_by_sha(_project_id, _scheme, []), do: %{}

  defp scheme_totals_by_sha(project_id, scheme, shas) do
    from(c in subquery(Coverage.run_totals_query(project_id)),
      join: t in subquery(runs_query(project_id, [])),
      on: t.id == c.test_run_id,
      where: c.scheme == ^scheme and c.partial == false and c.git_commit_sha in ^shas,
      group_by: c.git_commit_sha,
      select: %{
        git_commit_sha: c.git_commit_sha,
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, t.ran_at),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, t.ran_at)
      }
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.git_commit_sha, Map.delete(&1, :git_commit_sha)})
  end

  @doc """
  One page of the branch's commits, newest first: the commits of
  `branch_history/3` that the period holds, unmeasured ones included, so the
  list and the chart describe the same stretch of the branch. `page` is
  1-based, `page_size` is 20 by default, and `walk_limit` (1000) bounds how
  far back the branch is walked. Chaining and each commit's `change` against
  the commit chained before it are computed over the whole walk, so neither
  depends on the window's edge or on where a page was cut.
  """
  def commit_page(%Project{} = project, branch, opts \\ []) do
    {page, opts} = Keyword.pop(opts, :page, 1)
    {page_size, opts} = Keyword.pop(opts, :page_size, 20)
    {walk_limit, opts} = Keyword.pop(opts, :walk_limit, 1000)
    page = max(page, 1)

    history = branch_history(project, branch, Keyword.put(opts, :limit, walk_limit))
    commits = history.commits |> with_changes() |> Enum.filter(&in_period?(&1, opts))
    total_pages = max(1, ceil(length(commits) / page_size))
    page = min(page, total_pages)

    %{
      commits: commits |> Enum.drop((page - 1) * page_size) |> Enum.take(page_size),
      ordered_by: history.ordered_by,
      page: page,
      page_size: page_size,
      total_pages: total_pages,
      total_count: length(commits)
    }
  end

  # Each chained commit's difference from the one chained before it, computed
  # over the whole walk so a page does not depend on where it was cut.
  defp with_changes(commits) do
    commits
    |> Enum.reverse()
    |> Enum.map_reduce(nil, fn commit, previous ->
      change = if commit.chained and previous, do: Float.round(commit.coverage - previous.coverage, 1)
      {Map.put(commit, :change, change), if(commit.chained, do: commit, else: previous)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp in_period?(%{committed_at: nil}, _opts), do: true

  defp in_period?(%{committed_at: committed_at}, opts) do
    committed_at = naive(committed_at)
    since = opts |> Keyword.get(:since) |> naive()
    until = opts |> Keyword.get(:until) |> naive()

    (is_nil(since) or NaiveDateTime.compare(committed_at, since) != :lt) and
      (is_nil(until) or NaiveDateTime.compare(committed_at, until) != :gt)
  end

  defp naive(nil), do: nil
  defp naive(%DateTime{} = datetime), do: DateTime.to_naive(datetime)
  defp naive(%NaiveDateTime{} = datetime), do: datetime

  @doc """
  The branches and pull requests with a measured commit in the period, the
  most recently measured first: one row per ref with its newest measured
  commit and that commit's totals, which is where the page's list of refs
  sends the reader. A pull request is a ref of its own, since its commits
  belong to it until it is merged.

  `search` narrows by branch name or pull request number, `page` and
  `page_size` paginate (20 by default). `delta` is the difference from the
  default branch's newest chained commit, nil unless both sides measured the
  same set, since anything else only compares per scheme.
  """
  def refs(%Project{} = project, opts \\ []) do
    {page, opts} = Keyword.pop(opts, :page, 1)
    {page_size, opts} = Keyword.pop(opts, :page_size, 20)
    {search, opts} = Keyword.pop(opts, :search)
    page = max(page, 1)

    query = refs_query(project.id, search, opts)
    total = ClickHouseRepo.one(from(r in subquery(query), select: count())) || 0
    total_pages = max(1, ceil(total / page_size))
    page = min(page, total_pages)

    [rows, default] =
      Tuist.Tasks.parallel_tasks([
        fn ->
          query
          |> limit(^page_size)
          |> offset(^((page - 1) * page_size))
          |> ClickHouseRepo.all()
          |> Enum.map(&with_coverage/1)
        end,
        fn -> latest(project, project.default_branch, opts) end
      ])

    %{
      refs: Enum.map(rows, &with_delta(&1, default, project.default_branch)),
      page: page,
      page_size: page_size,
      total_pages: total_pages,
      total_count: total
    }
  end

  # The default branch is the baseline, so it has no difference of its own.
  defp with_delta(%{kind: "branch", name: branch} = ref, _default, branch), do: Map.put(ref, :delta, nil)

  defp with_delta(ref, nil, _default_branch), do: Map.put(ref, :delta, nil)

  defp with_delta(ref, default, _default_branch) do
    comparable = ref.schemes == default.schemes and ref.partial_schemes == default.partial_schemes

    Map.put(ref, :delta, if(comparable, do: Float.round(ref.coverage - default.coverage, 1)))
  end

  defp refs_query(project_id, search, opts) do
    runs =
      from(t in subquery(runs_query(project_id, opts)),
        where: t.git_commit_sha != "" and (t.is_pull_request == true or t.git_branch != ""),
        select: %{
          kind: fragment("if(?, 'pull_request', 'branch')", t.is_pull_request),
          name:
            fragment(
              "if(?, concat('#', toString(?)), ?)",
              t.is_pull_request,
              t.pull_request_number,
              t.git_branch
            ),
          pull_request_number: t.pull_request_number,
          git_branch: t.git_branch,
          base_branch: t.base_branch,
          git_commit_sha: t.git_commit_sha,
          ran_at: t.ran_at
        }
      )

    query =
      from(r in subquery(runs),
        join: c in subquery(Commits.commits_query(project_id)),
        on: c.git_commit_sha == r.git_commit_sha,
        group_by: [r.kind, r.name],
        select: %{
          kind: r.kind,
          name: r.name,
          pull_request_number: fragment("argMax(?, ?)", r.pull_request_number, r.ran_at),
          git_branch: fragment("argMax(?, ?)", r.git_branch, r.ran_at),
          base_branch: fragment("argMax(?, ?)", r.base_branch, r.ran_at),
          git_commit_sha: fragment("argMax(?, ?)", r.git_commit_sha, r.ran_at),
          ran_at: max(r.ran_at),
          covered_lines: fragment("argMax(?, ?)", c.covered_lines, r.ran_at),
          executable_lines: fragment("argMax(?, ?)", c.executable_lines, r.ran_at),
          files_count: fragment("argMax(?, ?)", c.files_count, r.ran_at),
          unmeasured_files_count: fragment("argMax(?, ?)", c.unmeasured_files_count, r.ran_at),
          schemes: fragment("argMax(?, ?)", c.schemes, r.ran_at),
          partial_schemes: fragment("argMax(?, ?)", c.partial_schemes, r.ran_at),
          complete: fragment("argMax(?, ?)", c.complete, r.ran_at),
          completeness: fragment("argMax(?, ?)", c.completeness, r.ran_at)
        },
        order_by: [desc: max(r.ran_at)]
      )

    # A pull request is listed by its number, so its branch name is matched too:
    # the reader knows the branch they pushed, not always the number it got.
    case search do
      blank when blank in [nil, ""] ->
        query

      search ->
        from(r in query,
          where:
            fragment("positionCaseInsensitive(?, ?) > 0", r.name, ^search) or
              fragment("positionCaseInsensitive(?, ?) > 0", r.git_branch, ^search)
        )
    end
  end

  @doc "The newest chained commit of the branch, with its totals, or nil."
  def latest(%Project{} = project, branch, opts \\ []) do
    project
    |> branch_history(branch, Keyword.put_new(opts, :limit, 200))
    |> Map.fetch!(:commits)
    |> Enum.find(& &1.chained)
  end

  @doc "The schemes measured on the branch's commits in the period, most commits first."
  def schemes(%Project{} = project, branch, opts \\ []) do
    project
    |> branch_history(branch, opts)
    |> Map.fetch!(:commits)
    |> Enum.filter(& &1.measured)
    |> Enum.flat_map(& &1.schemes)
    |> Enum.frequencies()
    |> Enum.map(fn {scheme, count} -> %{scheme: scheme, commits_count: count} end)
    |> Enum.sort_by(&{-&1.commits_count, &1.scheme})
  end

  @doc "The branches with a measured commit in the period, the most recently measured first."
  def branch_names(project_id, opts \\ []) do
    ClickHouseRepo.all(
      from(c in subquery(Commits.commits_query(project_id)),
        join: t in subquery(runs_query(project_id, opts)),
        on: t.git_commit_sha == c.git_commit_sha,
        where: t.git_branch != "",
        group_by: t.git_branch,
        select: t.git_branch,
        order_by: [desc: max(t.ran_at)]
      )
    )
  end

  @doc """
  Every branch with a measured commit in the period, newest first, with its
  head commit's totals (the recorded head when the graph knows it and it is
  measured, else the branch's newest chained commit) and the branch's
  difference from the project's default branch (`delta`, nil when either
  side is unchained or the default branch has none).
  """
  def branches(%Project{default_branch: default_branch} = project, opts \\ []) do
    branches =
      project.id
      |> branch_names(opts)
      |> Enum.map(fn branch ->
        history = branch_history(project, branch, Keyword.put(opts, :limit, 200))
        head = Enum.find(history.commits, & &1.measured)

        Map.merge(head || %{git_commit_sha: nil, coverage: nil, chained: false}, %{
          git_branch: branch,
          ordered_by: history.ordered_by
        })
      end)
      |> Enum.reject(&is_nil(&1.git_commit_sha))

    default = Enum.find(branches, &(&1.git_branch == default_branch and &1.chained))

    Enum.map(branches, fn branch ->
      Map.put(
        branch,
        :delta,
        if(default && branch.chained, do: Float.round(branch.coverage - default.coverage, 1))
      )
    end)
  end

  @doc """
  The commits of one pull request that gathered coverage, newest first,
  each with its measurement (`Tuist.Tests.Coverage.Commits.commits_query/1`
  fields), the branch and base branch its runs reported, and when it was
  first measured: what the pull request page lists.
  """
  def pull_request_commits(project_id, pull_request_number, opts \\ []) do
    runs =
      from(t in runs_query(project_id, opts),
        where: t.is_pull_request == true and t.pull_request_number == ^pull_request_number
      )

    from(c in subquery(Commits.commits_query(project_id)),
      join: t in subquery(runs),
      on: t.git_commit_sha == c.git_commit_sha,
      group_by: c.git_commit_sha,
      select: %{
        git_commit_sha: c.git_commit_sha,
        git_branch: fragment("argMax(?, ?)", t.git_branch, t.ran_at),
        base_branch: fragment("argMax(?, ?)", t.base_branch, t.ran_at),
        ran_at: max(t.ran_at),
        covered_lines: fragment("any(?)", c.covered_lines),
        executable_lines: fragment("any(?)", c.executable_lines),
        schemes: fragment("any(?)", c.schemes),
        partial_schemes: fragment("any(?)", c.partial_schemes),
        complete: fragment("any(?)", c.complete),
        completeness: fragment("any(?)", c.completeness),
        test_run_ids: type(fragment("any(?)", c.test_run_ids), {:array, Ecto.UUID})
      },
      order_by: [desc: max(t.ran_at)]
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&with_coverage/1)
  end

  # The measured commits with a run in the period, keyed by SHA.
  defp measured_by_sha(project_id, opts) do
    query = Commits.commits_query(project_id)

    query =
      if Keyword.has_key?(opts, :since) or Keyword.has_key?(opts, :until) do
        in_period = from(t in subquery(runs_query(project_id, opts)), select: t.git_commit_sha)
        from(c in subquery(query), where: c.git_commit_sha in subquery(in_period))
      else
        query
      end

    query
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.git_commit_sha, with_coverage(&1)})
  end

  # Without a graph, a branch is the measured commits its runs labelled with
  # it, newest run first.
  defp labelled_commits(project_id, branch, measured, opts) do
    from(t in subquery(runs_query(project_id, opts)),
      where: t.git_branch == ^branch and t.git_commit_sha != "",
      group_by: t.git_commit_sha,
      select: {t.git_commit_sha, max(t.ran_at)},
      order_by: [desc: max(t.ran_at)]
    )
    |> ClickHouseRepo.all()
    |> Enum.filter(fn {sha, _ran_at} -> Map.has_key?(measured, sha) end)
    |> Enum.with_index()
    |> Enum.map(fn {{sha, ran_at}, depth} -> %{git_commit_sha: sha, depth: depth, committed_at: ran_at} end)
  end

  # One row per run, whatever the history rewrites added: `test_runs` keeps
  # a row per update and the newest carries the run's current history.
  defp runs_query(project_id, opts) do
    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        group_by: t.id,
        select: %{
          id: t.id,
          git_branch: fragment("any(?)", t.git_branch),
          git_commit_sha: fragment("any(?)", t.git_commit_sha),
          scheme: fragment("any(?)", t.scheme),
          ran_at: min(t.ran_at),
          is_pull_request: fragment("argMax(?, ?)", t.is_pull_request, t.inserted_at),
          pull_request_number: fragment("argMax(?, ?)", t.pull_request_number, t.inserted_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.inserted_at)
        }
      )

    query =
      case Keyword.get(opts, :since) do
        nil -> query
        since -> where(query, [t], t.ran_at >= ^since)
      end

    case Keyword.get(opts, :until) do
      nil -> query
      until -> where(query, [t], t.ran_at <= ^until)
    end
  end

  defp with_coverage(row), do: Map.put(row, :coverage, Coverage.percentage(row.covered_lines, row.executable_lines))
end
