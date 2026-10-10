defmodule Tuist.Tests.Coverage.Commits do
  @moduledoc """
  A commit's coverage within a project: the union of every run that measured
  the commit (`Tuist.Tests.CoverageCommit`).

  A run is one measurement of a commit and a scheme is which slice of the
  code it measured, so the commit's figure merges them the way a run merges
  its shards: per path, a line is covered when any run covered it, and a file
  counts once however many schemes compiled it. Runs from a dirty checkout
  measured code that is not the commit's and never contribute; a scheme only
  they measured leaves the figure a lower bound. Partial runs do contribute:
  what they observed is real; they only keep the scheme from counting as
  fully measured.

  Whether the commit's coverage pipeline has finished cannot be read off the
  data (it depends on the pipeline and on what the changed files trigger), so
  the client says so with `signal_complete/2`, which pull request gates wait
  for. Totals are republished (`recompute/2`) a few seconds after each run
  reports and on the signal, rewriting the commit's row one version up. A
  complete commit's per-file figures are then stored as deltas
  (`Tuist.Tests.Coverage.Deltas`).

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
  alias Tuist.Tests.Coverage.Deltas
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.GapReasons
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.CoverageCommit
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test

  @doc """
  Schedules the commit's totals to be republished after a run reported
  coverage for it. Nothing is scheduled for a run without a commit, or for a
  local run from a dirty checkout. A CI run from a dirty checkout schedules a
  fold too: it never counts, but a scheme only it measured leaves the
  commit's figure a lower bound, whichever of the commit's runs lands last.
  """
  def enqueue_recompute(%Test{git_commit_sha: sha, git_dirty: dirty, is_ci: ci} = test) do
    if is_binary(sha) and sha != "" and (dirty != true or ci == true),
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

  @doc """
  Whether the commit's figure is incomplete, a lower bound (`reported_kind`
  `partial`, `gap_reasons` saying why): the coverage of some skipped tests
  could not be determined, a scheme's runs executed only the tests their
  caller selected, or a scheme's coverage only came from CI runs on a dirty
  checkout. The fold decides it, so the actual coverage may be higher. A figure whose
  skipped tests were all carried forward is complete, as is one nothing
  skipped in.
  """
  def incomplete?(%{reported_kind: kind}), do: kind == "partial"
  def incomplete?(_row), do: false

  @doc "Why the commit's figure is a lower bound (`Tuist.Tests.Coverage.GapReasons`), none when it is whole."
  def gap_reasons(row), do: GapReasons.decode(Map.get(row, :gap_reasons) || 0)

  @doc "Narrows a query over `CoverageCommit` to the commits whose figure is complete (`incomplete?/1`)."
  def complete_figures(query), do: where(query, [c], c.reported_kind != "partial")

  @doc """
  A commit's status on a branch: `:not_measured` when no run gave it a figure
  (`measured: false` in a branch's commit list), `:in_progress` until its
  pipeline signals completion, then `:incomplete` when its figure is a lower
  bound (`incomplete?/1`) and `:complete` otherwise. Only complete commits join
  the trend and have a change.
  """
  def status(%{measured: false}), do: :not_measured
  def status(%{complete: true} = row), do: if(incomplete?(row), do: :incomplete, else: :complete)
  def status(_row), do: :in_progress

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

      # The place was read before the row existed, so an advance that moved
      # the commit in between (its child's fold advancing the branch through
      # it) synced no row, and this commit's own advance, observed earlier
      # than that one or finding the branch already holds it, moves nothing.
      if row.git_repository_id > 0, do: GitHistory.sync_coverage_places(row.git_repository_id, [sha])

      summary = summary(project.id, sha)
      if Deltas.complete?(summary), do: Deltas.enqueue(project.id, sha)
      summary
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
  # branch. Each move is observed at the newest run that reported the ref, so
  # neither a late fold of an older commit nor a refold (after the excluded
  # paths changed, say) moves a ref back, and a commit the graph does not
  # know yet names no head.
  defp advance_refs(project, sha, runs) do
    runs
    |> Enum.filter(&(&1.git_repository_id > 0))
    |> Enum.group_by(&{&1.git_repository_id, ref_name(&1)}, & &1.ran_at)
    |> Enum.reject(fn {{repository_id, ref}, _ran_at} -> is_nil(ref) or not GitHistory.known?(repository_id, sha) end)
    |> Enum.each(fn {{repository_id, ref}, ran_at} ->
      parent = if ref == project.default_branch, do: nil, else: project.default_branch
      observed_at = Enum.max(ran_at, NaiveDateTime)
      GitHistory.advance_ref(repository_id, ref, parent, sha, only_forward: true, observed_at: observed_at)
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

    cond do
      # Every scheme was skipped whole, so no run measured the commit, but
      # its coverage is still known: all of it carried forward. The row is
      # written with nothing measured and the reported figure filled in, so
      # the commit is comparable and its pipeline can signal completion. A
      # commit whose runs carried nothing either (no ancestor ran what those
      # schemes skipped) has no coverage to publish and keeps none.
      runs == [] and not is_nil(reported) and reported.executable_lines > 0 ->
        clean = clean_runs(project.id, sha)
        {project |> carried_row(sha, previous, reported, clean, opts) |> lower_bound(project.id, sha), clean}

      runs == [] ->
        {nil, []}

      true ->
        {project |> measured_row(sha, runs, previous, reported, opts) |> lower_bound(project.id, sha), runs}
    end
  end

  # Besides the gaps `Reported` finds, the figure is a lower bound when a
  # scheme's runs all left tests out and nothing names what Tuist skipped, or
  # when a scheme's coverage only came from CI runs on a dirty checkout: the
  # pipeline set out to measure it, and no clean run of it did, not even one
  # skipped whole. A local run measures what a developer tried, not what the pipeline
  # owes the commit. Settled on the built row, so the unmeasured files are
  # still read the way the coverage was reached.
  defp lower_bound(row, project_id, sha) do
    row =
      if row.reported_kind == "measured" and row.partial_schemes != [],
        do: %{row | reported_kind: "partial"},
        else: row

    if dirty_only_scheme?(project_id, sha) do
      reasons = GapReasons.decode(row.gap_reasons) ++ [:dirty_run_excluded]
      %{row | reported_kind: "partial", gap_reasons: GapReasons.encode(reasons)}
    else
      row
    end
  end

  defp dirty_only_scheme?(project_id, sha) do
    covered = from(c in subquery(Coverage.run_totals_query(project_id, shas: [sha])), select: c.test_run_id)

    dirty =
      ClickHouseRepo.all(
        from(t in Test,
          where: t.project_id == ^project_id and t.git_commit_sha == ^sha and t.is_ci and t.id in subquery(covered),
          group_by: t.id,
          having: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at) == true,
          select: fragment("any(?)", t.scheme)
        ),
        settings: [select_sequential_consistency: 1]
      )

    if dirty == [] do
      false
    else
      clean = project_id |> clean_runs(sha) |> MapSet.new(& &1.scheme)
      Enum.any?(dirty, &(not MapSet.member?(clean, &1)))
    end
  end

  defp carried_row(project, sha, previous, reported, clean, opts) do
    repository_id = Reported.repository_id(project.id, sha)

    unmeasured =
      unmeasured_paths(
        project,
        %{
          git_repository_id: repository_id,
          git_commit_sha: sha,
          test_run_ids: [],
          schemes: [],
          reported_kind: reported.kind
        },
        ExcludedPaths.pattern_for_project(project)
      )

    project
    |> base_row(sha, previous, reported, opts)
    |> Map.merge(if(clean == [], do: %{}, else: labels(clean)))
    |> Map.merge(%{
      repository_id: positive(repository_id),
      build_system: Reported.build_system(project.id, sha),
      covered_lines: 0,
      executable_lines: 0,
      measured_files_count: 0,
      unmeasured_files_count: length(unmeasured),
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

    unmeasured =
      unmeasured_paths(
        project,
        %{
          git_repository_id: repository_id,
          git_commit_sha: sha,
          test_run_ids: run_ids,
          schemes: schemes,
          reported_kind: reported.kind
        },
        excluded
      )

    project
    |> base_row(sha, previous, reported, opts)
    |> Map.merge(labels(runs))
    |> Map.merge(%{
      repository_id: positive(repository_id),
      build_system: runs |> hd() |> Map.fetch!(:build_system),
      covered_lines: totals.covered_lines,
      executable_lines: totals.executable_lines,
      measured_files_count: totals.measured_files_count,
      unmeasured_files_count: length(unmeasured),
      schemes: schemes,
      partial_schemes: partial_schemes,
      test_run_ids: run_ids
    })
    |> Map.merge(place(repository_id, sha, utc(newest.ran_at)))
  end

  # A commit's runs from a clean checkout, measured or not, oldest first, with
  # what they reported about where the commit is: what labels a commit whose
  # every scheme was skipped whole and moves its refs.
  defp clean_runs(project_id, sha) do
    ClickHouseRepo.all(
      from(t in Test,
        where: t.project_id == ^project_id and t.git_commit_sha == ^sha,
        group_by: t.id,
        having: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at) == false,
        order_by: [asc: min(t.ran_at)],
        select: %{
          test_run_id: t.id,
          scheme: fragment("any(?)", t.scheme),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          git_branch: fragment("any(?)", t.git_branch),
          is_pull_request: fragment("argMax(?, ?)", t.is_pull_request, t.inserted_at),
          pull_request_number: fragment("argMax(?, ?)", t.pull_request_number, t.inserted_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.inserted_at),
          ran_at: min(t.ran_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
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
      gap_reasons: reported.gap_reasons,
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
  The nearest published commit with measured lines among a commit's
  ancestors, merged-in ones included, the commit itself left out, that
  measured at least one of `schemes`, as `{sha, distance}`, or nil: what a
  commit's runs of those schemes read the files they did not build from.

  The first-parent tree bounds the walk: the nearest such commit on the
  commit's first parents is `distance` away along the refs' segments, so a
  closer one merged in is within that depth and the walk goes no deeper.
  Only when no first parent within the window qualifies does the walk cover
  the window.
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
          coverage_evidence_status: fragment("argMax(?, ?)", t.coverage_evidence_status, t.inserted_at),
          only_test_identifiers: fragment("argMax(?, ?)", t.only_test_identifiers, t.inserted_at),
          skip_test_identifiers: fragment("argMax(?, ?)", t.skip_test_identifiers, t.inserted_at),
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
          coverage_evidence_status: t.coverage_evidence_status,
          only_test_identifiers: t.only_test_identifiers,
          skip_test_identifiers: t.skip_test_identifiers,
          ran_at: t.ran_at,
          covered_lines: c.covered_lines,
          executable_lines: c.executable_lines
        },
        order_by: [asc: t.ran_at]
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  @newest_run_first [desc: :ran_at, desc: :id]

  @doc """
  One page of the runs with coverage of a subject, newest first: a commit's
  (`{:commit, sha}`), or those that named a branch (`{:branch, name}`), run
  between `since` and `until`.
  Runs from a dirty checkout are left out, as `runs/2` does, unless
  `dirty: true` lists them too, with `git_dirty` set, to show why a scheme
  is missing from a figure.

  `search` keeps the schemes containing it, ignoring case; `scheme` as
  `{:== | :!=, name}` and `partial` as a boolean narrow them further. Pages
  are read from a cursor (`after`, `before`) of `page_size` runs (20 by
  default) along the order `test_runs` is stored in, so a page costs the same
  however long the period.
  """
  def run_cursor_page(project_id, scope, opts \\ []) do
    size = Keyword.get(opts, :page_size, 20)
    cursor = run_cursor(opts)
    read = fn keyset, order, limit -> read_run_page(project_id, scope, opts, keyset, order, limit) end
    {rows, more?} = cursor |> run_page_rows(read, size + 1) |> Enum.split(size)
    rows = if match?({:newer, _}, cursor), do: Enum.reverse(rows), else: rows
    {newest, oldest} = {List.first(rows), List.last(rows)}

    exists? = fn
      nil, _side -> false
      row, side -> read.(side.(run_key(row)), @newest_run_first, 1) != []
    end

    %{
      runs: with_run_totals(project_id, rows),
      has_next_page?: older_runs?(cursor, more? != [], fn -> exists?.(oldest, &older_run/1) end),
      has_previous_page?: newer_runs?(cursor, more? != [], fn -> exists?.(newest, &newer_run/1) end),
      start_cursor: newest && encode_run_cursor(run_key(newest)),
      end_cursor: oldest && encode_run_cursor(run_key(oldest))
    }
  end

  defp run_page_rows({:older, key}, read, limit), do: read.(older_run(key), @newest_run_first, limit)
  defp run_page_rows({:newer, key}, read, limit), do: read.(newer_run(key), [asc: :ran_at, asc: :id], limit)
  defp run_page_rows(nil, read, limit), do: read.(dynamic(true), @newest_run_first, limit)

  # Reading older: more below when the page overflowed. Reading newer: more
  # above when it overflowed, and below whatever the page came from.
  defp older_runs?({:newer, _}, _more?, below?), do: below?.()
  defp older_runs?(_cursor, more?, _below?), do: more?

  defp newer_runs?({:newer, _}, more?, _above?), do: more?
  defp newer_runs?({:older, _}, _more?, above?), do: above?.()
  defp newer_runs?(nil, _more?, _above?), do: false

  defp read_run_page(project_id, scope, opts, keyset, order, limit) do
    ClickHouseRepo.all(
      from(r in subquery(run_page_query(project_id, scope, opts)),
        where: ^keyset,
        order_by: ^order,
        limit: ^limit
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  # One row per run, however many times it was written; the period and the
  # subject narrow the rows before they are grouped, along the table's order.
  defp run_page_query(project_id, scope, opts) do
    from(t in Test,
      where: t.project_id == ^project_id and t.id in subquery(covered_runs_query(project_id, scope, opts)),
      group_by: t.id,
      select: %{id: t.id, ran_at: min(t.ran_at), git_dirty: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at)}
    )
    |> run_dirty(Keyword.get(opts, :dirty, false))
    |> run_scope(scope)
    |> run_period(opts)
    |> run_scheme(Keyword.get(opts, :search, ""), Keyword.get(opts, :scheme))
  end

  # The runs whose coverage counts: totals with executable lines, published
  # no earlier than the period starts, since a run's coverage lands after it.
  defp covered_runs_query(project_id, scope, opts) do
    query =
      from(c in CoverageRun,
        where: c.project_id == ^project_id,
        group_by: c.test_run_id,
        having: fragment("argMax(?, ?)", c.executable_lines, c.version) > 0,
        select: c.test_run_id
      )

    query =
      case {scope, Keyword.get(opts, :since)} do
        {{:commit, sha}, _since} -> where(query, [c], c.git_commit_sha == ^sha)
        {_scope, nil} -> query
        {_scope, since} -> where(query, [c], c.inserted_at >= ^since)
      end

    case Keyword.get(opts, :partial) do
      nil -> query
      partial -> having(query, [c], fragment("argMax(?, ?)", c.partial, c.version) == ^partial)
    end
  end

  defp run_scope(query, {:commit, sha}), do: where(query, [t], t.git_commit_sha == ^sha)
  defp run_scope(query, {:branch, branch}), do: where(query, [t], t.git_branch == ^branch)

  defp run_dirty(query, true), do: query
  defp run_dirty(query, false), do: having(query, [t], fragment("argMax(?, ?)", t.git_dirty, t.inserted_at) == false)

  defp run_period(query, opts) do
    query = if since = Keyword.get(opts, :since), do: where(query, [t], t.ran_at >= ^since), else: query
    if until = Keyword.get(opts, :until), do: where(query, [t], t.ran_at <= ^until), else: query
  end

  defp run_scheme(query, search, scheme) do
    query =
      if search == "",
        do: query,
        else: where(query, [t], fragment("positionCaseInsensitiveUTF8(?, ?) > 0", t.scheme, ^search))

    case scheme do
      {:==, name} -> where(query, [t], t.scheme == ^name)
      {:!=, name} -> where(query, [t], t.scheme != ^name)
      nil -> query
    end
  end

  defp older_run({at, id}), do: dynamic([r], r.ran_at < ^at or (r.ran_at == ^at and r.id < ^id))
  defp newer_run({at, id}), do: dynamic([r], r.ran_at > ^at or (r.ran_at == ^at and r.id > ^id))

  defp run_key(row), do: {row.ran_at, row.id}

  defp run_cursor(opts) do
    case {Keyword.get(opts, :after), Keyword.get(opts, :before)} do
      {value, _} when value not in [nil, ""] -> decode_run_cursor(:older, value)
      {_, value} when value not in [nil, ""] -> decode_run_cursor(:newer, value)
      _ -> nil
    end
  end

  defp encode_run_cursor({at, id}), do: "#{at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)}-#{id}"

  defp decode_run_cursor(direction, value) do
    with [micros, id] <- String.split(value, "-", parts: 2),
         {micros, ""} <- Integer.parse(micros),
         {:ok, at} <- DateTime.from_unix(micros, :microsecond),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {direction, {DateTime.to_naive(at), id}}
    else
      _ -> nil
    end
  end

  # The page's runs with their totals, read by run id along the totals'
  # order.
  defp with_run_totals(_project_id, []), do: []

  defp with_run_totals(project_id, rows) do
    ids = Enum.map(rows, & &1.id)

    totals =
      project_id
      |> Coverage.run_totals_query()
      |> where([c], c.test_run_id in ^ids)
      |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
      |> Map.new(&{&1.test_run_id, &1})

    Enum.flat_map(rows, fn row ->
      case Map.get(totals, row.id) do
        nil -> []
        total -> [Map.merge(total, %{ran_at: row.ran_at, git_dirty: row.git_dirty})]
      end
    end)
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
  defp unmeasured_paths(_project, %{git_repository_id: repository_id}, _excluded) when repository_id in [nil, 0], do: []

  defp unmeasured_paths(project, %{git_repository_id: repository_id, git_commit_sha: sha} = commit, excluded) do
    if GitHistory.listing_complete?(repository_id, sha) do
      measured = project.id |> report_paths(commit.test_run_ids) |> MapSet.new()
      measured = MapSet.union(measured, MapSet.new(Reported.unbuilt_paths(project, commit, measured, excluded)))

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
  defp report_paths(_project_id, []), do: []

  defp report_paths(project_id, run_ids) do
    ClickHouseRepo.all(
      from(f in Coverage.report_files_for_runs(project_id, run_ids), distinct: true, select: f.path),
      settings: [select_sequential_consistency: 1]
    )
  end

  @doc "The commit's files with the runs' reports merged, without line data, by path."
  def merged_files(project_id, sha, opts \\ []) do
    settings = if Keyword.get(opts, :consistent, false), do: [settings: [select_sequential_consistency: 1]], else: []

    case run_ids(project_id, sha) do
      [] -> []
      ids -> ClickHouseRepo.all(from(f in subquery(merged_query(project_id, ids, opts)), order_by: f.path), settings)
    end
  end

  defp merged_query(project_id, ids, opts),
    do: Coverage.merged_files_query_for_runs(project_id, ids, Coverage.excluded(project_id, opts))

  @doc """
  The commit's targets with their file count and line totals, least covered
  first. On a commit whose skipped tests were all carried forward they are
  over its reported coverage, as its files are (`measured: true` keeps to
  what its runs measured). A complete commit's are read as stored
  (`Tuist.Tests.Coverage.Deltas.targets/2`) when they are current.
  """
  def targets(project_id, sha, opts \\ []) do
    with true <- deltas?(project_id, opts),
         targets when is_list(targets) <- Deltas.targets(project_id, sha) do
      targets
    else
      _ ->
        case carried_files(project_id, sha, opts) do
          nil -> measured_targets(project_id, sha, opts)
          files -> targets_of(files)
        end
    end
  end

  # A complete commit's figures are stored (`Tuist.Tests.Coverage.Deltas`)
  # as the pages show them: carried coverage applied, the project's excluded
  # paths left out. Other readings, commits whose stored figures are not
  # current, and `stored: false` read the runs' rows.
  defp deltas?(project_id, opts),
    do:
      Keyword.get(opts, :stored, true) and not Keyword.get(opts, :measured, false) and
        Coverage.excluded(project_id, opts) == ExcludedPaths.pattern_for_project(project_id)

  @doc false
  def targets_of(files) do
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
  One page of the commit's files and the number of files; over its reported
  coverage on a commit whose skipped tests were all carried forward, as
  `targets/3`. `search:` keeps the paths containing it, ignoring case, and
  `sort:` orders them as `{:coverage | :path, :asc | :desc}`, least covered
  first by default. A complete commit's files are read from their stored
  deltas (`Tuist.Tests.Coverage.Deltas.list_files/5`) when they are current.
  """
  def list_files(project_id, sha, page, page_size, opts \\ []) do
    with true <- deltas?(project_id, opts),
         {_files, _count} = listed <- Deltas.list_files(project_id, sha, page, page_size, opts) do
      listed
    else
      _ -> list_raw_files(project_id, sha, page, page_size, opts)
    end
  end

  defp list_raw_files(project_id, sha, page, page_size, opts) do
    case carried_files(project_id, sha, opts) do
      nil ->
        list_measured_files(project_id, sha, page, page_size, opts)

      files ->
        files = Enum.filter(files, &path_matches?(&1.path, Keyword.get(opts, :search, "")))
        {files |> sort_files(files_sort(opts)) |> Enum.slice((page - 1) * page_size, page_size), length(files)}
    end
  end

  @doc """
  The files whose coverage moved most from `from_sha` to `to_sha`, at most
  `count`: those with executable lines at both commits whose percentage
  changed, the biggest change in percentage points first and, among equal
  ones, the bigger change in covered lines. Each carries its figures at
  `to_sha`, its figures at `from_sha` (`previous_covered_lines`,
  `previous_executable_lines`) and `change`, in percentage points. Read as
  `list_files/5` reads a commit's files: in ClickHouse, keeping only the
  top of the list, unless coverage was carried into either commit, whose
  files are then compared here. Two complete commits whose stored deltas are
  current are compared over those instead
  (`Tuist.Tests.Coverage.Deltas.changed_files/4`), carried coverage included.
  """
  def changed_files(project_id, from_sha, to_sha, count, opts \\ []) do
    with true <- deltas?(project_id, opts),
         changed when is_list(changed) <- Deltas.changed_files(project_id, from_sha, to_sha, count) do
      changed
    else
      _ -> raw_changed_files(project_id, from_sha, to_sha, count, opts)
    end
  end

  defp raw_changed_files(project_id, from_sha, to_sha, count, opts) do
    excluded = Coverage.excluded(project_id, opts)
    opts = Keyword.put(opts, :excluded, excluded)

    if carried_commit?(project_id, from_sha, opts) or carried_commit?(project_id, to_sha, opts) do
      before = Map.new(final_files(project_id, from_sha, opts), &{&1.path, &1})

      project_id
      |> final_files(to_sha, opts)
      |> Enum.flat_map(fn file ->
        case Map.get(before, file.path) do
          %{executable_lines: executable} = previous when executable > 0 and file.executable_lines > 0 ->
            [file_change(file, previous.covered_lines, previous.executable_lines)]

          _ ->
            []
        end
      end)
      |> Enum.reject(&(&1.change == 0.0))
      |> Enum.sort_by(&{-abs(&1.change), -abs(&1.covered_lines - &1.previous_covered_lines), &1.path})
      |> Enum.take(count)
    else
      measured_changed_files(project_id, run_ids(project_id, from_sha), run_ids(project_id, to_sha), count, excluded)
    end
  end

  @doc """
  The targets whose coverage moved most from `from_sha` to `to_sha`, at most
  `count`, as `changed_files/5` ranks files: those with executable lines at
  both commits, each as `targets/3` gives it at `to_sha`, with its figures at
  `from_sha` (`previous_covered_lines`, `previous_executable_lines`) and
  `change`, in percentage points. A commit has tens of targets, hundreds at
  most, so both are read whole and compared here.
  """
  def changed_targets(project_id, from_sha, to_sha, count, opts \\ []) do
    opts = Keyword.put(opts, :excluded, Coverage.excluded(project_id, opts))

    [before, current] =
      Tuist.Tasks.parallel_tasks([
        fn -> targets(project_id, from_sha, opts) end,
        fn -> targets(project_id, to_sha, opts) end
      ])

    before = Map.new(before, &{&1.name, &1})

    current
    |> Enum.flat_map(fn target ->
      case Map.get(before, target.name) do
        %{executable_lines: executable} = previous when executable > 0 and target.executable_lines > 0 ->
          [
            Map.merge(target, %{
              previous_covered_lines: previous.covered_lines,
              previous_executable_lines: executable,
              change: change(target, previous.covered_lines, executable)
            })
          ]

        _ ->
          []
      end
    end)
    |> Enum.reject(&(&1.change == 0.0))
    |> Enum.sort_by(&{-abs(&1.change), -abs(&1.covered_lines - &1.previous_covered_lines), &1.name})
    |> Enum.take(count)
  end

  defp carried_commit?(project_id, sha, opts) do
    not Keyword.get(opts, :measured, false) and
      case summary(project_id, sha) do
        nil -> false
        summary -> carried?(summary)
      end
  end

  @doc """
  The commit's files as its pages show them, by path: what its runs measured
  or, when coverage was carried into it (`carried?/1`), with that coverage
  applied, as `list_files/5` reads them. `consistent: true` reads the runs'
  rows as of every write so far (`select_sequential_consistency`).
  """
  def final_files(project_id, sha, opts \\ []),
    do:
      carried_files(project_id, sha, opts) || merged_files(project_id, sha, Keyword.take(opts, [:excluded, :consistent]))

  defp measured_changed_files(_project_id, [], _to_ids, _count, _excluded), do: []
  defp measured_changed_files(_project_id, _from_ids, [], _count, _excluded), do: []

  defp measured_changed_files(project_id, from_ids, to_ids, count, excluded) do
    from(n in subquery(Coverage.merged_files_query_for_runs(project_id, to_ids, excluded)),
      join: o in subquery(Coverage.merged_files_query_for_runs(project_id, from_ids, excluded)),
      on: o.path == n.path,
      where: n.executable_lines > 0 and o.executable_lines > 0,
      where:
        fragment(
          "round(? / ? * 100, 1) != round(? / ? * 100, 1)",
          n.covered_lines,
          n.executable_lines,
          o.covered_lines,
          o.executable_lines
        ),
      order_by: [
        desc: fragment("abs(? / ? - ? / ?)", n.covered_lines, n.executable_lines, o.covered_lines, o.executable_lines),
        desc: fragment("abs(toInt64(?) - toInt64(?))", n.covered_lines, o.covered_lines),
        asc: n.path
      ],
      limit: ^count,
      select: %{
        path: n.path,
        covered_lines: n.covered_lines,
        executable_lines: n.executable_lines,
        previous_covered_lines: o.covered_lines,
        previous_executable_lines: o.executable_lines
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&file_change(&1, &1.previous_covered_lines, &1.previous_executable_lines))
  end

  defp file_change(file, previous_covered, previous_executable) do
    %{
      path: file.path,
      covered_lines: file.covered_lines,
      executable_lines: file.executable_lines,
      previous_covered_lines: previous_covered,
      previous_executable_lines: previous_executable,
      change: change(file, previous_covered, previous_executable)
    }
  end

  defp change(row, previous_covered, previous_executable),
    do:
      Float.round(
        Coverage.percentage(row.covered_lines, row.executable_lines) -
          Coverage.percentage(previous_covered, previous_executable),
        1
      )

  # The files of a commit whose reported coverage is exact, or nil: what the
  # lists read instead of the measured files, so a file only a skipped test
  # covers is not listed as uncovered.
  defp carried_files(project_id, sha, opts) do
    with false <- Keyword.get(opts, :measured, false),
         %{} = summary <- summary(project_id, sha),
         true <- carried?(summary),
         %Project{} = project <- Tuist.Projects.get_project_by_id(project_id) do
      excluded = Coverage.excluded(project_id, opts)
      measured = merged_files(project_id, sha, excluded: excluded, consistent: Keyword.get(opts, :consistent, false))
      Reported.merged_files(project, sha, measured, excluded: excluded)
    else
      _ -> nil
    end
  end

  @doc """
  Whether coverage was carried into the commit's exact figure: a run skipped
  tests, a scheme was skipped whole, or files no run compiled were kept from
  an ancestor. Its files are then read with what was carried into them
  (`file_detail/4`), not only with what its runs measured, so its lists add
  up to its figure.
  """
  def carried?(%{reported_kind: "reported"} = summary) do
    summary.partial_schemes != [] or Map.get(summary, :carried_tests_count, 0) > 0 or
      {summary.reported_covered_lines, summary.reported_executable_lines} !=
        {summary.covered_lines, summary.executable_lines}
  end

  def carried?(_summary), do: false

  defp files_sort(opts), do: Keyword.get(opts, :sort, {:coverage, :asc})

  defp path_matches?(_path, ""), do: true
  defp path_matches?(path, search), do: path |> String.downcase() |> String.contains?(String.downcase(search))

  defp sort_files(files, {:path, direction}), do: Enum.sort_by(files, & &1.path, direction)

  defp sort_files(files, {:coverage, direction}),
    do: Enum.sort_by(files, &{&1.covered_lines / max(&1.executable_lines, 1), &1.path}, direction)

  defp list_measured_files(project_id, sha, page, page_size, opts) do
    case run_ids(project_id, sha) do
      [] ->
        {[], 0}

      ids ->
        files_query =
          project_id
          |> Coverage.merged_files_query_for_runs(ids, Coverage.excluded(project_id, opts))
          |> subquery()
          |> search_paths(Keyword.get(opts, :search, ""))

        [files, count] =
          Tuist.Tasks.parallel_tasks([
            fn ->
              ClickHouseRepo.all(
                from(f in files_query,
                  order_by: ^files_order(files_sort(opts)),
                  limit: ^page_size,
                  offset: ^((page - 1) * page_size)
                )
              )
            end,
            fn -> ClickHouseRepo.one(from(f in files_query, select: count(f.path))) || 0 end
          ])

        {files, count}
    end
  end

  @doc false
  def search_paths(query, ""), do: from(f in query)

  def search_paths(query, search),
    do: from(f in query, where: fragment("positionCaseInsensitiveUTF8(?, ?) > 0", f.path, ^search))

  @doc false
  def files_order({:path, direction}), do: [{direction, dynamic([f], f.path)}]

  def files_order({:coverage, direction}),
    do: [
      {direction, dynamic([f], fragment("? / greatest(?, 1)", f.covered_lines, f.executable_lines))},
      {direction, dynamic([f], f.path)}
    ]

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
  One file's merged coverage at the commit (`Tuist.Tests.Coverage.detail/2`
  over its runs' rows), or nil. On a commit
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

  @doc """
  The rows the given runs' latest reports hold for a product file, newest
  first: what `Tuist.Tests.Coverage.detail/2` merges. The runs are read in
  chunks, since each one binds a parameter twice.
  """
  def file_rows(_project_id, [], _path), do: []

  def file_rows(project_id, ids, path) do
    ids
    |> Coverage.id_chunks(div(900, 2))
    |> Enum.flat_map(fn chunk ->
      ClickHouseRepo.all(
        from(f in Coverage.report_files_for_runs(project_id, chunk),
          where: f.path == ^path and not f.is_test,
          order_by: [desc: f.inserted_at]
        )
      )
    end)
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
      functions: Coverage.cover_functions(detail.functions, effective)
    })
  end
end
