defmodule Tuist.Tests.Coverage.History do
  @moduledoc """
  Coverage over the project's history: a branch commit by commit, every
  branch's head, and a pull request's commits.

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

  A commit **chains** into the trend when it is complete (the client
  signalled its pipeline finished) or, failing a signal, when it measured
  the same schemes, each as fully, as the previous chained commit: two
  commits measured alike compare as a whole; anything else only compares
  per scheme. The first measured commit chains on its own. Unchained commits
  stay in the history with their measured set and out of the chart.
  """

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
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

  # The branch's ref, when it owns commits.
  defp branch_ref(project, branch) do
    with repository_id when not is_nil(repository_id) <- repository_id(project.id),
         %{} = ref <- GitHistory.ref(repository_id, branch),
         [_ | _] <- GitHistory.ref_commits(ref.id, limit: 1) do
      ref
    else
      _ -> nil
    end
  end

  @doc """
  The commits of a branch, newest first, each with its measurement when
  there is one: `%{git_commit_sha, depth, committed_at, measured, chained,
  coverage, ...}` (the `Tuist.Tests.Coverage.Commits.summary/2` fields when
  measured). `ordered_by` in the result says whether the order is the
  graph's (`:graph`: the commits the branch's ref owns, by position) or,
  when the ref owns none, the runs' time (`:time`). A branch other than the
  project's default one holds only the commits it added; the default
  branch's own history is read by selecting it. A branch the default one
  already contains (fast-forwarded, or merged and left in place) owns
  nothing, so it holds the commits its runs were labelled with.

  `since` and `until` bound the measurements considered (`NaiveDateTime`);
  `limit` caps the commits read (the newest), 200 by default. Each commit
  carries the `change` from the commit chained before it, settled over what
  was read and, for a branch, the commits it forked from.
  """
  def branch_history(%Project{} = project, branch, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    ref = branch_ref(project, branch)
    graph = if ref, do: GitHistory.ref_commits(ref.id, limit: limit), else: []

    {commits, ordered_by} =
      case graph do
        [] ->
          {labelled_commits(project.id, branch, opts, limit), :time}

        [{_sha, head_position, _at} | _] = rows ->
          {Enum.map(rows ++ below_fork(ref, limit), fn {sha, position, committed_at} ->
             %{git_commit_sha: sha, depth: head_position - position, committed_at: committed_at}
           end), :graph}
      end

    measured =
      project.id
      |> Commits.by_shas(Enum.map(commits, & &1.git_commit_sha))
      |> Map.filter(fn {_sha, row} -> ran_in_period?(row, opts) end)
      |> Map.new(fn {sha, row} -> {sha, with_coverage(row)} end)

    commits =
      commits
      |> Enum.map(fn commit ->
        case Map.get(measured, commit.git_commit_sha) do
          nil -> Map.merge(commit, %{measured: false, chained: false})
          row -> commit |> Map.merge(Map.delete(row, :committed_at)) |> Map.put(:measured, true)
        end
      end)
      |> chain()
      |> with_changes()
      |> Enum.take(if(graph == [], do: limit, else: length(graph)))

    %{commits: commits, ordered_by: ordered_by}
  end

  # A branch's oldest commits chain and change against the commits it forked
  # from, which belong to the parent's history and are dropped after.
  defp below_fork(%{parent_ref_id: parent_ref_id, fork_position: fork}, limit) when not is_nil(parent_ref_id),
    do: GitHistory.ref_commits(parent_ref_id, at_or_below: fork, limit: limit)

  defp below_fork(_ref, _limit), do: []

  defp ran_in_period?(row, opts) do
    ran_at = naive(row.ran_at)
    since = opts |> Keyword.get(:since) |> naive()
    until = opts |> Keyword.get(:until) |> naive()

    (is_nil(since) or NaiveDateTime.compare(ran_at, since) != :lt) and
      (is_nil(until) or NaiveDateTime.compare(ran_at, until) != :gt)
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

  defp same_measured_set?(a, b) do
    (a.schemes == b.schemes or Commits.fully_carried?(a) or Commits.fully_carried?(b)) and
      effective_partial_schemes(a) == effective_partial_schemes(b)
  end

  @max_trend_points 40

  @doc """
  The branch's coverage over the period, drawn from its complete commits
  only (the ones whose pipeline signalled it finished), oldest first and at
  most #{@max_trend_points} points: one per commit when they fit, otherwise
  the latest complete commit of each day, week or month, the finest of them
  that fits, and by month only the most recent #{@max_trend_points}. Each
  point carries the commit's totals and, when
  grouped, the `period` it stands for: the start of its day, week or month
  in UTC. Returns `%{grouping: :commit | :day | :week | :month, points:}`.

  The branch's commits are its ref's, by when they were made, or, when its
  ref owns none, the ones its runs were labelled with, by when they ran. Two
  reads over that range: one counting the commits and the days, weeks and
  months they fall on, to pick the grouping, and one returning the points.
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
      |> Enum.map(&(&1 |> with_coverage() |> Map.merge(%{measured: true, chained: true})))

    %{grouping: grouping, points: points}
  end

  defp trend_query(project, branch, opts) do
    base = where(CoverageCommit, [c], c.project_id == ^project.id and c.complete)

    {query, at} =
      case branch_ref(project, branch) do
        nil -> {base |> where([c], c.git_branch == ^branch) |> ran_in(opts), :ran_at}
        ref -> {base |> where([c], c.ref_id == ^ref.id) |> in_period(opts), :committed_at}
      end

    {Commits.comparable(query), at}
  end

  defp trend_rows(query, at, :commit),
    do: query |> order_by([c], asc: field(c, ^at), asc: c.git_commit_sha) |> trend_select(at)

  defp trend_rows(query, at, grouping) do
    query
    |> distinct(^[asc: bucket(at, grouping)])
    |> order_by([c], desc: field(c, ^at), desc: c.git_commit_sha)
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
  ends on the figure the page shows. Commits nothing was carried into are
  read in one pass over their runs.
  """
  def file_points(_project, _path, []), do: []

  def file_points(%Project{} = project, path, points) do
    rows_by_sha = Commits.by_shas(project.id, Enum.map(points, & &1.git_commit_sha))
    {carried, measured} = Enum.split_with(rows_by_sha, fn {_sha, row} -> Commits.carried?(row) end)

    commit_of = for {sha, row} <- measured, id <- row.test_run_ids, into: %{}, do: {id, sha}

    measured_files =
      project.id
      |> Commits.file_rows(Map.keys(commit_of), path)
      |> Enum.group_by(&commit_of[&1.test_run_id])
      |> Map.new(fn {sha, rows} -> {sha, Coverage.detail(path, rows)} end)

    carried_files = Map.new(carried, fn {sha, _row} -> {sha, Commits.file_detail(project.id, sha, path)} end)
    files = Map.merge(measured_files, carried_files)

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

  @doc """
  One page of the branch's commits, newest first, read at a cursor rather
  than by walking the branch: `after:` the page's `end_cursor` reads the
  older commits, `before:` its `start_cursor` the newer ones. A branch whose
  ref owns commits is paged by position, unmeasured commits included; one
  that falls back to its labelled commits (`ordered_by: :time`) by when they
  ran. Each complete commit's `change` is how far it moved coverage from the
  complete commit before it, settled over the page and the #{@lookback}
  measured commits below it, as the trend compares them
  (`trend_points/3`); other commits have none. The period bounds the commits
  (`since`/`until`); `page_size` is 20 by default.

  `search` keeps the commits whose SHA starts with it and `status` those of
  one status: `complete` (its pipeline signalled it finished), `in-progress`
  (measured, not yet signalled) or `not-measured` (on the branch, no run
  measured it). Each is stored, so they narrow the query the page is read
  with.
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
  # is measured when it has a published, comparable figure (`Commits.all/2`).
  defp graph_filter(project_id, opts) do
    {search, status} = commit_filter(opts)

    if search == "" and status == "" do
      nil
    else
      measured =
        from(m in CoverageCommit, where: m.project_id == ^project_id)
        |> Commits.comparable()
        |> select([m], %{sha: m.git_commit_sha, complete: m.complete})

      fn query ->
        query = if search == "", do: query, else: where(query, [c], like(c.sha, ^sha_prefix(search)))
        by_status(query, status, measured)
      end
    end
  end

  defp by_status(query, "", _measured), do: query

  defp by_status(query, "not-measured", measured),
    do: from(c in query, left_join: m in subquery(measured), on: m.sha == c.sha, where: is_nil(m.sha))

  defp by_status(query, "complete", measured),
    do: from(c in query, join: m in subquery(measured), on: m.sha == c.sha, where: m.complete)

  defp by_status(query, "in-progress", measured),
    do: from(c in query, join: m in subquery(measured), on: m.sha == c.sha, where: not m.complete)

  defp by_status(query, _unknown, _measured), do: where(query, false)

  # A labelled branch lists measured commits only, so "not measured" matches
  # none of them.
  defp labelled_filter(query, opts) do
    {search, status} = commit_filter(opts)
    query = if search == "", do: query, else: where(query, [c], like(c.git_commit_sha, ^sha_prefix(search)))

    case status do
      "" -> query
      "complete" -> where(query, [c], c.complete)
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
      refine: graph_filter(project.id, opts)
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

    %{
      commits: settle(commits, Commits.by_shas(project.id, Enum.map(commits, & &1.git_commit_sha)), lookback),
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
    labelled = fn query -> query |> where([c], c.git_branch == ^branch) |> ran_in(opts) |> labelled_filter(opts) end
    cursor = cursor_time(cursor)
    read = fn refine -> Commits.all(project.id, &(&1 |> labelled.() |> refine.())) end

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

  defp older_than(query, {at, sha}),
    do: where(query, [c], c.ran_at < ^at or (c.ran_at == ^at and c.git_commit_sha < ^sha))

  defp newer_than(query, {at, sha}),
    do: where(query, [c], c.ran_at > ^at or (c.ran_at == ^at and c.git_commit_sha > ^sha))

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
    |> Enum.map(&Map.put(&1, :chained, &1.measured and Map.get(&1, :complete, false)))
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

  defp naive(nil), do: nil
  defp naive(%DateTime{} = datetime), do: DateTime.to_naive(datetime)
  defp naive(%NaiveDateTime{} = datetime), do: datetime

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
    |> where([c], c.project_id == ^project.id and c.git_branch == ^branch)
    |> ran_in(opts)
    |> select([c], fragment("unnest(? || ?)", c.schemes, c.partial_schemes))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc """
  The branches whose runs never named a pull request, the most recently
  measured first, at most `limit` of them (100 by default): the branches the
  Code Coverage page picks its analytics from. The default branch leads,
  whether or not it is among them.
  """
  def branches(%Project{} = project, opts \\ []) do
    measured =
      CoverageCommit
      |> where([c], c.project_id == ^project.id and c.git_branch != "" and c.executable_lines > 0)
      |> group_by([c], c.git_branch)
      |> having([c], max(c.pull_request_number) == 0)
      |> order_by([c], desc: max(c.ran_at), asc: c.git_branch)
      |> limit(^Keyword.get(opts, :limit, 100))
      |> select([c], c.git_branch)
      |> Repo.all()

    [project.default_branch | List.delete(measured, project.default_branch)]
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

  # Without a ref, a branch is the measured commits its runs labelled with
  # it, newest run first.
  defp labelled_commits(project_id, branch, opts, limit) do
    project_id
    |> Commits.all(fn query ->
      query
      |> where([c], c.git_branch == ^branch)
      |> ran_in(opts)
      |> order_by([c], desc: c.ran_at)
      |> limit(^limit)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {row, depth} -> %{git_commit_sha: row.git_commit_sha, depth: depth, committed_at: row.ran_at} end)
  end

  # A commit whose runs skipped tests stands with its reported coverage and
  # lines (`Tuist.Tests.Coverage.Reported`): what a full run would have
  # measured when every skipped test was carried forward, in which case it
  # compares as a fully measured commit does, and otherwise the part of it
  # that is confirmed, the lines known to be covered among those that could
  # be counted (`confirmed: false`, `Commits.confirmed?/1`). `measured_*`
  # keep what its runs observed.
  defp with_coverage(%{reported_kind: kind} = row) when kind in ~w(reported partial) do
    Map.merge(row, %{
      coverage: Coverage.percentage(row.reported_covered_lines, row.reported_executable_lines),
      covered_lines: row.reported_covered_lines,
      executable_lines: row.reported_executable_lines,
      confirmed: Commits.confirmed?(row),
      measured_coverage: Coverage.percentage(row.covered_lines, row.executable_lines),
      measured_covered_lines: row.covered_lines,
      measured_executable_lines: row.executable_lines
    })
  end

  defp with_coverage(row),
    do:
      Map.merge(row, %{
        coverage: Coverage.percentage(row.covered_lines, row.executable_lines),
        confirmed: Commits.confirmed?(row)
      })

  defp effective_partial_schemes(%{reported_kind: "reported"}), do: []
  defp effective_partial_schemes(row), do: row.partial_schemes
end
