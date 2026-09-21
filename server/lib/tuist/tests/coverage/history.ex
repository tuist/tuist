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
  A branch other than the project's default one holds only the commits it
  added: the walk is cut at its merge base with the default branch, whose own
  history is read by selecting it. A branch the default one already contains
  (fast-forwarded, or merged and left in place) has no merge base of its own
  to cut at, so it holds the commits its runs were labelled with.

  `since` and `until` bound the measurements considered (`NaiveDateTime`);
  `limit` caps the commits walked (the newest), 200 by default. Each commit
  carries the `change` from the commit chained before it, which is settled
  over the whole walk.
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
      |> with_changes()
      |> own_commits(project, branch, ordered_by, repository_id, opts)

    %{commits: commits, ordered_by: ordered_by}
  end

  # A branch other than the default one is read as the commits it added: the
  # first-parent walk carries on into the branch it was cut from, whose
  # history belongs to that branch and is read by selecting it. Chaining and
  # each commit's change are settled before the cut, so the oldest commit
  # kept still compares with the commit the branch left.
  defp own_commits(commits, _project, _branch, :time, _repository_id, _opts), do: commits
  defp own_commits([], _project, _branch, _ordered_by, _repository_id, _opts), do: []
  defp own_commits(commits, _project, _branch, _ordered_by, nil, _opts), do: commits

  defp own_commits(commits, %Project{default_branch: branch}, branch, _ordered_by, _repository_id, _opts), do: commits

  defp own_commits(commits, project, branch, _ordered_by, repository_id, opts) do
    head = commits |> hd() |> Map.fetch!(:git_commit_sha)
    default_head = GitHistory.branch_head(repository_id, project.default_branch)
    base = default_head && GitHistory.merge_base(repository_id, head, default_head)

    cond do
      # Nothing to cut against: no default branch head, or no common commit.
      is_nil(base) ->
        commits

      # The branch diverges from the default one: its own commits are those
      # above the commit they share.
      base != head ->
        Enum.take_while(commits, &(&1.git_commit_sha != base))

      # The branch is contained in the default one — fast-forwarded, or merged
      # and not deleted — so the graph no longer says which commits were its
      # own. What ran on it does: the commits its runs were labelled with,
      # kept in the graph's order.
      true ->
        labelled = labelled_shas(project.id, branch, opts)
        Enum.filter(commits, &MapSet.member?(labelled, &1.git_commit_sha))
    end
  end

  defp labelled_shas(project_id, branch, opts) do
    from(t in subquery(runs_query(project_id, opts)),
      where: t.git_branch == ^branch and t.git_commit_sha != "",
      distinct: true,
      select: t.git_commit_sha
    )
    |> ClickHouseRepo.all()
    |> MapSet.new()
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

  defp same_measured_set?(a, b),
    do: a.schemes == b.schemes and effective_partial_schemes(a) == effective_partial_schemes(b)

  @doc """
  One point per chained commit of the branch, oldest first, with the
  commit's totals: what the trend chart draws. A commit's figure pools the
  schemes that measured it; a scheme's own totals are read per commit
  (`Tuist.Tests.Coverage.Comparison.compare/3`), where a baseline makes
  them comparable.
  """
  def branch_points(%Project{} = project, branch, opts \\ []) do
    project
    |> branch_history(branch, opts)
    |> Map.fetch!(:commits)
    |> Enum.filter(& &1.chained)
    |> Enum.reverse()
  end

  @doc """
  One page of the branch's commits, newest first: the commits of
  `branch_history/3` that the period holds, unmeasured ones included, so the
  list and the chart describe the same stretch of the branch. `page` is
  1-based, `page_size` is 20 by default, `max_commits` caps how many of the
  newest commits the pages hold at all, and `walk_limit` (1000) bounds how
  far back the branch is walked. Chaining and each commit's `change` against
  the commit chained before it are computed over the whole walk, so neither
  depends on the window's edge or on where a page was cut.
  """
  def commit_page(%Project{} = project, branch, opts \\ []) do
    {page, opts} = Keyword.pop(opts, :page, 1)
    {page_size, opts} = Keyword.pop(opts, :page_size, 20)
    {walk_limit, opts} = Keyword.pop(opts, :walk_limit, 1000)
    {max_commits, opts} = Keyword.pop(opts, :max_commits)
    page = max(page, 1)

    history = branch_history(project, branch, Keyword.put(opts, :limit, walk_limit))

    commits =
      history.commits
      |> Enum.filter(&in_period?(&1, opts))
      |> then(&if(max_commits, do: Enum.take(&1, max_commits), else: &1))

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
  The branches with a measured commit in the period, the most recently
  measured first: one row per branch with its newest measured commit, that
  commit's totals, and the pull request its runs reported, if any
  (`pull_request_number`, 0 without one) — a branch and its pull request are
  one thing to the reader, who lands on whichever of the two has more to
  say. A pull request whose runs never named a branch is listed under its
  number.

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
  defp with_delta(%{git_branch: branch} = ref, _default, branch), do: Map.put(ref, :delta, nil)

  defp with_delta(ref, nil, _default_branch), do: Map.put(ref, :delta, nil)

  defp with_delta(ref, default, _default_branch) do
    Map.put(ref, :delta, if(comparable?(ref, default), do: Float.round(ref.coverage - default.coverage, 1)))
  end

  defp refs_query(project_id, search, opts) do
    runs =
      from(t in subquery(runs_query(project_id, opts)),
        where: t.git_commit_sha != "" and (t.is_pull_request == true or t.git_branch != ""),
        select: %{
          # A run that named no branch is filed under its pull request, which
          # is the only name it has.
          name:
            fragment(
              "if(? != '', ?, concat('#', toString(?)))",
              t.git_branch,
              t.git_branch,
              t.pull_request_number
            ),
          git_branch: t.git_branch,
          is_pull_request: t.is_pull_request,
          pull_request_number: t.pull_request_number,
          base_branch: t.base_branch,
          git_commit_sha: t.git_commit_sha,
          ran_at: t.ran_at
        }
      )

    query =
      from(r in subquery(runs),
        join: c in subquery(Commits.commits_query(project_id)),
        on: c.git_commit_sha == r.git_commit_sha,
        group_by: r.name,
        select: %{
          name: r.name,
          git_branch: fragment("argMax(?, ?)", r.git_branch, r.ran_at),
          pull_request_number: fragment("argMaxIf(?, ?, ?)", r.pull_request_number, r.ran_at, r.is_pull_request),
          base_branch: fragment("argMaxIf(?, ?, ?)", r.base_branch, r.ran_at, r.is_pull_request),
          git_commit_sha: fragment("argMax(?, ?)", r.git_commit_sha, r.ran_at),
          ran_at: max(r.ran_at),
          covered_lines: fragment("argMax(?, ?)", c.covered_lines, r.ran_at),
          executable_lines: fragment("argMax(?, ?)", c.executable_lines, r.ran_at),
          measured_files_count: fragment("argMax(?, ?)", c.measured_files_count, r.ran_at),
          unmeasured_files_count: fragment("argMax(?, ?)", c.unmeasured_files_count, r.ran_at),
          schemes: fragment("argMax(?, ?)", c.schemes, r.ran_at),
          partial_schemes: fragment("argMax(?, ?)", c.partial_schemes, r.ran_at),
          complete: fragment("argMax(?, ?)", c.complete, r.ran_at),
          completeness: fragment("argMax(?, ?)", c.completeness, r.ran_at)
        },
        order_by: [desc: max(r.ran_at)]
      )

    # A branch is searched by its name and by the number of the pull request
    # it was pushed for: the reader remembers one or the other.
    case search do
      blank when blank in [nil, ""] ->
        query

      search ->
        from(r in query,
          where:
            fragment("positionCaseInsensitive(?, ?) > 0", r.name, ^search) or
              fragment("positionCaseInsensitive(concat('#', toString(?)), ?) > 0", r.pull_request_number, ^search)
        )
    end
  end

  @doc """
  The branch's newest measured commit, chained or not: the commit a branch
  page describes. Nil when nothing on the branch was measured.
  """
  def head_commit(%Project{} = project, branch, opts \\ []) do
    project
    |> branch_history(branch, Keyword.put_new(opts, :limit, 200))
    |> Map.fetch!(:commits)
    |> Enum.find(& &1.measured)
  end

  @doc """
  A measured commit against the default branch's newest chained commit:
  `%{branch, commit, coverage, delta}`, or nil when the commit is that
  branch's own, when nothing on it is chained, or when the two measured
  different sets — anything else only compares per scheme.
  """
  def against_default(%Project{} = project, commit, opts \\ []) do
    default = latest(project, project.default_branch, opts)

    if default && default.git_commit_sha != commit.git_commit_sha && comparable?(commit, default) do
      %{
        branch: project.default_branch,
        commit: default.git_commit_sha,
        coverage: default.coverage,
        delta: Float.round(commit.coverage - default.coverage, 1)
      }
    end
  end

  defp comparable?(a, b), do: same_measured_set?(a, b)

  @doc "The newest chained commit of the branch, with its totals, or nil."
  def latest(%Project{} = project, branch, opts \\ []) do
    project
    |> branch_history(branch, Keyword.put_new(opts, :limit, 200))
    |> Map.fetch!(:commits)
    |> Enum.find(& &1.chained)
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

  # A commit whose runs skipped tests, all of them carried forward
  # (`Tuist.Tests.Coverage.Reported`), stands in the trend with its reported
  # coverage, what a full run would have measured, and compares as a fully
  # measured commit does; `measured_coverage` keeps what its runs observed.
  defp with_coverage(%{reported_kind: "reported"} = row) do
    Map.merge(row, %{
      coverage: Coverage.percentage(row.reported_covered_lines, row.reported_executable_lines),
      measured_coverage: Coverage.percentage(row.covered_lines, row.executable_lines)
    })
  end

  defp with_coverage(row), do: Map.put(row, :coverage, Coverage.percentage(row.covered_lines, row.executable_lines))

  defp effective_partial_schemes(%{reported_kind: "reported"}), do: []
  defp effective_partial_schemes(row), do: row.partial_schemes
end
