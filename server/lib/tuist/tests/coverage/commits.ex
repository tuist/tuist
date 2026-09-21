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
  reports and on the signal, one version above the latest.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.Gates
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

  def enqueue_recompute(_project_id, sha) when sha in [nil, ""], do: :skipped
  def enqueue_recompute(project_id, sha), do: CommitWorker.enqueue(project_id, sha)

  @doc """
  Republishes the commit's totals from its runs' retained reports and
  returns the row published, or nil when no run measured the commit.
  `complete:` and `completeness:` set the completion state; without them the
  state already published is kept.
  """
  def recompute(%Project{} = project, sha, opts \\ []) do
    runs = runs(project.id, sha)
    previous = summary(project.id, sha)

    if runs == [] do
      nil
    else
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
      reported = project |> Reported.compute(sha, runs: runs, excluded: excluded) |> Map.drop([:files, :carried_lines])

      row = %{
        project_id: project.id,
        git_commit_sha: sha,
        git_repository_id: repository_id,
        build_system: runs |> hd() |> Map.fetch!(:build_system),
        covered_lines: totals.covered_lines,
        executable_lines: totals.executable_lines,
        measured_files_count: totals.measured_files_count,
        unmeasured_files_count: unmeasured_files_count(project.id, repository_id, sha, run_ids, excluded),
        schemes: schemes,
        partial_schemes: partial_schemes,
        test_run_ids: run_ids,
        reported_covered_lines: reported.covered_lines,
        reported_executable_lines: reported.executable_lines,
        reported_kind: reported.kind,
        skipped_tests_count: reported.skipped_tests_count,
        carried_tests_count: reported.carried_tests_count,
        gap_files_count: reported.gap_files_count,
        carried_from: reported.carried_from,
        complete: Keyword.get(opts, :complete, (previous && previous.complete) || false),
        completeness: Keyword.get(opts, :completeness, (previous && previous.completeness) || ""),
        version: next_version(previous),
        inserted_at: (previous && previous.inserted_at) || NaiveDateTime.utc_now()
      }

      IngestRepo.insert_all(CoverageCommit, [row])
      with_percentages(row)
    end
  end

  @doc """
  Records that the commit's coverage pipeline finished, republishing its
  totals as complete. Returns the row, or nil when no run measured the
  commit yet (the signal is then recorded on the next recompute).
  """
  def signal_complete(%Project{} = project, sha) do
    row = recompute(project, sha, complete: true, completeness: "signal")
    if row, do: Gates.enqueue_signal(project, sha)
    row
  end

  # A version above the latest published, so a republish always wins, and
  # never below the clock, so two publishers racing on a fresh commit still
  # order by time.
  defp next_version(previous) do
    now = NaiveDateTime.diff(NaiveDateTime.utc_now(), ~N[1970-01-01 00:00:00], :microsecond)
    if previous, do: max(previous.version + 1, now), else: now
  end

  @doc "The published totals of a commit, with the measured set, or nil."
  def summary(project_id, sha) do
    from(c in CoverageCommit,
      where: c.project_id == ^project_id and c.git_commit_sha == ^sha,
      group_by: c.git_commit_sha,
      select: %{
        git_commit_sha: c.git_commit_sha,
        git_repository_id: fragment("argMax(?, ?)", c.git_repository_id, c.version),
        build_system: fragment("argMax(?, ?)", c.build_system, c.version),
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
        measured_files_count: fragment("argMax(?, ?)", c.measured_files_count, c.version),
        unmeasured_files_count: fragment("argMax(?, ?)", c.unmeasured_files_count, c.version),
        schemes: fragment("argMax(?, ?)", c.schemes, c.version),
        partial_schemes: fragment("argMax(?, ?)", c.partial_schemes, c.version),
        test_run_ids: type(fragment("argMax(?, ?)", c.test_run_ids, c.version), {:array, Ecto.UUID}),
        reported_covered_lines: fragment("argMax(?, ?)", c.reported_covered_lines, c.version),
        reported_executable_lines: fragment("argMax(?, ?)", c.reported_executable_lines, c.version),
        reported_kind: fragment("argMax(?, ?)", c.reported_kind, c.version),
        skipped_tests_count: fragment("argMax(?, ?)", c.skipped_tests_count, c.version),
        carried_tests_count: fragment("argMax(?, ?)", c.carried_tests_count, c.version),
        gap_files_count: fragment("argMax(?, ?)", c.gap_files_count, c.version),
        carried_from: fragment("argMax(?, ?)", c.carried_from, c.version),
        complete: fragment("argMax(?, ?)", c.complete, c.version),
        completeness: fragment("argMax(?, ?)", c.completeness, c.version),
        version: max(c.version),
        inserted_at: fragment("argMax(?, ?)", c.inserted_at, c.version)
      }
    )
    |> ClickHouseRepo.one(settings: [select_sequential_consistency: 1])
    |> case do
      nil -> nil
      row -> with_percentages(row)
    end
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

  @doc "The published totals of a head (`Tuist.Tests.Coverage.Comparison.from_commit/2`), or nil."
  def summary_for(%{sha: sha, project_id: project_id}), do: summary(project_id, sha)
  def summary_for(_head), do: nil

  @doc """
  The project's published commits, one row per commit with the latest
  version's fields: what the history and the baselines read.
  """
  def commits_query(project_id) do
    from(c in CoverageCommit,
      where: c.project_id == ^project_id,
      group_by: c.git_commit_sha,
      having: fragment("argMax(?, ?)", c.executable_lines, c.version) > 0,
      select: %{
        git_commit_sha: c.git_commit_sha,
        git_repository_id: fragment("argMax(?, ?)", c.git_repository_id, c.version),
        build_system: fragment("argMax(?, ?)", c.build_system, c.version),
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
        measured_files_count: fragment("argMax(?, ?)", c.measured_files_count, c.version),
        unmeasured_files_count: fragment("argMax(?, ?)", c.unmeasured_files_count, c.version),
        schemes: fragment("argMax(?, ?)", c.schemes, c.version),
        partial_schemes: fragment("argMax(?, ?)", c.partial_schemes, c.version),
        test_run_ids: type(fragment("argMax(?, ?)", c.test_run_ids, c.version), {:array, Ecto.UUID}),
        reported_covered_lines: fragment("argMax(?, ?)", c.reported_covered_lines, c.version),
        reported_executable_lines: fragment("argMax(?, ?)", c.reported_executable_lines, c.version),
        reported_kind: fragment("argMax(?, ?)", c.reported_kind, c.version),
        skipped_tests_count: fragment("argMax(?, ?)", c.skipped_tests_count, c.version),
        carried_tests_count: fragment("argMax(?, ?)", c.carried_tests_count, c.version),
        gap_files_count: fragment("argMax(?, ?)", c.gap_files_count, c.version),
        carried_from: fragment("argMax(?, ?)", c.carried_from, c.version),
        complete: fragment("argMax(?, ?)", c.complete, c.version),
        completeness: fragment("argMax(?, ?)", c.completeness, c.version),
        inserted_at: fragment("argMax(?, ?)", c.inserted_at, c.version)
      }
    )
  end

  @doc """
  The runs that measured the commit and count towards it: one row per run
  with its scheme, whether it was partial, and its repository. Runs from a
  dirty checkout are left out.
  """
  def runs(project_id, sha) when is_binary(sha), do: runs(project_id, [sha])

  def runs(_project_id, []), do: []

  def runs(project_id, shas) when is_list(shas) do
    runs =
      from(t in Test,
        where: t.project_id == ^project_id and t.git_commit_sha in ^shas,
        group_by: t.id,
        select: %{
          id: t.id,
          scheme: fragment("any(?)", t.scheme),
          build_system: fragment("any(?)", t.build_system),
          git_commit_sha: fragment("any(?)", t.git_commit_sha),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          git_dirty: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at),
          ran_at: min(t.ran_at)
        }
      )

    ClickHouseRepo.all(
      from(c in subquery(Coverage.run_totals_query(project_id)),
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

  @doc "The commit's files with the runs' reports merged, without line data, by path."
  def merged_files(project_id, sha, opts \\ []) do
    case run_ids(project_id, sha) do
      [] ->
        []

      ids ->
        ClickHouseRepo.all(
          from(f in subquery(Coverage.merged_files_query_for_runs(project_id, ids, Coverage.excluded(project_id, opts))),
            order_by: f.path
          )
        )
    end
  end

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
         %{reported_kind: "reported", partial_schemes: [_ | _]} <- summary(project_id, sha),
         %Project{} = project <- Tuist.Projects.get_project_by_id(project_id) do
      excluded = Coverage.excluded(project_id, opts)
      Reported.merged_files(project, sha, merged_files(project_id, sha, excluded: excluded), excluded: excluded)
    else
      _ -> nil
    end
  end

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
         %{reported_kind: "reported", partial_schemes: [_ | _]} <- summary(project_id, sha),
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
