defmodule Tuist.Tests.Coverage.Commits do
  @moduledoc """
  A commit's coverage within a project: the union of every run that measured
  the commit (`Tuist.Tests.CoverageCommit`).

  A run is one measurement of a commit and a scheme is which slice of the
  code it measured, so the commit's figure merges them the way a run merges
  its shards: per path, a line is covered when any run covered it, and a file
  counts once however many schemes compiled it. Runs from a dirty checkout
  measured code that is not the commit's and never contribute. Partial runs
  do: what they observed is real; they only keep the scheme from counting as
  fully measured.

  Whether the commit's coverage pipeline has finished cannot be read off the
  data (it depends on the pipeline and on what the changed files trigger), so
  the client says so with `signal_complete/2`, which pull request gates wait
  for. Totals are republished (`recompute/2`) a few seconds after each run
  reports and on the signal, rewriting the commit's row one version up.

  The row lives in PostgreSQL beside the commit graph. Folding a commit also
  advances the refs its runs reported (`Tuist.GitHistory.advance_ref/5`):
  the branch a push ran on, or the pull request, so the commit takes its
  place on the first-parent tree and the row a copy of it.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.Test

  @doc """
  Schedules the commit's totals to be republished after a run reported
  coverage for it. Nothing is scheduled for a run without a commit or from a
  dirty checkout.
  """
  def enqueue_recompute(%Test{git_commit_sha: sha, git_dirty: dirty} = test) do
    # `dirty` is what the client said, and a client that says nothing said the
    # checkout was clean: negating it outright turns that into a crash after
    # the run's coverage is already stored.
    if is_binary(sha) and sha != "" and dirty != true,
      do: enqueue_recompute(test.project_id, sha),
      else: :skipped
  end

  @doc """
  Whether the commit measured nothing itself and its coverage is entirely
  carried forward: every scheme was skipped whole and every skipped test's
  coverage still applied. Its figure is the ancestor's, so it compares with
  whatever that ancestor measured rather than with an empty measured set.
  """
  def fully_carried?(%{reported_kind: "reported", schemes: []}), do: true
  def fully_carried?(_row), do: false

  @doc "Whether the commit already has a published coverage row."
  def measured?(_project_id, sha) when sha in [nil, ""], do: false

  def measured?(project_id, sha), do: not is_nil(summary(project_id, sha))

  def enqueue_recompute(_project_id, sha) when sha in [nil, ""], do: :skipped
  def enqueue_recompute(project_id, sha), do: CommitWorker.enqueue(project_id, sha)

  @publish_attempts 3
  @pending_completions "coverage_commit_completions"

  @doc """
  Republishes the commit's totals from its runs' retained reports and
  returns the row published, or nil when no run measured the commit.
  `complete:` and `completeness:` set the completion state; without them the
  state already published is kept.
  """
  def recompute(%Project{} = project, sha, opts \\ []) do
    {row, runs} = fold_and_publish(project, sha, opts, @publish_attempts)

    # Outside the commit's lock: advancing a ref takes the repository's.
    if row do
      advance_refs(project, sha, runs)
      summary(project.id, sha)
    end
  end

  # A fold reads the published row, spends seconds computing reported
  # coverage on a large suite, and writes it back. Two folds of the same
  # commit at once (the completion signal and a run's scheduled fold, on any
  # node) would each write what they read, and the later one wins: the
  # signal's `complete` was lost exactly that way. The fold runs outside any
  # transaction, and its write, under the commit's lock, goes through only
  # when the row is still the version it read; otherwise it folds again over
  # what the other one wrote. Past the last attempt it folds under the lock,
  # so it always ends up reading what the previous write left.
  defp fold_and_publish(project, sha, opts, attempts) when attempts > 1 do
    previous = summary(project.id, sha)
    {row, runs} = fold(project, sha, previous, opts)

    case publish_unless_changed(project, sha, previous && previous.version, row, opts) do
      :changed -> fold_and_publish(project, sha, opts, attempts - 1)
      published -> {published, runs}
    end
  end

  defp fold_and_publish(project, sha, opts, _attempts) do
    with_commit_lock(
      project,
      sha,
      fn ->
        {row, runs} = fold(project, sha, summary(project.id, sha), opts)
        {write(project, sha, row, opts), runs}
      end,
      timeout: to_timeout(minute: 5)
    )
  end

  defp publish_unless_changed(project, sha, version, row, opts) do
    if is_nil(row) and not Keyword.get(opts, :complete, false) do
      nil
    else
      with_commit_lock(project, sha, fn ->
        if published_version(project.id, sha) == version, do: write(project, sha, row, opts), else: :changed
      end)
    end
  end

  # The signal usually lands before any run of the commit folded (remote
  # processing and the runs' buffer both lag behind a final CI job), so with
  # nothing to publish it is kept for the commit's first fold (`publish/1`).
  defp write(project, sha, nil, opts) do
    if Keyword.get(opts, :complete, false) do
      Repo.insert_all(
        @pending_completions,
        [%{project_id: project.id, git_commit_sha: sha, inserted_at: DateTime.utc_now()}],
        on_conflict: :nothing
      )
    end

    nil
  end

  defp write(_project, _sha, row, _opts), do: publish(row)

  defp pending_completion(project_id, sha),
    do: from(c in @pending_completions, where: c.project_id == ^project_id and c.git_commit_sha == ^sha)

  defp with_commit_lock(project, sha, fun, opts \\ []) do
    {:ok, result} =
      Repo.transaction(
        fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["coverage_commit:#{project.id}:#{sha}"])
          fun.()
        end,
        opts
      )

    result
  end

  defp published_version(project_id, sha) do
    Repo.one(
      from(c in CoverageCommit, where: c.project_id == ^project_id and c.git_commit_sha == ^sha, select: c.version)
    )
  end

  # The refs the commit's runs reported move to it: a pull request's under
  # `pull/<number>`, a push's under its branch, each forking from the default
  # branch. A commit a ref already holds leaves it where it is, so a late
  # fold of an older commit never moves a ref back, and a commit the graph
  # does not know yet names no head.
  defp advance_refs(project, sha, runs) do
    runs
    |> Enum.filter(&(&1.git_repository_id > 0))
    |> Enum.map(&{&1.git_repository_id, ref_name(&1)})
    |> Enum.reject(fn {repository_id, ref} -> is_nil(ref) or not GitHistory.known?(repository_id, sha) end)
    |> Enum.uniq()
    |> Enum.each(fn {repository_id, ref} ->
      parent = if ref == project.default_branch, do: nil, else: project.default_branch
      GitHistory.advance_ref(repository_id, ref, parent, sha, only_forward: true)
    end)
  end

  defp ref_name(%{is_pull_request: true, pull_request_number: number}) when number > 0,
    do: GitHistory.pull_request_ref(number)

  defp ref_name(%{git_branch: branch}) when branch not in [nil, ""], do: branch
  defp ref_name(_run), do: nil

  # The row the commit's runs make, unwritten, or nil when there is none.
  defp fold(project, sha, previous, opts) do
    runs = runs(project.id, sha)
    reported = project |> Reported.compute(sha, runs: runs) |> then(&(&1 && Map.drop(&1, [:files, :carried_lines])))

    row =
      cond do
        # Every scheme was skipped whole, so no run measured the commit, but
        # its coverage is still known: all of it carried forward. The row is
        # written with nothing measured and the reported figure filled in, so
        # the commit is comparable and its pipeline can signal completion. A
        # commit whose runs carried nothing either — no candidate was ever
        # enumerated for those schemes — has no coverage to publish and keeps
        # none.
        runs == [] and not is_nil(reported) and reported.executable_lines > 0 ->
          carried_row(project, sha, previous, reported, opts)

        runs == [] ->
          nil

        true ->
          measured_row(project, sha, runs, previous, reported, opts)
      end

    {row, runs}
  end

  defp carried_row(project, sha, previous, reported, opts) do
    repository_id = Reported.repository_id(project.id, sha)

    project
    |> base_row(sha, previous, reported, opts)
    |> Map.merge(%{
      repository_id: positive(repository_id),
      build_system: Reported.build_system(project.id, sha),
      covered_lines: 0,
      executable_lines: 0,
      measured_files_count: 0,
      unmeasured_files_count: 0,
      schemes: [],
      partial_schemes: [],
      test_run_ids: []
    })
    |> Map.merge(place(repository_id, sha, previous && previous.ran_at))
  end

  defp measured_row(project, sha, runs, previous, reported, opts) do
    excluded = ExcludedPaths.pattern_for_project(project)
    run_ids = Enum.map(runs, & &1.test_run_id)
    totals = totals(project.id, run_ids, excluded)
    schemes = runs |> Enum.map(& &1.scheme) |> Enum.uniq() |> Enum.sort()

    partial_schemes =
      runs
      |> Enum.group_by(& &1.scheme, & &1.partial)
      |> Enum.filter(fn {_scheme, partials} -> Enum.all?(partials) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    repository_id = runs |> Enum.map(& &1.git_repository_id) |> Enum.max()
    newest = List.last(runs)

    project
    |> base_row(sha, previous, reported, opts)
    |> Map.merge(labels(runs))
    |> Map.merge(%{
      repository_id: positive(repository_id),
      build_system: runs |> hd() |> Map.fetch!(:build_system),
      covered_lines: totals.covered_lines,
      executable_lines: totals.executable_lines,
      measured_files_count: totals.measured_files_count,
      unmeasured_files_count: unmeasured_files_count(project.id, repository_id, sha, run_ids, excluded),
      schemes: schemes,
      partial_schemes: partial_schemes,
      test_run_ids: run_ids
    })
    |> Map.merge(place(repository_id, sha, utc(newest.ran_at)))
  end

  # What the runs reported: the newest one's branch, and the pull request of
  # the newest pull request run.
  defp labels(runs) do
    newest = List.last(runs)
    pull_request = runs |> Enum.filter(&(&1.is_pull_request and &1.pull_request_number > 0)) |> List.last()

    %{
      git_branch: newest.git_branch || "",
      pull_request_number: if(pull_request, do: pull_request.pull_request_number, else: 0),
      base_branch: if(pull_request, do: pull_request.base_branch, else: newest.base_branch) || ""
    }
  end

  # Where the commit stands in the graph, copied onto its row: its ref and
  # position when a ref owns it, and when it was committed (or, for a commit
  # the graph does not know, first measured).
  defp place(repository_id, sha, ran_at) do
    ran_at = usec(ran_at || DateTime.utc_now())

    case positive(repository_id) &&
           Repo.one(
             from(c in Tuist.GitHistory.Commit,
               where: c.repository_id == ^repository_id and c.sha == ^sha,
               select: %{ref_id: c.ref_id, position: c.position, committed_at: c.committed_at}
             )
           ) do
      nil ->
        %{ref_id: nil, position: nil, committed_at: ran_at, ran_at: ran_at}

      commit ->
        %{
          ref_id: commit.ref_id,
          position: commit.position,
          committed_at: usec(commit.committed_at),
          ran_at: ran_at
        }
    end
  end

  defp positive(id) when is_integer(id) and id > 0, do: id
  defp positive(_id), do: nil

  defp usec(%DateTime{microsecond: {value, _precision}} = at), do: %{at | microsecond: {value, 6}}

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(%DateTime{} = at), do: at

  # Under the commit's lock, so a signal kept for it is applied exactly once.
  defp publish(row) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    row = Map.merge(row, %{inserted_at: now, updated_at: now})

    row =
      case Repo.delete_all(pending_completion(row.project_id, row.git_commit_sha)) do
        {0, _} -> row
        _ -> %{row | complete: true, completeness: "signal"}
      end

    Repo.insert_all(CoverageCommit, [row],
      on_conflict: {:replace_all_except, [:project_id, :git_commit_sha, :inserted_at]},
      conflict_target: [:project_id, :git_commit_sha]
    )

    summary(row.project_id, row.git_commit_sha)
  end

  defp base_row(project, sha, nil, reported, opts),
    do: base_row(project, sha, %{git_branch: "", pull_request_number: 0, base_branch: "", version: 0}, reported, opts)

  defp base_row(project, sha, previous, reported, opts) do
    %{
      project_id: project.id,
      git_commit_sha: sha,
      reported_covered_lines: reported.covered_lines,
      reported_executable_lines: reported.executable_lines,
      reported_kind: reported.kind,
      skipped_tests_count: reported.skipped_tests_count,
      carried_tests_count: reported.carried_tests_count,
      gap_files_count: reported.gap_files_count,
      carried_from: reported.carried_from,
      git_branch: previous.git_branch,
      pull_request_number: previous.pull_request_number,
      base_branch: previous.base_branch,
      complete: Keyword.get(opts, :complete, Map.get(previous, :complete, false)),
      completeness: Keyword.get(opts, :completeness, Map.get(previous, :completeness, "")),
      version: previous.version + 1
    }
  end

  @doc """
  Records that the commit's coverage pipeline finished, republishing its
  totals as complete. Returns the row, or nil when no run measured the
  commit yet: the signal is then kept and the commit's first fold publishes
  it complete.
  """
  def signal_complete(%Project{} = project, sha) do
    recompute(project, sha, complete: true, completeness: "signal")
  end

  @doc "The published totals of a commit, with the measured set, or nil."
  def summary(_project_id, sha) when sha in [nil, ""], do: nil

  def summary(project_id, sha) do
    CoverageCommit
    |> where([c], c.project_id == ^project_id and c.git_commit_sha == ^sha)
    |> Repo.one()
    |> row()
  end

  @doc """
  The published commits of a project among `shas`, keyed by SHA: those with a
  comparable figure (`comparable/1`), what the history and the baselines
  read.
  """
  def by_shas(_project_id, []), do: %{}

  def by_shas(project_id, shas) do
    CoverageCommit
    |> where([c], c.project_id == ^project_id and c.git_commit_sha in ^shas)
    |> comparable()
    |> Repo.all()
    |> Map.new(&{&1.git_commit_sha, row(&1)})
  end

  @doc """
  The project's published commits with a comparable figure (`comparable/1`)
  matching a query refinement (`fun` receives the base query), each as
  `summary/2` returns it.
  """
  def all(project_id, fun \\ & &1) do
    CoverageCommit
    |> where([c], c.project_id == ^project_id)
    |> comparable()
    |> fun.()
    |> Repo.all()
    |> Enum.map(&row/1)
  end

  @doc """
  Narrows a query over `CoverageCommit` to the commits a history compares:
  those with measured lines, and those that measured nothing but carried all
  of their coverage forward (`fully_carried?/1`), whose figure is the
  reported one.
  """
  def comparable(query) do
    where(
      query,
      [c],
      c.executable_lines > 0 or (c.reported_kind == "reported" and c.reported_executable_lines > 0)
    )
  end

  @doc """
  The newest published commit with measured lines at or below `position` on
  a ref's segment, other than `except` and, unless `since` is nil, published
  since `since`, or nil: one index probe, the step a baseline takes per
  segment of the first-parent tree.
  """
  def nearest_on_ref(project_id, ref_id, position, except, since) do
    CoverageCommit
    |> where(
      [c],
      c.project_id == ^project_id and c.ref_id == ^ref_id and c.position <= ^position and
        c.git_commit_sha != ^except and c.executable_lines > 0
    )
    |> published_since(since)
    |> order_by([c], desc: c.position)
    |> limit(1)
    |> Repo.one()
    |> row()
  end

  defp published_since(query, nil), do: query
  defp published_since(query, since), do: where(query, [c], c.inserted_at >= ^since)

  @doc """
  The nearest published commit with measured lines at or below `position` on
  a ref's segment, going on below the fork on the ref it forked from, as
  `{row, distance}` with the distance in first parents, or nil: a probe per
  segment of the first-parent tree. `except` and `since` as in
  `nearest_on_ref/5`.
  """
  def nearest_on_segments(project_id, ref_id, position, except, since),
    do: nearest_on_segments(project_id, ref_id, position, except, since, 0)

  defp nearest_on_segments(_project_id, nil, _position, _except, _since, _distance), do: nil

  defp nearest_on_segments(project_id, ref_id, position, except, since, distance) do
    case nearest_on_ref(project_id, ref_id, position, except, since) do
      nil ->
        case GitHistory.get_ref(ref_id) do
          %{parent_ref_id: parent_id, fork_position: fork} when not is_nil(parent_id) ->
            nearest_on_segments(project_id, parent_id, fork, except, since, distance + position - fork)

          _ ->
            nil
        end

      commit ->
        {commit, distance + position - commit.position}
    end
  end

  @doc """
  The nearest published commit with measured lines among a commit's
  ancestors, merged-in ones included, the commit itself left out, as
  `{sha, distance}`, or nil.

  The first-parent tree bounds the walk: the nearest measured commit on the
  commit's first parents is `distance` away along the refs' segments, so a
  closer one merged in is within that depth and the walk goes no deeper.
  Only when no first parent within the window was measured does the walk
  cover the window.
  """
  def nearest_measured_ancestor(project_id, repository_id, sha) do
    nearest =
      case first_parent_distance(project_id, repository_id, sha) do
        nil -> nil
        distance -> nearest_within(project_id, repository_id, sha, distance)
      end

    nearest || GitHistory.nearest_ancestor(repository_id, sha, measured_shas(project_id, sha))
  end

  defp first_parent_distance(project_id, repository_id, sha) do
    {unowned, owned} = repository_id |> GitHistory.first_parents_to_segment(sha) |> Enum.split_with(&is_nil(&1.ref_id))
    measured = measured_among(project_id, unowned |> Enum.map(& &1.sha) |> List.delete(sha))

    case Enum.find(unowned, &MapSet.member?(measured, &1.sha)) do
      %{depth: depth} ->
        depth

      nil ->
        with [%{depth: depth, ref_id: ref_id, position: position}] <- owned,
             {_commit, distance} <- nearest_on_segments(project_id, ref_id, position, sha, nil) do
          depth + distance
        else
          _ -> nil
        end
    end
  end

  defp nearest_within(project_id, repository_id, sha, max_depth) do
    ancestors = repository_id |> GitHistory.ancestors(sha, max_depth: max_depth) |> Enum.reject(&(elem(&1, 1) == 0))
    measured = measured_among(project_id, Enum.map(ancestors, &elem(&1, 0)))
    Enum.find(ancestors, fn {ancestor, _depth} -> MapSet.member?(measured, ancestor) end)
  end

  @doc """
  As `nearest_measured_ancestor/3`, among the commits that measured at least
  one of `schemes`: what a commit's runs of those schemes read the files
  they did not build from. The walk is bounded the same way.
  """
  def nearest_measured_ancestor(_project_id, _repository_id, _sha, []), do: nil

  def nearest_measured_ancestor(project_id, repository_id, sha, schemes) do
    measured =
      from(c in CoverageCommit,
        where:
          c.project_id == ^project_id and c.executable_lines > 0 and c.git_commit_sha != ^sha and
            fragment("? && ?", c.schemes, type(^schemes, {:array, :string}))
      )

    nearest =
      case first_parent_distance_in(measured, repository_id, sha) do
        nil ->
          nil

        distance ->
          ancestors = repository_id |> GitHistory.ancestors(sha, max_depth: distance) |> Enum.reject(&(elem(&1, 1) == 0))
          found = shas_in(measured, Enum.map(ancestors, &elem(&1, 0)))
          Enum.find(ancestors, fn {ancestor, _depth} -> MapSet.member?(found, ancestor) end)
      end

    nearest || GitHistory.nearest_ancestor(repository_id, sha, Repo.all(select(measured, [c], c.git_commit_sha)))
  end

  defp first_parent_distance_in(measured, repository_id, sha) do
    {unowned, owned} = repository_id |> GitHistory.first_parents_to_segment(sha) |> Enum.split_with(&is_nil(&1.ref_id))
    found = shas_in(measured, Enum.map(unowned, & &1.sha))

    case Enum.find(unowned, &MapSet.member?(found, &1.sha)) do
      %{depth: depth} ->
        depth

      nil ->
        with [%{depth: depth, ref_id: ref_id, position: position}] <- owned,
             distance when is_integer(distance) <- segments_distance_in(measured, ref_id, position, 0) do
          depth + distance
        else
          _ -> nil
        end
    end
  end

  defp segments_distance_in(_measured, nil, _position, _distance), do: nil

  defp segments_distance_in(measured, ref_id, position, distance) do
    nearest =
      measured
      |> where([c], c.ref_id == ^ref_id and c.position <= ^position)
      |> order_by([c], desc: c.position)
      |> limit(1)
      |> select([c], c.position)
      |> Repo.one()

    case nearest do
      nil ->
        case GitHistory.get_ref(ref_id) do
          %{parent_ref_id: parent_id, fork_position: fork} when not is_nil(parent_id) ->
            segments_distance_in(measured, parent_id, fork, distance + position - fork)

          _ ->
            nil
        end

      found ->
        distance + position - found
    end
  end

  defp shas_in(_measured, []), do: MapSet.new()

  defp shas_in(measured, shas) do
    measured |> where([c], c.git_commit_sha in ^shas) |> select([c], c.git_commit_sha) |> Repo.all() |> MapSet.new()
  end

  defp measured_among(_project_id, []), do: MapSet.new()

  defp measured_among(project_id, shas) do
    from(c in CoverageCommit,
      where: c.project_id == ^project_id and c.git_commit_sha in ^shas and c.executable_lines > 0,
      select: c.git_commit_sha
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Whether the project published any commit with measured lines since `since`, other than `except`."
  def any_measured?(project_id, except, since) do
    Repo.exists?(
      from(c in CoverageCommit,
        where:
          c.project_id == ^project_id and c.executable_lines > 0 and c.git_commit_sha != ^except and
            c.inserted_at >= ^since
      )
    )
  end

  @doc "The SHAs of the project's published commits with measured lines, other than `except`."
  def measured_shas(project_id, except) do
    Repo.all(
      from(c in CoverageCommit,
        where: c.project_id == ^project_id and c.executable_lines > 0 and c.git_commit_sha != ^except,
        select: c.git_commit_sha
      )
    )
  end

  @doc """
  Drops the commits' coverage past its retention
  (`Tuist.Environment.coverage_commit_retention_days/1`), by when the commit
  was made: a pull request's own commits after `pull_requests` days, every
  other commit after `commits` days, and completion signals no run ever
  followed after `pull_requests` days. Returns how many commits went.
  """
  def prune(retention \\ Tuist.Environment.coverage_commit_retention_days()) do
    now = DateTime.utc_now()
    commits_cutoff = DateTime.add(now, -retention.commits, :day)
    pull_requests_cutoff = DateTime.add(now, -retention.pull_requests, :day)

    {count, _} =
      Repo.delete_all(
        from(c in CoverageCommit,
          as: :commit,
          where:
            c.committed_at < ^commits_cutoff or
              (c.committed_at < ^pull_requests_cutoff and c.pull_request_number > 0 and
                 (is_nil(c.ref_id) or
                    exists(
                      from(r in Tuist.GitHistory.Ref,
                        where: r.id == parent_as(:commit).ref_id and not is_nil(r.parent_ref_id)
                      )
                    )))
        )
      )

    Repo.delete_all(from(c in @pending_completions, where: c.inserted_at < ^pull_requests_cutoff))

    count
  end

  defp row(nil), do: nil

  defp row(%CoverageCommit{} = commit) do
    commit
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.put(:git_repository_id, commit.repository_id || 0)
    |> with_percentages()
  end

  @doc """
  The row with `coverage`, the observed percentage, and `reported_coverage`,
  what the commit is covered by once the tests its runs skipped are carried
  forward (`Tuist.Tests.Coverage.Reported`); the same as `coverage` for a
  commit published before reported coverage existed.
  """
  def with_percentages(row) do
    reported =
      if Map.get(row, :reported_kind, "") == "",
        do: Coverage.percentage(row.covered_lines, row.executable_lines),
        else: Coverage.percentage(row.reported_covered_lines, row.reported_executable_lines)

    row
    |> Map.put(:coverage, Coverage.percentage(row.covered_lines, row.executable_lines))
    |> Map.put(:reported_coverage, reported)
  end

  @doc """
  What a published commit is covered by once the tests its runs skipped are
  carried forward (`Tuist.Tests.Coverage.Reported`), as the comparison, the
  API and the pages show it; nil for a commit published before reported
  coverage existed.
  """
  def reported_figure(%{reported_kind: kind} = summary) when kind not in [nil, ""] do
    %{
      kind: kind,
      coverage: Coverage.percentage(summary.reported_covered_lines, summary.reported_executable_lines),
      covered_lines: summary.reported_covered_lines,
      executable_lines: summary.reported_executable_lines,
      skipped_tests_count: summary.skipped_tests_count,
      carried_tests_count: summary.carried_tests_count,
      gap_files_count: summary.gap_files_count,
      carried_from: summary.carried_from
    }
  end

  def reported_figure(_summary), do: nil

  @doc """
  The runs that measured the commit and count towards it: one row per run
  with its scheme, whether it was partial, and its repository. Runs from a
  dirty checkout are left out.
  """
  def runs(project_id, sha) when is_binary(sha), do: runs(project_id, [sha])

  def runs(_project_id, []), do: []

  def runs(project_id, shas) when is_list(shas) do
    # The ancestor window is thousands of commits wide, and ClickHouse binds one
    # HTTP form field per parameter, so the shas are read in chunks and the
    # ordering is restored here rather than by the query.
    shas
    |> Coverage.id_chunks()
    |> Enum.flat_map(&runs_chunk(project_id, &1))
    |> Enum.sort_by(& &1.ran_at, NaiveDateTime)
  end

  # The commits' runs are found through their coverage totals, which carry
  # the SHA under an index, and joined to the runs by id: grouping every run
  # of the project first made each commit read cost the project's history.
  defp runs_chunk(project_id, shas) do
    totals = Coverage.run_totals_query(project_id, shas: shas)

    runs =
      from(t in Test,
        where:
          t.project_id == ^project_id and t.git_commit_sha in ^shas and
            t.id in subquery(from(c in subquery(totals), select: c.test_run_id)),
        group_by: t.id,
        select: %{
          id: t.id,
          scheme: fragment("any(?)", t.scheme),
          build_system: fragment("any(?)", t.build_system),
          git_commit_sha: fragment("any(?)", t.git_commit_sha),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          git_dirty: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at),
          git_branch: fragment("any(?)", t.git_branch),
          is_pull_request: fragment("argMax(?, ?)", t.is_pull_request, t.inserted_at),
          pull_request_number: fragment("argMax(?, ?)", t.pull_request_number, t.inserted_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.inserted_at),
          ran_at: min(t.ran_at)
        }
      )

    ClickHouseRepo.all(
      from(c in subquery(totals),
        join: t in subquery(runs),
        on: t.id == c.test_run_id,
        where: t.git_dirty == false,
        select: %{
          test_run_id: c.test_run_id,
          scheme: c.scheme,
          build_system: c.build_system,
          partial: c.partial,
          git_commit_sha: t.git_commit_sha,
          git_repository_id: t.git_repository_id,
          git_branch: t.git_branch,
          is_pull_request: t.is_pull_request,
          pull_request_number: t.pull_request_number,
          base_branch: t.base_branch,
          ran_at: t.ran_at,
          covered_lines: c.covered_lines,
          executable_lines: c.executable_lines
        },
        order_by: [asc: t.ran_at]
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  @doc "The ids of the runs that count towards the commit."
  def run_ids(project_id, sha), do: project_id |> runs(sha) |> Enum.map(& &1.test_run_id)

  defp totals(project_id, run_ids, excluded) do
    ClickHouseRepo.one(
      from(f in subquery(Coverage.merged_files_query_for_runs(project_id, run_ids, excluded)),
        select: %{
          covered_lines: fragment("toUInt64(sum(?))", f.covered_lines),
          executable_lines: fragment("toUInt64(sum(?))", f.executable_lines),
          measured_files_count: fragment("toUInt32(count(?))", f.path)
        }
      ),
      settings: [select_sequential_consistency: 1]
    ) || %{covered_lines: 0, executable_lines: 0, measured_files_count: 0}
  end

  # The commit's listing narrowed to the languages the runs measured (a
  # listing has everything Git tracks; only files of the kinds the coverage
  # tool instruments can be "unmeasured"), minus the excluded paths and the
  # files some run measured.
  @doc """
  The files the commit's listing holds that no run measured, in path order:
  the gap the page names, and the count published with the commit. `limit`
  caps the list (50 by default) and `offset` skips into it, for paging. Empty
  for a commit without a listing, or one the project has no coverage for.
  """
  def unmeasured_files(%Project{} = project, sha, opts \\ []) do
    case summary(project.id, sha) do
      nil ->
        []

      summary ->
        project.id
        |> unmeasured_paths(
          summary.git_repository_id,
          sha,
          summary.test_run_ids,
          ExcludedPaths.pattern_for_project(project)
        )
        |> Enum.sort()
        |> Enum.drop(Keyword.get(opts, :offset, 0))
        |> Enum.take(Keyword.get(opts, :limit, 50))
    end
  end

  defp unmeasured_files_count(project_id, repository_id, sha, run_ids, excluded),
    do: length(unmeasured_paths(project_id, repository_id, sha, run_ids, excluded))

  # Build manifests are source files no product compiles, so a listing entry
  # for one is not a gap in the project's coverage. They are named, not
  # guessed: these are Tuist's own manifests and SwiftPM's.
  @manifest_globs [
    "Project.swift",
    "Workspace.swift",
    "Tuist.swift",
    "Package.swift",
    "**/Project.swift",
    "**/Workspace.swift",
    "**/Package.swift",
    "Tuist/**",
    "**/Tuist/**"
  ]

  # A listed file counts as unmeasured only when it shares an extension with
  # something the runs did measure: the listing holds the whole repository,
  # and a language no scheme compiles is not a gap in this project's coverage.
  defp unmeasured_paths(_project_id, repository_id, _sha, _run_ids, _excluded) when repository_id in [nil, 0], do: []

  defp unmeasured_paths(project_id, repository_id, sha, run_ids, excluded) do
    if GitHistory.listing_stored?(repository_id, sha) do
      measured = report_paths(project_id, run_ids)

      extensions =
        measured
        |> Enum.map(&Path.extname/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      if extensions == [] do
        []
      else
        pattern = ExcludedPaths.pattern(Enum.map(extensions, &("**/*" <> &1)))
        listed = repository_id |> GitHistory.commit_files(sha, match: pattern) |> Enum.map(& &1.path)
        excluded_regex = ExcludedPaths.compile(excluded)
        manifests = ExcludedPaths.compile(ExcludedPaths.pattern(@manifest_globs))
        measured = MapSet.new(measured)

        Enum.filter(listed, fn path ->
          not MapSet.member?(measured, path) and not ExcludedPaths.excluded?(manifests, path) and
            not ExcludedPaths.excluded?(excluded_regex, path)
        end)
      end
    else
      []
    end
  end

  # Every path the runs reported, product and test code alike: a test file
  # in the listing is not an unmeasured product file.
  defp report_paths(project_id, run_ids) do
    ClickHouseRepo.all(
      from(f in Coverage.report_files_for_runs(project_id, run_ids), distinct: true, select: f.path),
      settings: [select_sequential_consistency: 1]
    )
  end

  @doc """
  The commit's files with the runs' reports merged, without line data, by
  path; `paths:` narrows them to those paths.
  """
  def merged_files(project_id, sha, opts \\ []) do
    case {run_ids(project_id, sha), Keyword.get(opts, :paths)} do
      {[], _paths} ->
        []

      {_ids, []} ->
        []

      {ids, nil} ->
        ClickHouseRepo.all(from(f in subquery(merged_query(project_id, ids, opts)), order_by: f.path))

      {ids, paths} ->
        # One HTTP form field per bound path, which ClickHouse caps.
        paths
        |> Enum.uniq()
        |> Enum.chunk_every(900)
        |> Enum.flat_map(fn chunk ->
          ClickHouseRepo.all(from(f in subquery(merged_query(project_id, ids, opts)), where: f.path in ^chunk))
        end)
        |> Enum.sort_by(& &1.path)
    end
  end

  defp merged_query(project_id, ids, opts),
    do: Coverage.merged_files_query_for_runs(project_id, ids, Coverage.excluded(project_id, opts))

  @doc """
  The commit's targets with their file count and line totals, least covered
  first. On a commit whose skipped tests were all carried forward they are
  over its reported coverage, as its files are (`measured: true` keeps to
  what its runs measured).
  """
  def targets(project_id, sha, opts \\ []) do
    case carried_files(project_id, sha, opts) do
      nil -> measured_targets(project_id, sha, opts)
      files -> targets_of(files)
    end
  end

  defp targets_of(files) do
    files
    |> Enum.flat_map(fn file -> Enum.map(file.targets, &{&1, file}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, target_files} ->
      %{
        name: name,
        files_count: length(target_files),
        covered_lines: target_files |> Enum.map(& &1.covered_lines) |> Enum.sum(),
        executable_lines: target_files |> Enum.map(& &1.executable_lines) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(&{&1.covered_lines / max(&1.executable_lines, 1), &1.name})
  end

  defp measured_targets(project_id, sha, opts) do
    case run_ids(project_id, sha) do
      [] ->
        []

      ids ->
        ClickHouseRepo.all(
          from(f in subquery(Coverage.merged_files_query_for_runs(project_id, ids, Coverage.excluded(project_id, opts))),
            group_by: fragment("arrayJoin(?)", f.targets),
            select: %{
              name: fragment("arrayJoin(?)", f.targets),
              files_count: count(f.path),
              covered_lines: sum(f.covered_lines),
              executable_lines: sum(f.executable_lines)
            },
            order_by: [
              asc: fragment("sum(?) / greatest(sum(?), 1)", f.covered_lines, f.executable_lines),
              asc: fragment("arrayJoin(?)", f.targets)
            ]
          )
        )
    end
  end

  @doc """
  One page of the commit's files, least covered first, and the number of
  files; over its reported coverage on a commit whose skipped tests were all
  carried forward, as `targets/3`.
  """
  def list_files(project_id, sha, page, page_size, opts \\ []) do
    case carried_files(project_id, sha, opts) do
      nil ->
        list_measured_files(project_id, sha, page, page_size, opts)

      files ->
        {files
         |> Enum.sort_by(&{&1.covered_lines / max(&1.executable_lines, 1), &1.path})
         |> Enum.slice((page - 1) * page_size, page_size), length(files)}
    end
  end

  # The files of a commit whose reported coverage is exact, or nil: what the
  # lists read instead of the measured files, so a file only a skipped test
  # covers is not listed as uncovered.
  defp carried_files(project_id, sha, opts) do
    with false <- Keyword.get(opts, :measured, false),
         %{} = summary <- summary(project_id, sha),
         true <- carried?(summary),
         %Project{} = project <- Tuist.Projects.get_project_by_id(project_id) do
      excluded = Coverage.excluded(project_id, opts)
      Reported.merged_files(project, sha, merged_files(project_id, sha, excluded: excluded), excluded: excluded)
    else
      _ -> nil
    end
  end

  # Coverage was carried into the commit: a run skipped tests, or every
  # scheme was skipped whole.
  defp carried?(%{reported_kind: "reported", partial_schemes: [_ | _]}), do: true
  defp carried?(summary), do: fully_carried?(summary)

  defp list_measured_files(project_id, sha, page, page_size, opts) do
    case run_ids(project_id, sha) do
      [] ->
        {[], 0}

      ids ->
        files_query = Coverage.merged_files_query_for_runs(project_id, ids, Coverage.excluded(project_id, opts))

        [files, count] =
          Tuist.Tasks.parallel_tasks([
            fn ->
              ClickHouseRepo.all(
                from(f in subquery(files_query),
                  order_by: [asc: fragment("? / greatest(?, 1)", f.covered_lines, f.executable_lines), asc: f.path],
                  limit: ^page_size,
                  offset: ^((page - 1) * page_size)
                )
              )
            end,
            fn -> ClickHouseRepo.one(from(f in subquery(files_query), select: count(f.path))) || 0 end
          ])

        {files, count}
    end
  end

  @doc """
  The merged per-line execution counts of the given paths at the commit,
  keyed by path, as `{line, count}` pairs in line order.
  """
  def line_counts(project_id, sha, paths, opts \\ [])

  def line_counts(_project_id, _sha, [], _opts), do: %{}

  def line_counts(project_id, sha, paths, opts) do
    case run_ids(project_id, sha) do
      [] ->
        %{}

      ids ->
        from(
          f in Coverage.without_excluded(
            Coverage.report_files_for_runs(project_id, ids),
            Coverage.excluded(project_id, opts)
          ),
          where: f.path in ^paths and not f.is_test,
          select: {f.path, f.line_numbers, f.execution_counts}
        )
        |> ClickHouseRepo.all()
        |> Enum.group_by(&elem(&1, 0), fn {_path, lines, counts} -> Enum.zip(lines, counts) end)
        |> Map.new(fn {path, rows} ->
          {path,
           rows
           |> List.flatten()
           |> Enum.reduce(%{}, fn {line, count}, acc -> Map.update(acc, line, count, &(&1 + count)) end)
           |> Enum.sort()}
        end)
    end
  end

  @doc """
  One file's merged coverage at the commit
  (`Tuist.Tests.Coverage.file_detail/3` over its runs), or nil. On a commit
  whose skipped tests were all carried forward, `carried_lines` lists the
  lines that count as covered through a skipped test alone (their count stays
  0: no run here executed them), and a file no run at the commit compiled is
  read from the run its lines were carried from.
  """
  def file_detail(project_id, sha, path, opts \\ []) do
    carried = carried_file(project_id, sha, path, opts)
    ids = run_ids(project_id, sha)

    case file_rows(project_id, ids, path) do
      [] when is_nil(carried) -> nil
      [] -> carried.source_run_ids |> unbuilt_rows(project_id, path) |> detail_with_carried(path, carried)
      rows -> detail_with_carried(rows, path, carried)
    end
  end

  defp file_rows(_project_id, [], _path), do: []

  defp file_rows(project_id, ids, path) do
    ClickHouseRepo.all(
      from(f in Coverage.report_files_for_runs(project_id, ids),
        where: f.path == ^path and not f.is_test,
        order_by: [desc: f.inserted_at]
      )
    )
  end

  # Nothing at the commit executed a file it did not compile.
  defp unbuilt_rows(source_run_ids, project_id, path) do
    project_id
    |> file_rows(source_run_ids, path)
    |> Enum.map(&%{&1 | execution_counts: Enum.map(&1.execution_counts, fn _ -> 0 end), covered_lines: 0})
  end

  defp carried_file(project_id, sha, path, opts) do
    with false <- Keyword.get(opts, :measured, false),
         %{} = summary <- summary(project_id, sha),
         true <- carried?(summary),
         %Project{} = project <- Tuist.Projects.get_project_by_id(project_id) do
      Reported.file(project, sha, path)
    else
      _ -> nil
    end
  end

  defp detail_with_carried([], _path, _carried), do: nil
  defp detail_with_carried(rows, path, nil), do: Coverage.detail(path, rows)

  defp detail_with_carried(rows, path, carried) do
    detail = Coverage.detail(path, rows)
    carried_set = MapSet.new(carried.carried_lines)
    only_carried = for {line, 0} <- detail.lines, MapSet.member?(carried_set, line), do: line
    effective = Enum.map(detail.lines, fn {line, count} -> {line, if(line in only_carried, do: 1, else: count)} end)

    Map.merge(detail, %{
      carried_lines: only_carried,
      covered_lines: Enum.count(effective, fn {_line, count} -> count > 0 end),
      uncovered_ranges: detail.uncovered_ranges && Coverage.uncovered_ranges(effective)
    })
  end
end
