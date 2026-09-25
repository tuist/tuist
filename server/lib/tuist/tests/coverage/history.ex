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
  The repository the project's measured commits belong to (the newest
  published commit's), or nil when none named one.
  """
  def repository_id(project_id) do
    Repo.one(
      from(c in CoverageCommit,
        where: c.project_id == ^project_id and not is_nil(c.repository_id),
        order_by: [desc: c.updated_at],
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

  @doc """
  One point per chained commit of the branch, oldest first, with the
  commit's totals: what the trend chart draws. The period bounds when the
  commits were made and nothing else caps it, so a trend reaches as far
  back as coverage is kept. A commit's figure pools the
  schemes that measured it; a scheme's own totals are read per commit
  (`Tuist.Tests.Coverage.Comparison.compare/3`), where a baseline makes
  them comparable.
  """
  def branch_points(%Project{} = project, branch, opts \\ []) do
    case branch_ref(project, branch) do
      nil ->
        project
        |> branch_history(branch, opts)
        |> Map.fetch!(:commits)
        |> Enum.filter(& &1.chained)
        |> Enum.reverse()

      ref ->
        project.id
        |> point_rows(ref.id, opts)
        |> Enum.map(&(&1 |> with_coverage() |> Map.put(:measured, true)))
        |> chain()
        |> Enum.filter(& &1.chained)
        |> Enum.reverse()
    end
  end

  # Chaining decides which commits the trend draws, and a commit chains
  # against the one chained before it, so every measured commit of the
  # period is read, newest first; only the columns the chaining rule and the
  # chart need, not the runs and the carried ancestors each row also holds.
  defp point_rows(project_id, ref_id, opts) do
    from(c in CoverageCommit,
      where: c.project_id == ^project_id and c.ref_id == ^ref_id,
      order_by: [desc: c.position],
      select: %{
        git_commit_sha: c.git_commit_sha,
        committed_at: c.committed_at,
        covered_lines: c.covered_lines,
        executable_lines: c.executable_lines,
        unmeasured_files_count: c.unmeasured_files_count,
        reported_covered_lines: c.reported_covered_lines,
        reported_executable_lines: c.reported_executable_lines,
        reported_kind: c.reported_kind,
        schemes: c.schemes,
        partial_schemes: c.partial_schemes,
        complete: c.complete
      }
    )
    |> Commits.comparable()
    |> in_period(opts)
    |> Repo.all()
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
  ran. Each commit's chaining and `change` are settled over the page and the
  #{@lookback} measured commits below it. The period bounds the commits
  (`since`/`until`); `page_size` is 20 by default.
  """
  def commit_cursor_page(%Project{} = project, branch, opts \\ []) do
    size = Keyword.get(opts, :page_size, 20)
    cursor = cursor(opts)

    case branch_ref(project, branch) do
      nil -> labelled_cursor_page(project, branch, opts, size, cursor)
      ref -> graph_cursor_page(project, ref, opts, size, cursor)
    end
  end

  defp cursor(opts) do
    case {Keyword.get(opts, :after), Keyword.get(opts, :before)} do
      {value, _} when value not in [nil, ""] -> {:older, value}
      {_, value} when value not in [nil, ""] -> {:newer, value}
      _ -> nil
    end
  end

  defp graph_cursor_page(project, ref, opts, size, cursor) do
    period = [since: second(Keyword.get(opts, :since)), until: second(Keyword.get(opts, :until))]
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
    labelled = fn query -> query |> where([c], c.git_branch == ^branch) |> ran_in(opts) end
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
    |> chain()
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
  The branches with a measured commit in the period, the most recently
  measured first: one row per branch with its newest measured commit, that
  commit's totals, and the pull request its runs reported, if any
  (`pull_request_number`, 0 without one). A pull request whose runs never
  named a branch is listed under its number.

  `search` narrows by branch name or pull request number, `page` and
  `page_size` paginate (20 by default).
  """
  def refs(%Project{} = project, opts \\ []) do
    {page, opts} = Keyword.pop(opts, :page, 1)
    {page_size, opts} = Keyword.pop(opts, :page_size, 20)
    {search, opts} = Keyword.pop(opts, :search)

    query = refs_query(project.id, search, opts)
    total = Repo.one(from(r in subquery(query), select: count())) || 0
    total_pages = max(1, ceil(total / page_size))
    page = page |> max(1) |> min(total_pages)

    rows =
      from(r in subquery(query), order_by: [desc: r.ran_at], limit: ^page_size, offset: ^((page - 1) * page_size))
      |> Repo.all()
      |> Enum.map(&with_coverage/1)

    %{refs: rows, page: page, page_size: page_size, total_pages: total_pages, total_count: total}
  end

  # The newest measured commit of every branch and pull request the period
  # ran: a commit is filed under the branch its newest run named, or, when
  # none did, under its pull request's number.
  defp refs_query(project_id, search, opts) do
    latest =
      ran_in(
        from(c in CoverageCommit,
          where: c.project_id == ^project_id and c.executable_lines > 0,
          where: c.git_branch != "" or c.pull_request_number > 0,
          distinct:
            fragment(
              "CASE WHEN ? <> '' THEN ? ELSE '#' || ?::text END",
              c.git_branch,
              c.git_branch,
              c.pull_request_number
            ),
          order_by: [desc: c.ran_at],
          select: %{
            name:
              fragment(
                "CASE WHEN ? <> '' THEN ? ELSE '#' || ?::text END",
                c.git_branch,
                c.git_branch,
                c.pull_request_number
              ),
            git_branch: c.git_branch,
            pull_request_number: c.pull_request_number,
            base_branch: c.base_branch,
            git_commit_sha: c.git_commit_sha,
            ran_at: c.ran_at,
            covered_lines: c.covered_lines,
            executable_lines: c.executable_lines,
            schemes: c.schemes,
            partial_schemes: c.partial_schemes,
            complete: c.complete,
            completeness: c.completeness,
            reported_kind: c.reported_kind,
            reported_covered_lines: c.reported_covered_lines,
            reported_executable_lines: c.reported_executable_lines
          }
        ),
        opts
      )

    # A branch is searched by its name and by the number of the pull request
    # it was pushed for: the reader remembers one or the other.
    case search do
      blank when blank in [nil, ""] ->
        latest

      search ->
        pattern = "%" <> String.replace(search, ~w(\\ % _), &("\\" <> &1)) <> "%"

        from(r in subquery(latest),
          where: ilike(r.name, ^pattern) or ilike(fragment("'#' || ?::text", r.pull_request_number), ^pattern)
        )
    end
  end

  @doc """
  The commits of one pull request that gathered coverage, newest first,
  each with its measurement (`Tuist.Tests.Coverage.Commits.summary/2`
  fields) and the branch and base branch its runs reported: what the pull
  request page lists.
  """
  def pull_request_commits(project_id, pull_request_number, opts \\ []) do
    project_id
    |> Commits.all(fn query ->
      query
      |> where([c], c.pull_request_number == ^pull_request_number)
      |> ran_in(opts)
      |> order_by([c], desc: c.ran_at)
    end)
    |> Enum.map(&with_coverage/1)
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
