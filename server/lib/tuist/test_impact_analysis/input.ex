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
  - `evidence`: each test's evidence at the checkout,
    `%{test_case_id => %{newest:, reproduced:}}`, from
    `Tuist.Tests.Coverage.TestEvidence`, the lookup coverage carry uses, over
    the checkout's blobs (`checkout_blobs/2`);
  - `target_evidence`: per module, what the baseline's test processes
    executed outside every test and suite scope (a hosted app's launch,
    Swift Testing tests);
  - `test_paths`: the files the baseline recorded as test code;
  - `evidence_paths`: every file any of the baseline's evidence includes, in
    any module;
  - `flaky`: the tests whose newest reproduced version comes from a run
    where they were flaky.

  `new/1` indexes it, so rules asking the same question share one answer.
  `load/2` reads it all for a baseline.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.TestEvidence
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.TestCaseRun

  @type t :: %__MODULE__{}

  defstruct tests: [],
            changed_files: [],
            changed_files_count: 0,
            tracked_file_globs: [],
            evidence: %{},
            target_evidence: %{},
            test_paths: MapSet.new(),
            evidence_paths: MapSet.new(),
            flaky: MapSet.new(),
            # Derived by `new/1`.
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

    %{
      input
      | changed: changed,
        changed_paths: changed |> Map.keys() |> Enum.sort(),
        tracked: input.tracked_file_globs |> ExcludedPaths.pattern() |> ExcludedPaths.compile(),
        evidenced: evidenced(input),
        tests_by_path: tests_by_path(input.evidence),
        tests_by_module: Enum.group_by(input.tests, & &1.module_name)
    }
  end

  @doc """
  The checkout's blobs, `%{path => blob}`: the baseline's overlaid with the
  changed files', without the files the checkout deleted.
  """
  def checkout_blobs(baseline_blobs, changed_files) do
    Enum.reduce(changed_files, baseline_blobs, fn
      %{path: path, blob: blob}, blobs when is_binary(blob) and blob != "" -> Map.put(blobs, path, blob)
      %{path: path}, blobs -> Map.delete(blobs, path)
    end)
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

  @doc "Whether any of the baseline's evidence, or any test's newest or reproduced version, includes the path."
  def evidenced?(%__MODULE__{evidenced: evidenced}, path), do: MapSet.member?(evidenced, path)

  @doc """
  The test's evidence: `%{newest:, reproduced:}`, `reproduced` the newest
  version the checkout reproduces or nil. Nil for a test without versions.
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

  @doc "Whether the test's newest reproduced version comes from a run where it was flaky."
  def flaky?(%__MODULE__{flaky: flaky}, test_case_id), do: MapSet.member?(flaky, test_case_id)

  defp evidenced(input) do
    version_paths =
      for {_test_case_id, evidence} <- input.evidence,
          version <- [evidence.newest, evidence.reproduced],
          version != nil,
          path <- version.paths,
          do: path

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
  - `:modules`: the requested modules, nil for every module the baseline
    ran;
  - `:changed_files` and `:changed_files_count`, from the client.
  """
  def load(%Project{} = project, opts) do
    repository_id = Keyword.fetch!(opts, :repository_id)
    run_ids = Keyword.fetch!(opts, :baseline_run_ids)
    baseline_sha = Keyword.fetch!(opts, :baseline_sha)
    changed_files = Keyword.get(opts, :changed_files, [])

    # The tests and their evidence, the baseline's evidence and its test files
    # don't depend on each other, so they're read concurrently.
    [{tests, evidence, flaky}, {target_evidence, evidence_paths}, test_paths] =
      [
        fn ->
          tests = baseline_tests(project.id, run_ids, Keyword.get(opts, :modules))

          evidence =
            TestEvidence.lookup(project.id, repository_id, Enum.map(tests, & &1.test_case_id), fn paths ->
              repository_id |> GitHistory.blobs_at(baseline_sha, paths) |> checkout_blobs(changed_files)
            end)

          {tests, evidence, flaky(project.id, evidence)}
        end,
        fn -> baseline_evidence(project.id, run_ids) end,
        fn -> test_paths(project.id, run_ids) end
      ]
      |> Task.async_stream(& &1.(), ordered: true, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    new(%{
      tests: tests,
      changed_files: changed_files,
      changed_files_count: Keyword.get(opts, :changed_files_count, 0),
      tracked_file_globs: GitHistory.settings(project).tracked_file_globs,
      evidence: evidence,
      target_evidence: target_evidence,
      test_paths: test_paths,
      evidence_paths: evidence_paths,
      flaky: flaky
    })
  end

  @doc """
  How many distinct tests the baseline runs `run_ids` ran in `modules`.
  """
  def baseline_test_count(_project_id, [], _modules), do: 0
  def baseline_test_count(_project_id, _run_ids, []), do: 0

  def baseline_test_count(project_id, run_ids, modules) do
    ClickHouseRepo.one(
      from(r in TestCaseRun,
        where:
          r.project_id == ^project_id and r.test_run_id in ^run_ids and not is_nil(r.test_case_id) and
            r.module_name in ^modules,
        select: fragment("uniqExact(?)", r.test_case_id)
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  @doc """
  The tests the baseline's runs executed, one per test case, as
  `%{test_case_id, module_name, suite_name, name}`, narrowed to `modules`
  unless nil.
  """
  def baseline_tests(_project_id, [], _modules), do: []

  def baseline_tests(project_id, run_ids, modules) do
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

  defp flaky(project_id, evidence) do
    reproduced = for {id, %{reproduced: %{run_id: run_id}}} <- evidence, into: %{}, do: {id, run_id}
    flaky_in_runs(project_id, reproduced)
  end

  defp flaky_in_runs(_project_id, reproduced) when reproduced == %{}, do: []

  defp flaky_in_runs(project_id, reproduced) do
    run_ids = reproduced |> Map.values() |> Enum.uniq()

    from(r in TestCaseRun,
      where: r.project_id == ^project_id and r.test_run_id in ^run_ids and r.is_flaky,
      distinct: true,
      select: {fragment("toString(?)", r.test_case_id), fragment("toString(?)", r.test_run_id)}
    )
    |> ClickHouseRepo.all()
    |> Enum.filter(fn {test_case_id, run_id} -> Map.get(reproduced, test_case_id) == run_id end)
    |> Enum.map(&elem(&1, 0))
  end
end
