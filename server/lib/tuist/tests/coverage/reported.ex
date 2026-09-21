defmodule Tuist.Tests.Coverage.Reported do
  @moduledoc """
  A commit's **reported** coverage: what its runs observed plus the coverage
  carried forward for the tests they skipped.

  A selective run measures less than the commit is covered by: the tests it
  skipped would have covered lines too. The run's client lists every
  candidate test (`Tuist.Tests.Enumeration`), so the skipped ones are known,
  and per-test evidence (`Tuist.Tests.Coverage.Evidence`) says which lines
  each of them ran the last time it executed. That coverage is carried
  forward only when it provably still applies:

  - the evidence comes from an ancestor of the commit, from a run on a clean
    checkout, and the nearest such ancestor wins;
  - the test passed in that run;
  - every file the test executed there, and every file its suite's setup
    executed, has the same blob at the commit, and so does every tracked file
    of the project;
  - the evidence holds lines, not only files, for every file that counts.

  A skipped test that fails any of these is a **gap**: nothing is carried for
  it and the figure is a lower bound, which `kind` says (`partial`). Files an
  ancestor measured that no run at the commit compiled keep their executable
  lines when their blob is unchanged, so a run that built half the project is
  compared over the whole of it; one whose blob changed is a gap too.

  Carried coverage always chains back to a run in which the test really
  executed: evidence rows exist only where tests ran, so an estimate is never
  carried from an estimate.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.EnumeratedTest
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun

  @chunk_size 2_000

  @doc """
  The commit's reported coverage, or nil when no run measured it.

  `kind` is `measured` when the runs skipped nothing, `reported` when every
  skipped test was carried and no file is left out, `partial` when gaps
  remain, and `observed` when the runs' clients listed no candidates, so what
  was skipped cannot be told and the figure is the observed one.
  """
  def compute(%Project{} = project, sha, opts \\ []) do
    runs = Keyword.get_lazy(opts, :runs, fn -> Commits.runs(project.id, sha) end)

    if runs == [] do
      nil
    else
      excluded = Keyword.get_lazy(opts, :excluded, fn -> ExcludedPaths.pattern_for_project(project) end)
      run_ids = Enum.map(runs, & &1.test_run_id)
      observed = observed_files(project.id, run_ids, excluded)

      repository_id = runs |> Enum.map(& &1.git_repository_id) |> Enum.max()
      schemes = runs |> Enum.map(& &1.scheme) |> Enum.uniq()

      case skipped_tests(project, repository_id, sha, run_ids, schemes) do
        :not_enumerated ->
          result(observed, "observed", [], [], 0, [])

        [] ->
          result(observed, "measured", [], [], 0, [])

        skipped ->
          carry(project, repository_id, sha, {run_ids, schemes}, observed, skipped, excluded)
      end
    end
  end

  defp carry(project, repository_id, sha, {run_ids, schemes}, observed, skipped, excluded) do
    context = %{
      project: project,
      repository_id: repository_id,
      sha: sha,
      observed: observed,
      blobs: run_blobs(project.id, run_ids),
      excluded: ExcludedPaths.compile(excluded)
    }

    {carried_tests, carried_lines, sources} = carried(context, skipped)

    {files, gap_files} =
      observed
      |> add_carried_lines(context, run_ids, carried_lines, sources)
      |> add_unbuilt_files(context, schemes)

    kind = if length(carried_tests) == length(skipped) and gap_files == 0, do: "reported", else: "partial"
    shas = sources |> Map.values() |> Enum.map(& &1.sha) |> Enum.uniq() |> Enum.sort()
    files |> result(kind, skipped, carried_tests, gap_files, shas) |> Map.put(:carried_lines, carried_lines)
  end

  @doc """
  The commit's files with their reported line totals, by path, as
  `Tuist.Tests.Coverage.Commits.merged_files/3` lists the measured ones: what
  the comparison reads when the commit's reported coverage is exact, so its
  targets and files compare as a full run's would. `measured` are the
  commit's measured files; a file only an ancestor compiled takes its targets
  from there.
  """
  def merged_files(%Project{} = project, sha, measured, opts \\ []) do
    case compute(project, sha, opts) do
      %{kind: "reported", files: files} ->
        by_path = Map.new(measured, &{&1.path, &1})

        files
        |> Enum.map(fn {path, file} ->
          by_path
          |> Map.get(path, %{path: path, targets: Map.get(file, :targets, [])})
          |> Map.merge(Map.take(file, [:git_blob_id, :covered_lines, :executable_lines]))
        end)
        |> Enum.sort_by(& &1.path)

      _ ->
        measured
    end
  end

  @doc """
  One file of a commit whose skipped tests were all carried forward: the
  lines carried into it (those no run at the commit covered itself), and,
  for a file no run at the commit compiled, the runs its executable lines are
  read from. Nil when the commit's reported coverage is not exact or the file
  is not part of it.
  """
  def file(%Project{} = project, sha, path, opts \\ []) do
    case compute(project, sha, opts) do
      %{kind: "reported", files: %{^path => file}} = reported ->
        %{
          carried_lines: reported.carried_lines |> Map.get(path, MapSet.new()) |> Enum.sort(),
          source_run_ids: Map.get(file, :source_run_ids, [])
        }

      _ ->
        nil
    end
  end

  defp result(files, kind, skipped, carried_tests, gap_files, shas) do
    %{
      files: files,
      carried_lines: %{},
      kind: kind,
      covered_lines: files |> Map.values() |> Enum.map(& &1.covered_lines) |> Enum.sum(),
      executable_lines: files |> Map.values() |> Enum.map(& &1.executable_lines) |> Enum.sum(),
      skipped_tests_count: length(skipped),
      carried_tests_count: length(carried_tests),
      gap_files_count: gap_files,
      carried_from: shas
    }
  end

  # The files the commit's runs measured, by path, as the commit's own totals
  # count them.
  defp observed_files(project_id, run_ids, excluded) do
    from(f in subquery(Coverage.merged_files_query_for_runs(project_id, run_ids, excluded)),
      select:
        {f.path, %{git_blob_id: f.git_blob_id, covered_lines: f.covered_lines, executable_lines: f.executable_lines}}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Map.new()
  end

  # The blob of every file the commit's runs reported, test code included.
  defp run_blobs(project_id, run_ids) do
    from(f in Coverage.report_files_for_runs(project_id, run_ids),
      where: f.git_blob_id != "",
      group_by: f.path,
      select: {f.path, fragment("any(?)", f.git_blob_id)}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Map.new()
  end

  # The enabled candidates of the commit's runs that none of them executed.
  defp skipped_tests(project, repository_id, sha, run_ids, schemes) do
    candidates =
      Enum.uniq_by(
        enumerated(project.id, run_ids) ++ inherited_candidates(project, repository_id, sha, run_ids, schemes),
        & &1.test_case_id
      )

    if candidates == [] do
      :not_enumerated
    else
      ran =
        from(r in TestCaseRun,
          where: r.project_id == ^project.id and r.test_run_id in ^run_ids and not is_nil(r.test_case_id),
          distinct: true,
          select: r.test_case_id
        )
        |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
        |> MapSet.new()

      Enum.reject(candidates, &MapSet.member?(ran, &1.test_case_id))
    end
  end

  defp enumerated(_project_id, []), do: []

  defp enumerated(project_id, run_ids) do
    ClickHouseRepo.all(
      from(e in EnumeratedTest,
        where: e.project_id == ^project_id and e.test_run_id in ^run_ids,
        group_by: e.test_case_id,
        having: fragment("argMax(?, ?)", e.enabled, e.inserted_at),
        select: %{
          test_case_id: e.test_case_id,
          module_name: fragment("argMax(?, ?)", e.module_name, e.inserted_at),
          suite_name: fragment("argMax(?, ?)", e.suite_name, e.inserted_at),
          name: fragment("argMax(?, ?)", e.name, e.inserted_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  # A scheme selective testing skipped entirely never builds, so its run
  # carries no coverage and its client lists no candidates: nothing at the
  # commit says those tests exist, let alone that they were skipped. Their
  # candidates come from the nearest ancestor run of the same scheme, which
  # is where their evidence comes from anyway. Every other guard still
  # applies to each of them, so a test that must not be carried is still a
  # gap rather than a silent omission.
  defp silent_schemes(project_id, sha, run_ids, schemes) do
    measured = MapSet.new(schemes)

    from(t in Test,
      where: t.project_id == ^project_id and t.git_commit_sha == ^sha and t.git_dirty == false,
      distinct: true,
      select: %{id: t.id, scheme: t.scheme}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Enum.reject(&(&1.scheme in [nil, ""] or MapSet.member?(measured, &1.scheme) or &1.id in run_ids))
    |> Enum.map(& &1.scheme)
    |> Enum.uniq()
  end

  defp inherited_candidates(_project, repository_id, _sha, _run_ids, _schemes) when repository_id in [nil, 0], do: []

  defp inherited_candidates(project, repository_id, sha, run_ids, schemes) do
    case silent_schemes(project.id, sha, run_ids, schemes) do
      [] -> []
      silent -> inherit(project, repository_id, sha, silent)
    end
  end

  defp inherit(project, repository_id, sha, silent) do
    depths =
      repository_id
      |> GitHistory.ancestors(sha)
      |> Enum.reject(fn {_sha, depth} -> depth == 0 end)
      |> Map.new()

    wanted = MapSet.new(silent)

    project.id
    |> Commits.runs(Map.keys(depths))
    |> Enum.filter(&MapSet.member?(wanted, &1.scheme))
    |> Enum.group_by(& &1.scheme)
    |> Enum.flat_map(fn {_scheme, scheme_runs} ->
      scheme_runs
      |> Enum.sort_by(&source_rank(%{depth: depths[&1.git_commit_sha], ran_at: &1.ran_at}))
      |> Enum.find_value([], fn run ->
        case enumerated(project.id, [run.test_run_id]) do
          [] -> nil
          candidates -> candidates
        end
      end)
    end)
  end

  # The skipped tests whose coverage still applies, the lines they carry per
  # path, and per path the run the lines came from.
  defp carried(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}, %{}}

  defp carried(context, skipped) do
    depths =
      context.repository_id
      |> GitHistory.ancestors(context.sha)
      |> Enum.reject(fn {_sha, depth} -> depth == 0 end)
      |> Map.new()

    source_runs =
      context.project.id
      |> Commits.runs(Map.keys(depths))
      |> Map.new(&{&1.test_run_id, %{sha: &1.git_commit_sha, depth: depths[&1.git_commit_sha], ran_at: &1.ran_at}})

    tests = Map.new(skipped, &{Evidence.test_scope_id(&1.module_name, &1.suite_name, &1.name), &1})
    rows = evidence_rows(context.project.id, Map.keys(tests), Map.keys(source_runs), "test")

    chosen =
      rows
      |> Enum.group_by(& &1.scope_id)
      |> Map.new(fn {scope_id, scope_rows} ->
        run_id = scope_rows |> Enum.map(& &1.test_run_id) |> Enum.uniq() |> Enum.min_by(&source_rank(source_runs[&1]))
        {scope_id, %{run_id: run_id, rows: Enum.filter(scope_rows, &(&1.test_run_id == run_id))}}
      end)

    passed = passed(context.project.id, tests, chosen)
    suites = suite_rows(context.project.id, tests, chosen)
    files = source_files(context.project.id, chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq())
    validity = validity_cache(context, source_runs)

    Enum.reduce(chosen, {[], %{}, %{}}, fn {scope_id, %{run_id: run_id, rows: test_rows}}, {kept, lines, sources} = acc ->
      test = tests[scope_id]
      all_rows = test_rows ++ Map.get(suites, {run_id, Evidence.suite_scope_id(test.module_name, test.suite_name)}, [])
      source = Map.put(source_runs[run_id], :run_id, run_id)

      if MapSet.member?(passed, {test.test_case_id, run_id}) and
           applies?(context, validity, source, all_rows, Map.get(files, run_id, %{})) do
        counted = Enum.filter(all_rows, &counted?(context, Map.get(files, run_id, %{}), &1.path))

        {[test | kept],
         Enum.reduce(counted, lines, fn row, lines ->
           Map.update(lines, row.path, MapSet.new(row.line_numbers), &MapSet.union(&1, MapSet.new(row.line_numbers)))
         end), Enum.reduce(counted, sources, fn row, sources -> Map.put_new(sources, row.path, source) end)}
      else
        acc
      end
    end)
  end

  defp source_rank(%{depth: depth, ran_at: ran_at}), do: {depth, -DateTime.to_unix(to_datetime(ran_at), :microsecond)}

  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  # Evidence rows of the given scopes in the given runs, each shard's latest
  # report only.
  defp evidence_rows(_project_id, [], _run_ids, _kind), do: []
  defp evidence_rows(_project_id, _scope_ids, [], _kind), do: []

  defp evidence_rows(project_id, scope_ids, run_ids, kind) do
    scope_ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn chunk ->
      ClickHouseRepo.all(
        from(f in CoverageFile,
          where:
            f.project_id == ^project_id and f.scope_kind == ^kind and f.scope_id in ^chunk and f.test_run_id in ^run_ids,
          select: %{
            test_run_id: f.test_run_id,
            shard_index: f.shard_index,
            scope_id: f.scope_id,
            path: f.path,
            line_numbers: f.line_numbers,
            inserted_at: f.inserted_at
          }
        )
      )
    end)
    |> Enum.group_by(&{&1.test_run_id, &1.shard_index, &1.scope_id})
    |> Enum.flat_map(fn {_key, shard_rows} ->
      latest = shard_rows |> Enum.map(& &1.inserted_at) |> Enum.max(NaiveDateTime)
      Enum.filter(shard_rows, &(NaiveDateTime.compare(&1.inserted_at, latest) == :eq))
    end)
  end

  defp suite_rows(project_id, tests, chosen) do
    suite_ids =
      tests
      |> Map.values()
      |> Enum.reject(&(&1.suite_name == ""))
      |> Enum.map(&Evidence.suite_scope_id(&1.module_name, &1.suite_name))
      |> Enum.uniq()

    run_ids = chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq()

    project_id
    |> evidence_rows(suite_ids, run_ids, "suite")
    |> Enum.group_by(&{&1.test_run_id, &1.scope_id})
  end

  defp passed(project_id, tests, chosen) do
    pairs =
      Enum.map(chosen, fn {scope_id, %{run_id: run_id}} -> {tests[scope_id].test_case_id, run_id} end)

    run_ids = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    pairs
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn chunk ->
      ClickHouseRepo.all(
        from(r in TestCaseRun,
          where:
            r.project_id == ^project_id and r.test_case_id in ^chunk and r.test_run_id in ^run_ids and
              r.status == "success",
          select: {r.test_case_id, r.test_run_id}
        )
      )
    end)
    |> MapSet.new()
  end

  # What each source run reported per path: the blob, whether it is test
  # code, and the executable lines.
  defp source_files(_project_id, []), do: %{}

  defp source_files(project_id, run_ids) do
    from(f in Coverage.report_files_for_runs(project_id, run_ids),
      select: %{
        test_run_id: f.test_run_id,
        path: f.path,
        git_blob_id: f.git_blob_id,
        is_test: f.is_test,
        line_numbers: f.line_numbers
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.group_by(& &1.test_run_id)
    |> Map.new(fn {run_id, rows} ->
      {run_id,
       rows
       |> Enum.group_by(& &1.path)
       |> Map.new(fn {path, path_rows} ->
         {path,
          %{
            git_blob_id: path_rows |> Enum.map(& &1.git_blob_id) |> Enum.find("", &(&1 != "")),
            is_test: Enum.all?(path_rows, & &1.is_test),
            line_numbers: path_rows |> Enum.flat_map(& &1.line_numbers) |> MapSet.new()
          }}
       end)}
    end)
  end

  # Tracked files are compared once per source commit.
  defp validity_cache(context, source_runs) do
    now = tracked(context, context.sha)

    source_runs
    |> Map.values()
    |> Enum.map(& &1.sha)
    |> Enum.uniq()
    |> Map.new(fn sha -> {sha, now != :unknown and tracked(context, sha) == now} end)
  end

  defp tracked(%{project: project, repository_id: repository_id}, sha) do
    cond do
      GitHistory.settings(project).tracked_file_globs == [] -> []
      GitHistory.listing_stored?(repository_id, sha) -> GitHistory.tracked_files(project, repository_id, sha)
      true -> :unknown
    end
  end

  defp applies?(context, validity, source, rows, source_files) do
    paths = rows |> Enum.map(& &1.path) |> Enum.uniq()

    validity[source.sha] and
      Enum.all?(rows, &(&1.line_numbers != [] or not counted?(context, source_files, &1.path))) and
      same_blobs?(context, source, paths, source_files)
  end

  defp counted?(context, source_files, path) do
    not ExcludedPaths.excluded?(context.excluded, path) and
      case Map.get(source_files, path) do
        %{is_test: is_test} -> not is_test
        nil -> false
      end
  end

  defp same_blobs?(context, source, paths, source_files) do
    now = blobs_now(context, paths)

    then_blobs =
      case Enum.reject(paths, &match?(%{git_blob_id: <<_, _::binary>>}, Map.get(source_files, &1))) do
        [] -> %{}
        missing -> GitHistory.blobs_at(context.repository_id, source.sha, missing)
      end

    Enum.all?(paths, fn path ->
      before = source_files |> get_in([path, :git_blob_id]) |> blank_to_nil() || Map.get(then_blobs, path)
      is_binary(before) and before != "" and Map.get(now, path) == before
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A path's blob at the commit: what a run measured says it, and the commit's
  # listing says it for the files no run compiled.
  defp blobs_now(context, paths) do
    {known, unknown} = Enum.split_with(paths, &Map.has_key?(context.blobs, &1))

    context.blobs
    |> Map.take(known)
    |> Map.merge(GitHistory.blobs_at(context.repository_id, context.sha, unknown))
  end

  defp add_carried_lines(files, _context, _run_ids, carried_lines, _sources) when carried_lines == %{}, do: files

  defp add_carried_lines(files, context, _run_ids, carried_lines, sources) do
    {observed_paths, unbuilt_paths} = carried_lines |> Map.keys() |> Enum.split_with(&Map.has_key?(files, &1))
    line_counts = Commits.line_counts(context.project.id, context.sha, observed_paths, excluded: nil)

    files =
      Enum.reduce(observed_paths, files, fn path, files ->
        counts = Map.get(line_counts, path, [])
        executable = MapSet.new(counts, &elem(&1, 0))
        covered = for {line, count} <- counts, count > 0, into: MapSet.new(), do: line
        carried = MapSet.intersection(carried_lines[path], executable)

        if counts == [] do
          files
        else
          Map.update!(files, path, &%{&1 | covered_lines: MapSet.size(MapSet.union(covered, carried))})
        end
      end)

    source_files = source_files(context.project.id, unbuilt_paths |> Enum.map(&sources[&1].run_id) |> Enum.uniq())

    Enum.reduce(unbuilt_paths, files, fn path, files ->
      case get_in(source_files, [sources[path].run_id, path]) do
        %{line_numbers: executable, git_blob_id: git_blob_id} ->
          Map.put(files, path, %{
            git_blob_id: git_blob_id,
            source_run_ids: [sources[path].run_id],
            covered_lines: MapSet.size(MapSet.intersection(carried_lines[path], executable)),
            executable_lines: MapSet.size(executable)
          })

        nil ->
          files
      end
    end)
  end

  # The files the nearest measured ancestor counted, in the schemes measured
  # here, that no run at the commit compiled. Unchanged, they keep their
  # executable lines; what the ancestor covered in them has to have been
  # carried in full, or the file is a gap: some of its coverage came from tests
  # the commit's runs never listed (a target pruned from the workspace) or
  # from code that ran outside any test. Changed, they are a gap; gone from
  # the listing, they are gone.
  defp add_unbuilt_files(files, context, schemes) do
    with repository_id when repository_id not in [nil, 0] <- context.repository_id,
         {:ok, basis} <- basis(context),
         [_ | _] = basis_run_ids <- basis_run_ids(context.project.id, basis, schemes) do
      missing =
        from(f in subquery(Coverage.merged_files_query_for_runs(context.project.id, basis_run_ids, nil)))
        |> ClickHouseRepo.all()
        |> Enum.reject(&(Map.has_key?(context.observed, &1.path) or ExcludedPaths.excluded?(context.excluded, &1.path)))

      now = GitHistory.blobs_at(repository_id, context.sha, Enum.map(missing, & &1.path))
      listed? = GitHistory.listing_stored?(repository_id, context.sha)

      Enum.reduce(missing, {files, 0}, fn file, {files, gaps} ->
        cond do
          not listed? ->
            {files, gaps + 1}

          not Map.has_key?(now, file.path) ->
            {Map.delete(files, file.path), gaps}

          now[file.path] != file.git_blob_id or file.git_blob_id == "" ->
            {Map.delete(files, file.path), gaps + 1}

          true ->
            carried = Map.get(files, file.path, %{covered_lines: 0}).covered_lines

            {Map.put(files, file.path, %{
               git_blob_id: file.git_blob_id,
               source_run_ids: basis_run_ids,
               targets: file.targets,
               covered_lines: carried,
               executable_lines: file.executable_lines
             }), if(carried < file.covered_lines, do: gaps + 1, else: gaps)}
        end
      end)
    else
      _ -> {files, 0}
    end
  end

  defp basis_run_ids(project_id, basis, schemes) do
    project_id
    |> Commits.runs(basis)
    |> Enum.filter(&(&1.scheme in schemes))
    |> Enum.map(& &1.test_run_id)
  end

  defp basis(context) do
    candidates =
      context.project.id
      |> Commits.commits_query()
      |> subquery()
      |> select([c], c.git_commit_sha)
      |> where([c], c.git_commit_sha != ^context.sha)
      |> ClickHouseRepo.all()

    case GitHistory.nearest_ancestor(context.repository_id, context.sha, candidates) do
      {sha, _distance} -> {:ok, sha}
      nil -> :none
    end
  end
end
