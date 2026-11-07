defmodule Tuist.TestImpactAnalysis.Runs do
  @moduledoc """
  Creates impact runs and derives what they skip.

  `create/2` is the runs request: with a baseline it stores or reuses the
  diff, rebuilds the evidence window for that baseline
  (`Tuist.TestImpactAnalysis.Baselines`), applies the rules
  (`Tuist.TestImpactAnalysis.run/1`) to the modules left to decide and
  records the run with its selected tests. Without one, or when selection
  can't happen, it records a fallback with the reason, after which the client
  runs default selective testing. When hashing skipped every module, it
  records a selection of nothing, without a diff or the rules, so a run never
  runs more than hashing left.

  The request lists every test module in scope, each `skipped` or not, and
  the counts cover all of them: once the baseline is confirmed, the
  baseline's tests in skipped modules count as requested and skipped, and a
  fallback counts the tests of the modules left as selected. Runs that end
  before the baseline is confirmed record zeros.

  Skipped tests are never stored. A skip list is the baseline's tests in the
  modules left to decide (`requested_modules`) less the selected ones:
  `skip_entries/2` for an unsharded run, and `shard_skip/4` for one shard of
  a plan, read again from the baseline runs the decision used
  (`baseline_run_ids`).
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Projects.Project
  alias Tuist.TestImpactAnalysis
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.TestCase

  @changed_files_limit 5_000
  @default_test_duration_ms 1_000

  @doc """
  Decides and records an impact run for the runs request's `params` (the
  `CreateTestImpactRunParams` fields, atom keys). Returns `{:ok, %{run:,
  skipped_tests:}}`, `skipped_tests` being nil on a fallback.
  """
  def create(%Project{} = project, params) do
    commit_sha = Map.get(params, :commit_sha) || params.head_sha
    {decided, skipped} = split_modules(params)
    params = Map.merge(params, %{decided_modules: decided, skipped_modules: skipped})
    attrs = run_attrs(project, params, commit_sha)

    case decide(project, params, commit_sha) do
      {:nothing_left, extra} ->
        attrs = attrs |> Map.put(:outcome, "selected") |> Map.merge(extra)

        with {:ok, run} <- Storage.create_run(attrs) do
          {:ok, %{run: run, skipped_tests: []}}
        end

      {:fallback, reason, extra} ->
        attrs = attrs |> Map.merge(%{outcome: "fallback", reason: to_string(reason)}) |> Map.merge(extra)

        with {:ok, run} <- Storage.create_run(attrs) do
          {:ok, %{run: run, skipped_tests: nil}}
        end

      {:selected, input, result, baseline, skipped_modules} ->
        record_selection(Map.put(attrs, :skipped_modules, skipped_modules), input, result, baseline)
    end
  end

  defp split_modules(params) do
    {skipped, decided} = params |> Map.get(:modules, []) |> Enum.split_with(&Map.get(&1, :skipped, false))
    {Enum.map(decided, & &1.name), Enum.map(skipped, & &1.name)}
  end

  defp run_attrs(project, params, commit_sha) do
    %{
      project_id: project.id,
      head_sha: params.head_sha,
      commit_sha: commit_sha,
      baseline_sha: Map.get(params, :baseline_sha),
      git_branch: Map.get(params, :git_branch) || "",
      dirty: Map.get(params, :dirty) || false,
      strategy: "coverage",
      build_system: params.build_system,
      platform: Map.get(params, :platform) || "",
      build_context: Map.get(params, :xcode) || %{},
      requested_modules: params.decided_modules,
      skipped_modules: Map.new(params.skipped_modules, &{&1, 0}),
      rules_version: TestImpactAnalysis.rules_version()
    }
  end

  defp decide(project, params, commit_sha) do
    baseline_sha = Map.get(params, :baseline_sha)

    cond do
      params.decided_modules == [] ->
        {:nothing_left, nothing_left_attrs(project, params, commit_sha, baseline_sha)}

      is_nil(baseline_sha) ->
        {:fallback, Map.get(params, :fallback_reason) || :no_baseline, %{}}

      true ->
        select(project, params, commit_sha, baseline_sha)
    end
  end

  # Nothing to decide, so no diff and no rules: only what hashing skipped,
  # counted once the baseline is confirmed.
  defp nothing_left_attrs(_project, _params, _commit_sha, nil), do: %{}

  defp nothing_left_attrs(project, params, commit_sha, baseline_sha) do
    case resolve(project, scope(params, commit_sha), baseline_sha) do
      {:ok, baseline} ->
        skipped_modules = skipped_modules(project, params, baseline)
        module_skipped = total(skipped_modules)

        %{
          baseline_run_ids: baseline.run_ids,
          skipped_modules: skipped_modules,
          requested_count: module_skipped,
          skipped_count: module_skipped
        }

      {:fallback, _reason, _extra} ->
        %{baseline_sha: nil}
    end
  end

  # The baseline's tests in each module the client skipped because its hash
  # matched. No rule decides them, so they're counted, never listed.
  defp skipped_modules(project, params, baseline) do
    Input.baseline_test_counts(project.id, baseline.run_ids, params.skipped_modules)
  end

  defp total(skipped_modules), do: skipped_modules |> Map.values() |> Enum.sum()

  defp scope(params, commit_sha) do
    %{
      commit_sha: commit_sha,
      parent_shas: Map.get(params, :parent_shas) || [],
      ancestor_shas: Map.get(params, :ancestor_shas) || [],
      platform: Map.get(params, :platform),
      scheme: get_in(params, [:xcode, :scheme])
    }
  end

  defp select(project, params, commit_sha, baseline_sha) do
    with {:ok, changed_files, changed_files_count} <- changed_files(project, params, commit_sha, baseline_sha),
         :ok <- within_diff_limit(changed_files_count),
         {:ok, baseline} <- resolve(project, scope(params, commit_sha), baseline_sha) do
      skipped_modules = skipped_modules(project, params, baseline)
      module_skipped = total(skipped_modules)

      input =
        Input.load(project,
          repository_id: baseline.repository_id,
          baseline_sha: baseline_sha,
          baseline_run_ids: baseline.run_ids,
          modules: params.decided_modules,
          changed_files: changed_files,
          changed_files_count: changed_files_count
        )

      case TestImpactAnalysis.run(input) do
        # Default selective testing runs every test of the modules left.
        %{outcome: :fallback} = result ->
          requested = length(input.tests)

          extra =
            result
            |> trace_attrs()
            |> Map.merge(%{
              matched_path: result.matched_path || "",
              skipped_modules: skipped_modules,
              requested_count: requested + module_skipped,
              selected_count: requested,
              skipped_count: module_skipped
            })

          {:fallback, result.reason, extra}

        result ->
          {:selected, input, result, baseline, skipped_modules}
      end
    else
      {:diff_fallback, reason} -> {:fallback, reason, diff_fallback_attrs(project, params, commit_sha, baseline_sha)}
      fallback -> fallback
    end
  end

  # Without a diff the rules can't run, so every test of the modules left
  # runs: counted like a rule fallback once the baseline is confirmed.
  defp diff_fallback_attrs(project, params, commit_sha, baseline_sha) do
    case resolve(project, scope(params, commit_sha), baseline_sha) do
      {:ok, baseline} ->
        skipped_modules = skipped_modules(project, params, baseline)
        module_skipped = total(skipped_modules)
        requested = project.id |> Input.baseline_test_counts(baseline.run_ids, params.decided_modules) |> total()

        %{
          skipped_modules: skipped_modules,
          requested_count: requested + module_skipped,
          selected_count: requested,
          skipped_count: module_skipped
        }

      {:fallback, _reason, _extra} ->
        %{}
    end
  end

  # The client sends the diff only when the baseline request said it isn't
  # stored, and always for a dirty checkout, whose diff is never stored.
  defp changed_files(project, params, commit_sha, baseline_sha) do
    case Map.get(params, :changed_files) do
      nil ->
        with false <- Map.get(params, :dirty) || false,
             {:ok, diff} <- Storage.get_diff(project.id, commit_sha, baseline_sha) do
          {:ok, diff.changed_files, diff.changed_files_count}
        else
          _ -> {:diff_fallback, :diff_unavailable}
        end

      files ->
        files =
          Enum.map(
            files,
            &Map.merge(%{blob: nil, affected_modules: nil}, Map.take(&1, [:path, :status, :blob, :affected_modules]))
          )

        count = Map.get(params, :changed_files_count) || length(files)

        if !Map.get(params, :dirty) do
          :ok =
            Storage.put_diff(%{
              project_id: project.id,
              commit_sha: commit_sha,
              baseline_sha: baseline_sha,
              changed_files: files,
              changed_files_count: count
            })
        end

        {:ok, files, count}
    end
  end

  defp within_diff_limit(count) when count > @changed_files_limit, do: {:diff_fallback, :diff_too_large}
  defp within_diff_limit(_count), do: :ok

  defp resolve(project, scope, baseline_sha) do
    case Baselines.resolve(project, scope, baseline_sha: baseline_sha) do
      {:ok, baseline} -> {:ok, baseline}
      {:error, reason} -> {:fallback, reason, %{}}
    end
  end

  defp record_selection(attrs, input, result, baseline) do
    module_skipped = total(attrs.skipped_modules)
    tests = Map.new(input.tests, &{&1.test_case_id, &1})

    selected =
      for {test_case_id, %{decision: :selected} = decision} <- result.decisions do
        test = Map.fetch!(tests, test_case_id)

        %{
          test_case_id: test_case_id,
          module_name: test.module_name,
          suite_name: test.suite_name,
          name: test.name,
          reason: to_string(decision.reason),
          matched_path: decision.matched_path
        }
      end

    attrs =
      attrs
      |> Map.merge(trace_attrs(result))
      |> Map.merge(%{
        outcome: "selected",
        baseline_run_ids: baseline.run_ids,
        requested_count: result.counts.requested + module_skipped,
        selected_count: result.counts.selected,
        skipped_count: result.counts.skipped + module_skipped
      })

    with {:ok, run} <- Storage.create_run(attrs, selected) do
      {:ok, %{run: run, skipped_tests: skip_entries(input.tests, MapSet.new(selected, & &1.test_case_id))}}
    end
  end

  defp trace_attrs(result) do
    %{
      rules_version: result.rules_version,
      rule_trace:
        Enum.map(result.rule_trace, fn entry ->
          %{entry | rule: to_string(entry.rule), verdict: to_string(entry.verdict)}
        end)
    }
  end

  @doc """
  The skip list of an unsharded run: the tests in scope not selected, as
  `%{module, suite, name}`, or one `%{module}` for a module none of whose
  tests is selected. A test the baseline didn't run isn't in scope, so it's
  never on the list and runs.
  """
  def skip_entries(tests, selected_ids) do
    tests
    |> Enum.group_by(& &1.module_name)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {module, tests} ->
      {selected, skipped} = Enum.split_with(tests, &MapSet.member?(selected_ids, &1.test_case_id))

      cond do
        skipped == [] -> []
        selected == [] -> [%{module: module}]
        true -> test_entries(skipped)
      end
    end)
  end

  @doc """
  The skip list of one shard of a plan that distributes the impact run
  `run_id`:

  - a regular shard runs `own_suites` (`{module, suite}`) with
    `-only-testing`, so its list is the tests in them not selected;
  - the catch-all shard, given the suites the other shards own
    (`other_suites`), runs every suite but those. Its list skips the modules
    none of whose tests is selected, the other shards' suites
    (`%{module, suite}`), and the tests not selected in every other suite.

  Nil when the run doesn't exist or isn't a selection.
  """
  def shard_skip(project_id, run_id, own_suites, other_suites \\ nil) do
    case Storage.get_run(project_id, run_id) do
      {:ok, %{outcome: "selected"} = run} ->
        tests = Input.baseline_tests(project_id, run.baseline_run_ids, run.requested_modules)
        selected_ids = project_id |> Storage.list_run_tests(run_id) |> MapSet.new(& &1.test_case_id)

        case other_suites do
          nil ->
            tests
            |> Enum.filter(&MapSet.member?(own_suites, {&1.module_name, &1.suite_name}))
            |> Enum.reject(&MapSet.member?(selected_ids, &1.test_case_id))
            |> test_entries()

          other_suites ->
            catch_all_skip(tests, selected_ids, other_suites)
        end

      _ ->
        nil
    end
  end

  defp catch_all_skip(tests, selected_ids, other_suites) do
    tests
    |> Enum.group_by(& &1.module_name)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {module, tests} ->
      {selected, skipped} = Enum.split_with(tests, &MapSet.member?(selected_ids, &1.test_case_id))

      if selected == [] do
        if skipped == [], do: [], else: [%{module: module}]
      else
        suites =
          for {^module, suite} <- other_suites |> MapSet.to_list() |> Enum.sort(), do: %{module: module, suite: suite}

        suites ++ test_entries(Enum.reject(skipped, &MapSet.member?(other_suites, {module, &1.suite_name})))
      end
    end)
  end

  defp test_entries(tests) do
    tests
    |> Enum.sort_by(&{&1.module_name, &1.suite_name, &1.name})
    |> Enum.map(&%{module: &1.module_name, suite: &1.suite_name, name: &1.name})
  end

  @doc """
  What a shard plan for the impact run `run_id` balances: its suites with
  selected tests, as `Module/Suite`, each priced at its selected tests'
  average durations (`test_cases.avg_duration`; a test without one counts as
  the median of those with one). `{:ok, %{run_id, durations}}`, or
  `{:error, :not_selected}` when the run doesn't exist or fell back.
  """
  def shard_units(project_id, run_id) do
    case Storage.get_run(project_id, run_id) do
      {:ok, %{outcome: "selected"}} ->
        tests = project_id |> Storage.list_run_tests(run_id) |> Enum.reject(&(&1.suite_name == ""))
        known = test_durations(project_id, Enum.map(tests, & &1.test_case_id))
        default = known |> Map.values() |> median(@default_test_duration_ms)

        durations =
          tests
          |> Enum.group_by(&"#{&1.module_name}/#{&1.suite_name}", &Map.get(known, &1.test_case_id, default))
          |> Map.new(fn {unit, durations} -> {unit, Enum.sum(durations)} end)

        {:ok, %{run_id: run_id, durations: durations}}

      _ ->
        {:error, :not_selected}
    end
  end

  defp test_durations(_project_id, []), do: %{}

  defp test_durations(project_id, test_case_ids) do
    test_case_ids
    |> Enum.uniq()
    |> Coverage.id_chunks(1)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in TestCase,
          where: t.project_id == ^project_id and t.id in ^ids,
          group_by: t.id,
          select: {fragment("toString(?)", t.id), fragment("argMax(?, ?)", t.avg_duration, t.inserted_at)}
        )
      )
    end)
    |> Enum.filter(fn {_id, duration} -> duration > 0 end)
    |> Map.new()
  end

  defp median([], default), do: default

  defp median(values, _default) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end
end
