defmodule Tuist.TestImpactAnalysis.Input do
  @moduledoc """
  What the selection rules read, built once per request and never changed by
  them:

  - `tests`: the tests in scope, `%{test_case_id, module_name, suite_name,
    name}`: the baseline's tests in the requested modules;
  - `changed_files`: the diff between the baseline and the checkout,
    `%{path, status, blob, affected_modules}`. `affected_modules` lists the
    test modules a file can affect: empty when no target owns it, nil when
    the client couldn't classify it;
  - `changed_files_count`: the diff's size, larger than the list when the
    client capped it;
  - `tracked_file_globs`: the project's tracked files
    (`Tuist.GitHistory.settings/1`);
  - `baseline_blobs`: the baseline's blob for the paths the versions
    executed; overlaid with the changed files, they are the checkout's;
  - `versions`: each test's versions in the evidence window
    (`Tuist.Tests.Coverage.TestSources.versions/4`);
  - `target_evidence`: per module, what the baseline's test processes
    executed outside every test and suite scope (a hosted app's launch,
    Swift Testing tests);
  - `test_paths`: the files the baseline recorded as test code;
  - `evidence_paths`: every file any of the baseline's evidence includes, in
    any module;
  - `flaky`: the tests whose newest version comes from a run where they were
    flaky.

  `new/1` resolves each test's evidence against the checkout's blobs through
  the lookup coverage carry uses (`Tuist.Tests.Coverage.TestSources.resolve/2`)
  and indexes it, so rules asking the same question share one answer.
  `load/2` reads it all for a baseline.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.TestSources
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.TestCaseRun

  @type t :: %__MODULE__{}

  defstruct tests: [],
            changed_files: [],
            changed_files_count: 0,
            tracked_file_globs: [],
            baseline_blobs: %{},
            versions: %{},
            target_evidence: %{},
            test_paths: MapSet.new(),
            evidence_paths: MapSet.new(),
            flaky: MapSet.new(),
            # Derived by `new/1`.
            evidence: %{},
            changed: %{},
            changed_paths: [],
            tracked: nil,
            evidenced: MapSet.new(),
            tests_by_path: %{},
            tests_by_module: %{}

  @doc "Builds an input from its fields (see the module doc) and derives the lookups the rules share."
  def new(attrs) do
    input = struct!(__MODULE__, attrs)
    input = %{input | test_paths: MapSet.new(input.test_paths), evidence_paths: MapSet.new(input.evidence_paths)}
    input = %{input | flaky: MapSet.new(input.flaky)}
    changed = Map.new(input.changed_files, &{&1.path, &1})

    blobs =
      Enum.reduce(input.changed_files, input.baseline_blobs, fn
        %{path: path, blob: blob}, blobs when is_binary(blob) and blob != "" -> Map.put(blobs, path, blob)
        %{path: path}, blobs -> Map.delete(blobs, path)
      end)

    evidence = TestSources.resolve(input.versions, blobs)

    %{
      input
      | evidence: evidence,
        changed: changed,
        changed_paths: changed |> Map.keys() |> Enum.sort(),
        tracked: input.tracked_file_globs |> ExcludedPaths.pattern() |> ExcludedPaths.compile(),
        evidenced: evidenced(input),
        tests_by_path: tests_by_path(evidence),
        tests_by_module: Enum.group_by(input.tests, & &1.module_name)
    }
  end

  @doc "The changed paths, in path order."
  def changed_paths(%__MODULE__{changed_paths: paths}), do: paths

  @doc "Whether the path differs between the baseline and the checkout."
  def changed?(%__MODULE__{changed: changed}, path), do: Map.has_key?(changed, path)

  @doc "Whether a tracked file glob matches the path."
  def tracked?(%__MODULE__{tracked: nil}, _path), do: false
  def tracked?(%__MODULE__{tracked: tracked}, path), do: Regex.match?(tracked, path)

  @doc "Whether the baseline recorded the path as test code."
  def test_file?(%__MODULE__{test_paths: paths}, path), do: MapSet.member?(paths, path)

  @doc "Whether any of the baseline's evidence, or any version in the window, includes the path."
  def evidenced?(%__MODULE__{evidenced: evidenced}, path), do: MapSet.member?(evidenced, path)

  @doc """
  The test's evidence: `%{versions:, newest:, reproduced:}`, `reproduced`
  the newest version the checkout reproduces or nil. Nil for a test without
  versions in the window.
  """
  def evidence(%__MODULE__{evidence: evidence}, test_case_id), do: Map.get(evidence, test_case_id)

  @doc "The tests whose newest version executed the path, as a set of test case ids."
  def tests_touching(%__MODULE__{tests_by_path: by_path}, path), do: Map.get(by_path, path, MapSet.new())

  @doc "The tests in scope from the given modules."
  def tests_in_modules(%__MODULE__{tests_by_module: by_module}, modules),
    do: Enum.flat_map(modules, &Map.get(by_module, &1, []))

  @doc "The module's target-level evidence that changed, in path order."
  def changed_target_paths(%__MODULE__{} = input, module_name) do
    input.target_evidence |> Map.get(module_name, []) |> Enum.filter(&changed?(input, &1)) |> Enum.sort()
  end

  @doc "Whether the test's newest version comes from a run where it was flaky."
  def flaky?(%__MODULE__{flaky: flaky}, test_case_id), do: MapSet.member?(flaky, test_case_id)

  defp evidenced(input) do
    version_paths = input.versions |> Map.values() |> Enum.concat() |> Enum.flat_map(& &1.paths)
    target_paths = input.target_evidence |> Map.values() |> Enum.concat()
    input.evidence_paths |> MapSet.union(MapSet.new(version_paths)) |> MapSet.union(MapSet.new(target_paths))
  end

  defp tests_by_path(evidence) do
    for {test_case_id, %{newest: newest}} <- evidence, path <- newest.paths, reduce: %{} do
      acc -> Map.update(acc, path, MapSet.new([test_case_id]), &MapSet.put(&1, test_case_id))
    end
  end

  @doc """
  Reads the input for a baseline and builds it (`new/1`):

  - `:repository_id`, `:baseline_sha` and `:baseline_run_ids`, the
    baseline's runs in scope;
  - `:window_shas`: the evidence window's commits, nil for no bound;
  - `:modules`: the requested modules, nil for every module the baseline
    ran;
  - `:changed_files` and `:changed_files_count`, from the client.
  """
  def load(%Project{} = project, opts) do
    repository_id = Keyword.fetch!(opts, :repository_id)
    run_ids = Keyword.fetch!(opts, :baseline_run_ids)
    tests = baseline_tests(project.id, run_ids, Keyword.get(opts, :modules))
    test_case_ids = Enum.map(tests, & &1.test_case_id)
    versions = TestSources.versions(project.id, repository_id, test_case_ids, shas: Keyword.get(opts, :window_shas))
    paths = versions |> Map.values() |> Enum.concat() |> Enum.flat_map(& &1.paths) |> Enum.uniq()
    {target_evidence, evidence_paths} = baseline_evidence(project.id, run_ids)

    new(%{
      tests: tests,
      changed_files: Keyword.get(opts, :changed_files, []),
      changed_files_count: Keyword.get(opts, :changed_files_count, 0),
      tracked_file_globs: GitHistory.settings(project).tracked_file_globs,
      baseline_blobs: GitHistory.blobs_at(repository_id, Keyword.fetch!(opts, :baseline_sha), paths),
      versions: versions,
      target_evidence: target_evidence,
      test_paths: test_paths(project.id, run_ids),
      evidence_paths: evidence_paths,
      flaky: flaky(project.id, versions)
    })
  end

  defp baseline_tests(_project_id, [], _modules), do: []

  defp baseline_tests(project_id, run_ids, modules) do
    query =
      from(r in TestCaseRun,
        where: r.project_id == ^project_id and r.test_run_id in ^run_ids and not is_nil(r.test_case_id),
        group_by: r.test_case_id,
        select: %{
          test_case_id: fragment("toString(?)", r.test_case_id),
          module_name: fragment("any(?)", r.module_name),
          suite_name: fragment("any(?)", r.suite_name),
          name: fragment("any(?)", r.name)
        }
      )

    query = if is_nil(modules), do: query, else: where(query, [r], r.module_name in ^modules)
    ClickHouseRepo.all(query, settings: [select_sequential_consistency: 1])
  end

  # The baseline's target-level evidence, per module, with what its tests and
  # suites recorded taken out, and every path any of its evidence includes.
  # Rows from a shard's replaced reports only add paths, which selects more,
  # never less.
  defp baseline_evidence(_project_id, []), do: {%{}, MapSet.new()}

  defp baseline_evidence(project_id, run_ids) do
    rows =
      ClickHouseRepo.all(
        from(f in CoverageFile,
          where:
            f.project_id == ^project_id and f.test_run_id in ^run_ids and f.scope_kind in ["test", "suite", "target"],
          distinct: true,
          select: {f.scope_kind, f.scope_id, f.path}
        )
      )

    scoped =
      for {kind, scope_id, path} <- rows, kind != "target", reduce: %{} do
        acc -> Map.update(acc, Evidence.scope_module(scope_id), MapSet.new([path]), &MapSet.put(&1, path))
      end

    for_result = for({"target", module_name, path} <- rows, do: {module_name, path})

    target_evidence =
      for_result
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {module_name, paths} ->
        {module_name,
         paths |> Enum.reject(&MapSet.member?(Map.get(scoped, module_name, MapSet.new()), &1)) |> Enum.sort()}
      end)

    {target_evidence, MapSet.new(rows, &elem(&1, 2))}
  end

  defp test_paths(_project_id, []), do: []

  defp test_paths(project_id, run_ids) do
    ClickHouseRepo.all(
      from(f in Coverage.report_files_for_runs(project_id, run_ids),
        where: f.is_test == true,
        distinct: true,
        select: f.path
      )
    )
  end

  defp flaky(_project_id, versions) when versions == %{}, do: []

  defp flaky(project_id, versions) do
    newest = versions |> TestSources.resolve(%{}) |> Map.new(fn {id, %{newest: newest}} -> {id, newest.run_id} end)

    run_ids = newest |> Map.values() |> Enum.uniq()

    from(r in TestCaseRun,
      where: r.project_id == ^project_id and r.test_run_id in ^run_ids and r.is_flaky,
      distinct: true,
      select: {fragment("toString(?)", r.test_case_id), fragment("toString(?)", r.test_run_id)}
    )
    |> ClickHouseRepo.all()
    |> Enum.filter(fn {test_case_id, run_id} -> Map.get(newest, test_case_id) == run_id end)
    |> Enum.map(&elem(&1, 0))
  end
end
