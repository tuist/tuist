defmodule Tuist.Tests.Coverage.History do
  @moduledoc """
  Coverage over the project's history: a branch or a pull request commit by
  commit, and every branch's head. Wherever a branch is taken, a pull request
  is too, as `{:pull_request, number}`: its ref is `pull/<number>`, and, when
  that owns nothing, its commits are the ones whose runs named it.

  Branch membership comes from the repository's commit graph
  (`Tuist.GitHistory`), not from the branch a run was labelled with: a
  branch's commits are the ones its ref owns on the first-parent tree
  (`Tuist.GitHistory.Ref`), newest position first, so a commit measured on a
  pull request is on `main` once the branch is fast-forwarded, and a merged
  branch's commits stay with the pull request. Each commit's coverage
  (`Tuist.Tests.CoverageCommit`) keeps a copy of its ref and position, so a
  branch's trend is a range over them for as long as coverage is kept. A
  branch whose ref owns nothing (a run that sent a commit but no history, or
  a branch the default one already contains) falls back to the measured
  commits labelled with it, in time order, and says so (`ordered_by: :time`).
  A pull request's job on a merge checkout (`refs/pull/N/merge`) measures a
  merge commit the graph keeps on `pull/<number>`, never on the branch; on
  the branch's page (its commits, head commit and trend) each such merge
  commit stands at the commit it merged (its second parent) when no run
  measured that commit.

  A commit **chains** into the trend when it is complete (the client
  signalled its pipeline finished) and so is its figure
  (`Tuist.Tests.Coverage.Commits.incomplete?/1`): its change is from the
  commit chained before it. Other commits stay in the history with their
  measured set and out of the chart, the headline figure and the changes.
  """

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.GitHistory.CommitParent
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Deltas
  alias Tuist.Tests.CoverageCommit

  @doc """
  The repository the project's measured commits belong to (the most
  recently run commit's that named one), or nil when none did. Read newest
  first along `(project_id, ran_at)`, so it stops at the first such commit.
  """
  def repository_id(project_id) do
    Repo.one(
      from(c in CoverageCommit,
        where: c.project_id == ^project_id and not is_nil(c.repository_id),
        order_by: [desc: c.ran_at],
        limit: 1,
        select: c.repository_id
      )
    )
  end

  # The branch's ref, when it owns commits. A pull request's
  # (`{:pull_request, number}`) is `pull/<number>`.
  defp branch_ref(project, branch) do
    with repository_id when not is_nil(repository_id) <- repository_id(project.id),
         %{} = ref <- GitHistory.ref(repository_id, ref_name(branch)),
         [_ | _] <- GitHistory.ref_commits(ref.id, limit: 1) do
      ref
    else
      _ -> nil
    end
  end

  defp ref_name({:pull_request, number}), do: GitHistory.pull_request_ref(number)
  defp ref_name(branch), do: branch

  # The commits labelled with the branch, or, for a pull request, whose runs
  # named it.
  defp labelled(query, {:pull_request, number}), do: where(query, [c], c.pull_request_number == ^number)
  defp labelled(query, branch), do: where(query, [c], c.git_branch == ^branch)

  @max_trend_points 40

  @doc """
  The branch's coverage over the period, drawn from its complete commits
  only (the ones whose pipeline signalled it finished, with a complete
  figure: `Tuist.Tests.Coverage.Commits.complete_figures/1`), oldest first and at
  most #{@max_trend_points} points: one per commit when they fit, otherwise
  the latest complete commit of each day, week or month, the finest of them
  that fits, and by month only the most recent #{@max_trend_points}. Each
  point carries the commit's totals and, when
  grouped, the `period` it stands for: the start of its day, week or month
  in UTC. Returns `%{grouping: :commit | :day | :week | :month, points:}`.

  The branch's commits are its ref's, by when they were made, each with its
  own figure or, when no run measured it, its newest merge checkout's (the
  commits and figures its commit list shows), or, when its ref owns none,
  the ones its runs were labelled with, by when they ran. Two reads over
  that range: one counting the commits and the days, weeks and months they
  fall on, to pick the grouping, and one returning the points.
  """
  def trend_points(%Project{} = project, branch, opts \\ []) do
    {query, at} = trend_query(project, branch, opts)

    counts =
      Repo.one(
        from(c in query,
          select: %{
            commits: count(),
            day: count(fragment("date_trunc('day', ?, 'UTC')", field(c, ^at)), :distinct),
            week: count(fragment("date_trunc('week', ?, 'UTC')", field(c, ^at)), :distinct)
          }
        )
      )

    grouping =
      cond do
        counts.commits <= @max_trend_points -> :commit
        counts.day <= @max_trend_points -> :day
        counts.week <= @max_trend_points -> :week
        true -> :month
      end

    points =
      query
      |> trend_rows(at, grouping)
      |> Repo.all()
      |> Enum.take(-@max_trend_points)
      |> Enum.map(&with_coverage/1)

    %{grouping: grouping, points: points}
  end

  @doc """
  The SHA of the branch's latest complete commit, the newest point its trend
  over all time ends at (`trend_points/3`), or nil. The newest of each of the
  trend's reads (`trend_queries/3`), each newest first and limited to one
  row, which the indexes on `(project_id, ref_id, committed_at)`,
  `(project_id, git_branch, ran_at)` and its pull request rows' serve.
  """
  def latest_complete_commit(%Project{} = project, branch) do
    {queries, at} = trend_queries(project, branch, [])

    queries
    |> Enum.flat_map(fn query ->
      query
      |> order_by(^chronological(at, :desc))
      |> limit(1)
      |> select([c], %{git_commit_sha: c.git_commit_sha, at: field(c, ^at), position: c.position})
      |> Repo.all()
    end)
    |> Enum.max_by(&{DateTime.to_unix(&1.at, :microsecond), &1.position, &1.git_commit_sha}, fn -> nil end)
    |> then(&(&1 && &1.git_commit_sha))
  end

  # The trend's commits as one query: the union of `trend_queries/3`.
  defp trend_query(project, branch, opts) do
    case trend_queries(project, branch, opts) do
      {[query], at} -> {query, at}
      {[own, stand_ins], at} -> {from(c in subquery(union_all(trend_fields(own), ^trend_fields(stand_ins)))), at}
    end
  end

  # The reads a branch's trend is drawn from. A branch whose ref owns
  # commits: the ref's commits that chain, and the merge checkouts standing
  # at the ref's commits no run measured (`stand_ins/3`). Otherwise the
  # commits labelled with it.
  defp trend_queries(project, branch, opts) do
    base = where(CoverageCommit, [c], c.project_id == ^project.id and c.complete)

    case branch_ref(project, branch) do
      nil ->
        {[base |> labelled(branch) |> ran_in(opts) |> chains()], :ran_at}

      ref ->
        own = base |> where([c], c.ref_id == ^ref.id) |> in_period(opts) |> chains()

        # A branch no pull request run named, the default one among them,
        # reads its ref's commits alone.
        if Repo.exists?(labelled_merges(project, ref, opts)),
          do: {[own, stand_ins(project, ref, opts)], :committed_at},
          else: {[own], :committed_at}
    end
  end

  defp chains(query), do: query |> Commits.comparable() |> Commits.complete_figures()

  # The merge checkouts that chain, each at the ref's commit it stands at:
  # the commit's newest listed merge checkout when no run measured the
  # commit, as the branch's commit list shows it (`measured_on_ref/3`), with
  # the commit's place. Read from the merge checkouts labelled with the
  # branch (index-only, on its pull request rows), then, for each, one probe
  # of its second parent, of that parent on the ref, of the parent's own
  # figure and of the merge checkout's, each on a unique key: a read the
  # size of the branch's merge checkouts, none on a branch that has none,
  # whatever the planner estimates. A merge checkout runs after the commit
  # it merged, so the period's start bounds them too.
  defp stand_ins(project, ref, opts) do
    second_parent =
      from(p in CommitParent,
        where:
          p.repository_id == ^ref.repository_id and p.child_sha == parent_as(:merge_checkout).git_commit_sha and
            p.position == 1,
        limit: 1,
        select: %{sha: p.parent_sha}
      )

    on_ref =
      from(b in GitHistory.Commit,
        where: b.repository_id == ^ref.repository_id and b.sha == parent_as(:second_parent).sha and b.ref_id == ^ref.id,
        limit: 1,
        select: %{sha: b.sha, committed_at: b.committed_at, position: b.position}
      )

    figures =
      from(m in CoverageCommit,
        where: m.project_id == ^project.id and m.git_commit_sha == parent_as(:merge_checkout).git_commit_sha,
        limit: 1
      )
      |> Commits.listed()
      |> trend_fields()

    own =
      Commits.listed(
        from(o in CoverageCommit,
          where: o.project_id == ^project.id and o.git_commit_sha == parent_as(:branch_commit).sha,
          limit: 1,
          select: %{git_commit_sha: o.git_commit_sha}
        )
      )

    newest =
      from(l in subquery(labelled_merges(project, ref, opts)),
        as: :merge_checkout,
        inner_lateral_join: p in subquery(second_parent),
        as: :second_parent,
        on: true,
        inner_lateral_join: b in subquery(on_ref),
        as: :branch_commit,
        on: true,
        left_lateral_join: o in subquery(own),
        on: true,
        inner_lateral_join: m in subquery(figures),
        on: true,
        where: is_nil(o.git_commit_sha),
        distinct: [asc: b.sha],
        order_by: [desc: l.ran_at, desc: l.git_commit_sha],
        select: m,
        select_merge: %{committed_at: b.committed_at, position: b.position}
      )

    from(s in subquery(newest), where: s.complete) |> in_period(opts) |> chains()
  end

  # The merge checkouts labelled with the branch: its pull request runs'
  # commits, read index-only.
  defp labelled_merges(project, ref, opts) do
    query =
      from(l in CoverageCommit,
        where: l.project_id == ^project.id and l.git_branch == ^ref.name and l.pull_request_number > 0,
        select: %{git_commit_sha: l.git_commit_sha, ran_at: l.ran_at}
      )

    case Keyword.get(opts, :since) do
      nil -> query
      since -> where(query, [l], l.ran_at >= ^utc(since))
    end
  end

  # The fields a trend reads.
  defp trend_fields(query) do
    select(query, [c], %{
      git_commit_sha: c.git_commit_sha,
      committed_at: c.committed_at,
      position: c.position,
      complete: c.complete,
      covered_lines: c.covered_lines,
      executable_lines: c.executable_lines,
      reported_covered_lines: c.reported_covered_lines,
      reported_executable_lines: c.reported_executable_lines,
      reported_kind: c.reported_kind,
      schemes: c.schemes,
      partial_schemes: c.partial_schemes
    })
  end

  # The order a trend's commits follow. A ref's commits can share a commit
  # time, as a rebase merge's do, and then their position orders them: the
  # newest is the one nearest the head. Commits read by when they ran have
  # no common ref to order them by.
  defp chronological(:committed_at, direction),
    do: [{direction, :committed_at}, {direction, :position}, {direction, :git_commit_sha}]

  defp chronological(:ran_at, direction), do: [{direction, :ran_at}, {direction, :git_commit_sha}]

  defp trend_rows(query, at, :commit), do: query |> order_by(^chronological(at, :asc)) |> trend_select(at)

  defp trend_rows(query, at, grouping) do
    query
    |> distinct(^[asc: bucket(at, grouping)])
    |> order_by(^chronological(at, :desc))
    |> trend_select(at)
    |> select_merge(^%{period: bucket(at, grouping)})
  end

  defp bucket(at, :day), do: dynamic([c], fragment("date_trunc('day', ?, 'UTC')", field(c, ^at)))
  defp bucket(at, :week), do: dynamic([c], fragment("date_trunc('week', ?, 'UTC')", field(c, ^at)))
  defp bucket(at, :month), do: dynamic([c], fragment("date_trunc('month', ?, 'UTC')", field(c, ^at)))

  defp trend_select(query, at) do
    select(query, [c], %{
      git_commit_sha: c.git_commit_sha,
      committed_at: field(c, ^at),
      covered_lines: c.covered_lines,
      executable_lines: c.executable_lines,
      reported_covered_lines: c.reported_covered_lines,
      reported_executable_lines: c.reported_executable_lines,
      reported_kind: c.reported_kind,
      schemes: c.schemes,
      partial_schemes: c.partial_schemes,
      complete: c.complete
    })
  end

  @doc """
  A file's coverage over a trend's commits (`trend_points/3`'s points): one
  point per commit that has coverage for the file, oldest first, with the
  commit's own fields (its `period` among them). Each point is the file as
  its page reads it at that commit (`Commits.file_detail/4`): its lines
  merged over the commit's runs and, where coverage was carried into the
  commit, covered too by the skipped tests that covered them, so the trend
  ends on the figure the page shows. Complete commits whose stored deltas
  are current (`Tuist.Tests.Coverage.Deltas.file_figures/3`) are read from
  the file's rows along their chain, the rest from their runs (all of them
  with `stored: false`): commits nothing was carried into in one pass.
  """
  def file_points(project, path, points, opts \\ [])

  def file_points(_project, _path, [], _opts), do: []

  def file_points(%Project{} = project, path, points, opts) do
    summaries = Commits.by_shas(project.id, Enum.map(points, & &1.git_commit_sha))
    stored = if Keyword.get(opts, :stored, true), do: Deltas.file_figures(project.id, path, summaries), else: %{}
    rows_by_sha = Map.drop(summaries, Map.keys(stored))
    {carried, measured} = Enum.split_with(rows_by_sha, fn {_sha, row} -> Commits.carried?(row) end)

    commit_of = for {sha, row} <- measured, id <- row.test_run_ids, into: %{}, do: {id, sha}

    measured_files =
      project.id
      |> Commits.file_rows(Map.keys(commit_of), path)
      |> Enum.group_by(&commit_of[&1.test_run_id])
      |> Map.new(fn {sha, rows} -> {sha, Coverage.detail(path, rows)} end)

    carried_files = Map.new(carried, fn {sha, _row} -> {sha, Commits.file_detail(project.id, sha, path)} end)
    files = measured_files |> Map.merge(carried_files) |> Map.merge(stored)

    Enum.flat_map(points, fn point ->
      case Map.get(files, point.git_commit_sha) do
        nil ->
          []

        file ->
          [
            Map.merge(point, %{
              covered_lines: file.covered_lines,
              executable_lines: file.executable_lines,
              coverage: Coverage.percentage(file.covered_lines, file.executable_lines)
            })
          ]
      end
    end)
  end

  # Positions follow the graph, and the period follows when the commits were
  # made: the range of a ref's coverage the trend draws, however long.
  defp in_period(query, opts) do
    query =
      case Keyword.get(opts, :since) do
        nil -> query
        since -> where(query, [c], c.committed_at >= ^utc(since))
      end

    case Keyword.get(opts, :until) do
      nil -> query
      until -> where(query, [c], c.committed_at <= ^utc(until))
    end
  end

  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(%DateTime{} = at), do: at

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

  @lookback 30
  @head_lookback 200

  @doc """
  One page of the branch's commits, newest first, read at a cursor rather
  than by walking the branch: `after:` the page's `end_cursor` reads the
  older commits, `before:` its `start_cursor` the newer ones. A branch whose
  ref owns commits is paged by position, unmeasured commits included; one
  that falls back to its labelled commits (`ordered_by: :time`) by when they
  ran. Each complete commit's `change` is how far it moved coverage from the
  complete commit before it, settled over the page and the #{@lookback}
  measured commits below it, as the trend compares them
  (`trend_points/3`); other commits have none. A `partial` commit with no
  measured line (its runs' product code all came from the binary cache
  without counters) is listed as incomplete (`Commits.listed/1`), out of the
  trend and the changes. The period bounds the commits (`since`/`until`);
  `page_size` is 20 by default.

  `search` keeps the commits whose SHA starts with it and `status` those of
  one status (`Tuist.Tests.Coverage.Commits.status/1`): `complete` (its
  pipeline signalled it finished and its figure is whole), `incomplete`
  (signalled, its figure a lower bound), `in-progress` (measured, not yet
  signalled) or `not-measured` (on the branch, no run measured it), or
  `measured` for every status but `not-measured`. Each is stored, so they
  narrow the query the page is read with.
  """
  def commit_cursor_page(%Project{} = project, branch, opts \\ []) do
    size = Keyword.get(opts, :page_size, 20)
    cursor = cursor(opts)

    case branch_ref(project, branch) do
      nil -> labelled_cursor_page(project, branch, opts, size, cursor)
      ref -> graph_cursor_page(project, ref, opts, size, cursor)
    end
  end

  # The branch's graph commits narrowed by `search` and `status`: a commit
  # stands with its own published figure a list shows (`Commits.listed/1`),
  # or, as `measured_on_ref/3` settles it, when it has none, with its newest
  # merge checkout's. Both are looked up per commit the page reads (the
  # commit's key, then its child edges), so a page stops at its size.
  defp graph_filter(project_id, ref, opts) do
    {search, status} = commit_filter(opts)

    if search == "" and status == "" do
      nil
    else
      fn query ->
        query = if search == "", do: query, else: where(query, [c], like(c.sha, ^sha_prefix(search)))
        if status == "", do: query, else: query |> stand_in(project_id, ref) |> by_status(status)
      end
    end
  end

  defp stand_in(query, project_id, ref) do
    own =
      Commits.listed(
        from(o in CoverageCommit,
          where: o.project_id == ^project_id and o.git_commit_sha == parent_as(:ref_commit).sha,
          select: %{complete: o.complete, reported_kind: o.reported_kind}
        )
      )

    merge =
      Commits.listed(
        from(m in CoverageCommit,
          join: p in CommitParent,
          on: p.repository_id == ^ref.repository_id and p.child_sha == m.git_commit_sha and p.position == 1,
          where: is_nil(parent_as(:own).reported_kind) and p.parent_sha == parent_as(:ref_commit).sha,
          where: m.project_id == ^project_id and m.git_branch == ^ref.name and m.pull_request_number > 0,
          order_by: [desc: m.ran_at],
          limit: 1,
          select: %{complete: m.complete, reported_kind: m.reported_kind}
        )
      )

    from(c in query,
      left_lateral_join: o in subquery(own),
      as: :own,
      on: true,
      left_lateral_join: m in subquery(merge),
      as: :merge,
      on: true
    )
  end

  defp by_status(query, "measured"),
    do: where(query, [own: o, merge: m], not is_nil(o.reported_kind) or not is_nil(m.reported_kind))

  defp by_status(query, "not-measured"),
    do: where(query, [own: o, merge: m], is_nil(o.reported_kind) and is_nil(m.reported_kind))

  defp by_status(query, "complete"),
    do:
      where(
        query,
        [own: o, merge: m],
        coalesce(o.complete, m.complete) and coalesce(o.reported_kind, m.reported_kind) != "partial"
      )

  defp by_status(query, "incomplete"),
    do:
      where(
        query,
        [own: o, merge: m],
        coalesce(o.complete, m.complete) and coalesce(o.reported_kind, m.reported_kind) == "partial"
      )

  defp by_status(query, "in-progress"), do: where(query, [own: o, merge: m], not coalesce(o.complete, m.complete))

  defp by_status(query, _unknown), do: where(query, false)

  # A labelled branch lists measured commits only, so "not measured" matches
  # none of them.
  defp labelled_filter(query, opts) do
    {search, status} = commit_filter(opts)
    query = if search == "", do: query, else: where(query, [c], like(c.git_commit_sha, ^sha_prefix(search)))

    case status do
      status when status in ["", "measured"] -> query
      "complete" -> where(query, [c], c.complete and c.reported_kind != "partial")
      "incomplete" -> where(query, [c], c.complete and c.reported_kind == "partial")
      "in-progress" -> where(query, [c], not c.complete)
      _other -> where(query, false)
    end
  end

  defp commit_filter(opts) do
    search = opts |> Keyword.get(:search) |> Kernel.||("") |> String.trim() |> String.downcase()
    {search, Keyword.get(opts, :status) || ""}
  end

  defp sha_prefix(search), do: String.replace(search, ~w(\\ % _), &("\\" <> &1)) <> "%"

  defp cursor(opts) do
    case {Keyword.get(opts, :after), Keyword.get(opts, :before)} do
      {value, _} when value not in [nil, ""] -> {:older, value}
      {_, value} when value not in [nil, ""] -> {:newer, value}
      _ -> nil
    end
  end

  defp graph_cursor_page(project, ref, opts, size, cursor) do
    period = [
      since: second(Keyword.get(opts, :since)),
      until: second(Keyword.get(opts, :until)),
      refine: graph_filter(project.id, ref, opts)
    ]

    cursor = cursor_position(cursor)

    {rows, more?} =
      read_page(cursor, size, fn
        {:older, position}, limit ->
          GitHistory.ref_commits(ref.id, period ++ [below: position, limit: limit])

        {:newer, position}, limit ->
          GitHistory.ref_commits(ref.id, period ++ [above: position, limit: limit, order: :asc])

        nil, limit ->
          GitHistory.ref_commits(ref.id, period ++ [limit: limit])
      end)

    head_position = ref.id |> GitHistory.ref_commits(limit: 1) |> Enum.map(&elem(&1, 1)) |> List.first(0)

    commits =
      Enum.map(rows, fn {sha, position, committed_at} ->
        %{git_commit_sha: sha, depth: head_position - position, committed_at: committed_at, position: position}
      end)

    {newest, oldest} = bounds(commits, & &1.position)
    lookback = graph_lookback(project, ref, oldest)
    measured = measured_on_ref(project, ref, Enum.map(commits, & &1.git_commit_sha))

    %{
      commits: settle(commits, measured, lookback),
      ordered_by: :graph,
      has_next_page?:
        older_page?(cursor, more?, fn ->
          not is_nil(oldest) and GitHistory.ref_commits?(ref.id, period ++ [below: oldest])
        end),
      has_previous_page?:
        newer_page?(cursor, more?, fn ->
          not is_nil(newest) and GitHistory.ref_commits?(ref.id, period ++ [above: newest])
        end),
      start_cursor: newest && "p#{newest}",
      end_cursor: oldest && "p#{oldest}"
    }
  end

  # Newest first whichever way the page was read; `read` gets the cursor and
  # one row more than the page, to tell whether there is more.
  defp read_page(cursor, size, read) do
    {rows, more?} = cursor |> read.(size + 1) |> split(size)

    case cursor do
      {:newer, _value} -> {Enum.reverse(rows), more?}
      _ -> {rows, more?}
    end
  end

  defp graph_lookback(_project, _ref, nil), do: []

  defp graph_lookback(project, ref, oldest) do
    lookback =
      Commits.all(project.id, fn query ->
        query
        |> where([c], c.ref_id == ^ref.id and c.position < ^oldest)
        |> order_by([c], desc: c.position)
        |> limit(@lookback)
      end)

    lookback ++ fork_lookback(project, ref, length(lookback))
  end

  # A branch forked from another: the lookback runs on into the commits it
  # left, so its oldest commits compare with them.
  defp fork_lookback(project, %{parent_ref_id: parent_ref_id, fork_position: fork}, found)
       when not is_nil(parent_ref_id) and found < @lookback do
    Commits.all(project.id, fn query ->
      query
      |> where([c], c.ref_id == ^parent_ref_id and c.position <= ^fork)
      |> order_by([c], desc: c.position)
      |> limit(^(@lookback - found))
    end)
  end

  defp fork_lookback(_project, _ref, _found), do: []

  defp labelled_cursor_page(project, branch, opts, size, cursor) do
    labelled = fn query -> query |> labelled(branch) |> ran_in(opts) |> labelled_filter(opts) end
    cursor = cursor_time(cursor)
    read = fn refine -> Commits.all(project.id, &(&1 |> labelled.() |> refine.()), listed: true) end

    {rows, more?} =
      read_page(cursor, size, fn
        {:older, key}, limit -> read.(&(&1 |> older_than(key) |> newest_first() |> limit(^limit)))
        {:newer, key}, limit -> read.(&(&1 |> newer_than(key) |> oldest_first() |> limit(^limit)))
        nil, limit -> read.(&(&1 |> newest_first() |> limit(^limit)))
      end)

    {newest, oldest} = bounds(rows, &{&1.ran_at, &1.git_commit_sha})
    newer? = fn key -> not is_nil(key) and read.(&(&1 |> newer_than(key) |> limit(1))) != [] end
    lookback = if oldest, do: read.(&(&1 |> older_than(oldest) |> newest_first() |> limit(@lookback))), else: []

    commits =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, depth} -> %{git_commit_sha: row.git_commit_sha, depth: depth, committed_at: row.ran_at} end)

    %{
      commits: settle(commits, Map.new(rows, &{&1.git_commit_sha, &1}), lookback),
      ordered_by: :time,
      has_next_page?: older_page?(cursor, more?, fn -> lookback != [] end),
      has_previous_page?: newer_page?(cursor, more?, fn -> newer?.(newest) end),
      start_cursor: newest && time_cursor(newest),
      end_cursor: oldest && time_cursor(oldest)
    }
  end

  # The `ran_at` bound repeats what the `or` says so PostgreSQL can seek the
  # `ran_at` indexes to the cursor; with the `or` alone it walks and filters
  # every row on the near side, so a page got slower the deeper it was.
  defp older_than(query, {at, sha}),
    do: where(query, [c], c.ran_at <= ^at and (c.ran_at < ^at or (c.ran_at == ^at and c.git_commit_sha < ^sha)))

  defp newer_than(query, {at, sha}),
    do: where(query, [c], c.ran_at >= ^at and (c.ran_at > ^at or (c.ran_at == ^at and c.git_commit_sha > ^sha)))

  defp oldest_first(query), do: order_by(query, [c], asc: c.ran_at, asc: c.git_commit_sha)

  defp newest_first(query), do: order_by(query, [c], desc: c.ran_at, desc: c.git_commit_sha)

  # The page's commits with their measurements, chained and changed over the
  # page and the measured commits below it, which are dropped after.
  defp settle(commits, measured, lookback) do
    measured = Map.new(measured, fn {sha, row} -> {sha, with_coverage(row)} end)

    page =
      Enum.map(commits, fn commit ->
        case Map.get(measured, commit.git_commit_sha) do
          nil -> Map.merge(commit, %{measured: false, chained: false})
          row -> commit |> Map.merge(Map.delete(row, :committed_at)) |> Map.put(:measured, true)
        end
      end)

    below = Enum.map(lookback, &(&1 |> with_coverage() |> Map.put(:measured, true)))

    (page ++ below)
    |> Enum.map(&Map.put(&1, :chained, &1.measured and Map.get(&1, :complete, false) and not Commits.incomplete?(&1)))
    |> with_changes()
    |> Enum.take(length(page))
  end

  defp split(rows, size), do: {Enum.take(rows, size), length(rows) > size}

  defp bounds([], _key), do: {nil, nil}
  defp bounds(rows, key), do: {key.(List.first(rows)), key.(List.last(rows))}

  # Reading older: more below when the page overflowed. Reading newer: more
  # above when it overflowed, and below whatever the page came from. The
  # other side is asked only when the direction does not answer it.
  defp older_page?({:newer, _}, _more?, below?), do: below?.()
  defp older_page?(_cursor, more?, _below?), do: more?

  defp newer_page?({:newer, _}, more?, _above?), do: more?
  defp newer_page?({:older, _}, _more?, above?), do: above?.()
  defp newer_page?(nil, _more?, _above?), do: false

  defp cursor_position({direction, "p" <> position}) do
    case Integer.parse(position) do
      {position, ""} -> {direction, position}
      _ -> nil
    end
  end

  defp cursor_position(_cursor), do: nil

  defp cursor_time({direction, "t" <> value}) do
    with [micros, sha] <- String.split(value, "-", parts: 2),
         {micros, ""} <- Integer.parse(micros),
         {:ok, at} <- DateTime.from_unix(micros, :microsecond) do
      {direction, {at, sha}}
    else
      _ -> nil
    end
  end

  defp cursor_time(_cursor), do: nil

  defp time_cursor({at, sha}), do: "t#{DateTime.to_unix(at, :microsecond)}-#{sha}"

  defp second(nil), do: nil
  defp second(at), do: at |> utc() |> DateTime.truncate(:second)

  defp ran_in(query, opts) do
    query =
      case Keyword.get(opts, :since) do
        nil -> query
        since -> where(query, [c], c.ran_at >= ^utc(since))
      end

    case Keyword.get(opts, :until) do
      nil -> query
      until -> where(query, [c], c.ran_at <= ^utc(until))
    end
  end

  @doc """
  The schemes that measured the branch's commits in the period, by the runs
  that named the branch: the schemes its Test Runs tab filters by.
  """
  def branch_schemes(%Project{} = project, branch, opts \\ []) do
    CoverageCommit
    |> where([c], c.project_id == ^project.id)
    |> labelled(branch)
    |> ran_in(opts)
    |> select([c], fragment("unnest(? || ?)", c.schemes, c.partial_schemes))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc """
  The branches whose runs never named a pull request, the most recently
  measured first, at most `limit` of them (100 by default): the branches the
  Code Coverage page picks its analytics from, those with a commit a list
  shows (`Commits.listed/1`). The default branch leads, whether or not it is
  among them.
  """
  def branches(%Project{} = project, opts \\ []) do
    measured =
      CoverageCommit
      |> where([c], c.project_id == ^project.id and c.git_branch != "")
      |> Commits.listed()
      |> group_by([c], c.git_branch)
      |> having([c], max(c.pull_request_number) == 0)
      |> order_by([c], desc: max(c.ran_at), asc: c.git_branch)
      |> limit(^Keyword.get(opts, :limit, 100))
      |> select([c], c.git_branch)
      |> Repo.all()

    [project.default_branch | List.delete(measured, project.default_branch)]
  end

  @doc """
  The project's listed commits (`Commits.listed/1`) on every branch and pull
  request, complete or not, the most recently run first, a page at a time
  from a cursor (`after`/`before`, as `commit_cursor_page/3` takes them):
  where each run's coverage went, whichever branch it named. Read along
  `(project_id, ran_at)`.
  """
  def recent_commits_page(%Project{} = project, opts \\ []) do
    size = Keyword.get(opts, :page_size, 20)
    cursor = opts |> cursor() |> cursor_time()
    read = fn refine -> Commits.all(project.id, refine, listed: true) end

    {rows, more?} =
      read_page(cursor, size, fn
        {:older, key}, limit -> read.(&(&1 |> older_than(key) |> newest_first() |> limit(^limit)))
        {:newer, key}, limit -> read.(&(&1 |> newer_than(key) |> oldest_first() |> limit(^limit)))
        nil, limit -> read.(&(&1 |> newest_first() |> limit(^limit)))
      end)

    {newest, oldest} = bounds(rows, &{&1.ran_at, &1.git_commit_sha})
    beyond? = fn key, side -> not is_nil(key) and read.(&(&1 |> side.(key) |> limit(1))) != [] end

    %{
      commits: Enum.map(rows, &with_coverage/1),
      has_next_page?: older_page?(cursor, more?, fn -> beyond?.(oldest, &older_than/2) end),
      has_previous_page?: newer_page?(cursor, more?, fn -> beyond?.(newest, &newer_than/2) end),
      start_cursor: newest && time_cursor(newest),
      end_cursor: oldest && time_cursor(oldest)
    }
  end

  @doc """
  The branch's newest listed commit (`Commits.listed/1`), complete or not:
  the commit a branch page describes. Among the newest #{@head_lookback}
  commits its ref owns or, when it owns none, the commits its runs were
  labelled with. Nil when nothing on the branch was measured, so the page
  says so rather than describing nothing.
  """
  def head_commit(%Project{} = project, branch) do
    row =
      case branch_ref(project, branch) do
        nil ->
          project.id
          |> Commits.all(
            fn query ->
              query |> labelled(branch) |> order_by([c], desc: c.ran_at) |> limit(1)
            end,
            listed: true
          )
          |> List.first()

        ref ->
          shas = ref.id |> GitHistory.ref_commits(limit: @head_lookback) |> Enum.map(&elem(&1, 0))
          measured = measured_on_ref(project, ref, shas)
          Enum.find_value(shas, &Map.get(measured, &1))
      end

    row && with_coverage(row)
  end

  # The listed commits among the ref's `shas`, keyed by the SHA they stand
  # at. A commit no run measured stands with its newest merge checkout: the
  # merge commit a pull request's job checked out (`refs/pull/N/merge`, the
  # base branch's tip first and the commit second) and measured, labelled
  # with the branch. The graph keeps that merge commit on `pull/<number>`,
  # never on the branch, and a job of each push makes a new one, so this is
  # how a branch whose pull request jobs ran merge checkouts shows what each
  # push measured. One read of the parent edges by `(repository_id,
  # parent_sha)` and one of the merge commits' figures.
  defp measured_on_ref(project, ref, shas) do
    measured = Commits.by_shas(project.id, shas, listed: true)

    case Enum.reject(shas, &Map.has_key?(measured, &1)) do
      [] ->
        measured

      unmeasured ->
        merges =
          Repo.all(
            from(p in CommitParent,
              where: p.repository_id == ^ref.repository_id and p.parent_sha in ^unmeasured and p.position == 1,
              select: {p.child_sha, p.parent_sha}
            )
          )

        project.id
        |> Commits.by_shas(Enum.map(merges, &elem(&1, 0)), listed: true)
        |> Map.values()
        |> Enum.filter(&(&1.git_branch == ref.name and &1.pull_request_number > 0))
        |> Enum.sort_by(& &1.ran_at, DateTime)
        |> Enum.reduce(measured, fn row, acc ->
          merges |> Enum.filter(&(elem(&1, 0) == row.git_commit_sha)) |> Enum.reduce(acc, &Map.put(&2, elem(&1, 1), row))
        end)
    end
  end

  @doc """
  The commit's row with the figure it stands with. A commit whose runs
  skipped tests stands with its reported coverage and lines
  (`Tuist.Tests.Coverage.Reported`): what a full run would have measured
  when every skipped test was carried forward, in which case it compares as
  a fully measured commit does, and otherwise the part of it that is
  confirmed, the lines known to be covered among those that could be
  counted.
  """
  def with_coverage(%{reported_kind: kind} = row) when kind in ~w(reported partial) do
    Map.merge(row, %{
      coverage: Coverage.percentage(row.reported_covered_lines, row.reported_executable_lines),
      covered_lines: row.reported_covered_lines,
      executable_lines: row.reported_executable_lines
    })
  end

  def with_coverage(row), do: Map.put(row, :coverage, Coverage.percentage(row.covered_lines, row.executable_lines))
end
