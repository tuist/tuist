defmodule Tuist.TestImpactAnalysis.Runs do
  @moduledoc """
  Creates impact runs and derives what they skip.

  `create/2` is the runs request: with a baseline it stores or reuses the
  diff, finds the baseline's checkpoint (`Tuist.TestImpactAnalysis.Baselines`),
  decides the tests of the modules left to decide from snapshots
  (`Tuist.TestImpactAnalysis.Decision`), stores that decision as bitmaps and
  records the run. Without a baseline, or when selection can't happen (a
  dirty checkout, no diff, a diff too large, a changed tracked file), it
  records a fallback with the reason, after which the client runs default
  selective testing.
  When hashing skipped every module, it records a selection of nothing,
  without a diff, so a run never runs more than hashing left.

  A clean checkout's whole diff against a baseline whose file changes are
  written also gives the checked-out commit's files, which it writes as file
  changes when the commit is in the graph
  (`Tuist.GitHistory.FileChanges.write_from_diff/5`), so the client isn't
  asked for the commit's listing. The commit usually reaches the graph only
  after the request, so the listings endpoint tries again from the stored
  diff before the client uploads (`write_file_changes/3`). Either is best
  effort and never fails its request.

  The request lists every test module in scope, each `skipped` or not, and
  the counts cover all of them: once the baseline is confirmed, the
  checkpoint's tests in skipped modules count as requested and skipped, and
  a fallback counts the tests of the modules left as selected. Runs that end
  before the baseline is confirmed record zeros and no `baseline_sha`, with
  the reason there's none, even a selection of nothing.

  The decision is stored before the run, so a run's skip lists, shard plans
  and coverage carry read it (`Decision.stored/2`). A test the decision
  would skip but whose name `test_cases` doesn't hold can't be listed, so
  it's selected as `undecided`.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.GitHistory.FileChanges
  alias Tuist.Projects.Project
  alias Tuist.TestImpactAnalysis
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.BuildSystem
  alias Tuist.TestImpactAnalysis.Decision
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.TestCase

  require Logger

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
    attrs = Map.put(run_attrs(project, params, commit_sha), :id, UUIDv7.generate())

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

      {:selected, baseline, decisions, skipped_modules} ->
        record_selection(project, Map.put(attrs, :skipped_modules, skipped_modules), baseline, decisions)
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
      build_context: BuildSystem.context(params),
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

      Map.get(params, :dirty) ->
        dirty_fallback(project, params, commit_sha, baseline_sha)

      true ->
        select(project, params, commit_sha, baseline_sha)
    end
  end

  # As with coverage, which never counts a dirty run toward its commit, a
  # dirty checkout's code isn't the commit's, so coverage doesn't narrow it:
  # every test of the modules left runs, once the baseline is confirmed. Its
  # diff isn't stored as the commit's; only the files its client marked
  # `dirty`, its uncommitted changes, are kept with the run.
  defp dirty_fallback(project, params, commit_sha, baseline_sha) do
    case resolve(project, scope(params, commit_sha), baseline_sha) do
      {:ok, baseline} ->
        extra =
          project
          |> fallback_counts(params, baseline, skipped_modules(project, params, baseline))
          |> Map.put(:dirty_files, dirty_files(params))

        {:fallback, :dirty_checkout, extra}

      fallback ->
        fallback
    end
  end

  defp dirty_files(params) do
    params |> Map.get(:changed_files) |> List.wrap() |> Enum.filter(&(Map.get(&1, :dirty) == true))
  end

  # Nothing to decide, so no diff and no rules: only what hashing skipped,
  # counted once the baseline is confirmed.
  defp nothing_left_attrs(_project, params, _commit_sha, nil),
    do: %{reason: to_string(Map.get(params, :fallback_reason) || :no_baseline)}

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

      {:fallback, reason, extra} ->
        Map.put(extra, :reason, to_string(reason))
    end
  end

  # The checkpoint's tests in each module the client skipped because its
  # hash matched. No rule decides them, so they're counted, never listed.
  defp skipped_modules(project, params, baseline) do
    Decision.module_counts(project.id, baseline.checkpoint, params.skipped_modules)
  end

  defp total(skipped_modules), do: skipped_modules |> Map.values() |> Enum.sum()

  defp scope(params, commit_sha) do
    %{
      commit_sha: commit_sha,
      parent_shas: Map.get(params, :parent_shas) || [],
      ancestor_shas: Map.get(params, :ancestor_shas) || [],
      platform: Map.get(params, :platform),
      scheme: BuildSystem.scheme(params)
    }
  end

  defp select(project, params, commit_sha, baseline_sha) do
    with {:ok, changed_files, changed_files_count} <- changed_files(project, params, commit_sha, baseline_sha),
         :ok <- within_diff_limit(changed_files_count),
         {:ok, baseline} <- resolve(project, scope(params, commit_sha), baseline_sha) do
      write_file_changes(project, baseline.repository_id, commit_sha, baseline_sha, changed_files, changed_files_count)

      skipped_modules = skipped_modules(project, params, baseline)

      case Decision.tracked_path(project, changed_files) do
        nil ->
          request = %{
            commit_sha: commit_sha,
            git_branch: Map.get(params, :git_branch) || "",
            scheme: BuildSystem.scheme(params),
            platform: Map.get(params, :platform) || "",
            requested_modules: params.decided_modules,
            coverage_policy: Map.get(params, :coverage_policy),
            before: DateTime.utc_now()
          }

          {:selected, baseline, Decision.decide(project, request, baseline.checkpoint, changed_files), skipped_modules}

        # Default selective testing runs every test of the modules left.
        path ->
          extra =
            project
            |> fallback_counts(params, baseline, skipped_modules)
            |> Map.merge(%{
              matched_path: path,
              rules_version: TestImpactAnalysis.rules_version(),
              rule_trace: TestImpactAnalysis.tracked_trace()
            })

          {:fallback, :tracked_file_changed, extra}
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
      {:ok, baseline} -> fallback_counts(project, params, baseline, skipped_modules(project, params, baseline))
      {:fallback, _reason, extra} -> extra
    end
  end

  defp fallback_counts(project, params, baseline, skipped_modules) do
    module_skipped = total(skipped_modules)
    requested = project.id |> Decision.module_counts(baseline.checkpoint, params.decided_modules) |> total()

    %{
      baseline_run_ids: baseline.run_ids,
      skipped_modules: skipped_modules,
      requested_count: requested + module_skipped,
      selected_count: requested,
      skipped_count: module_skipped
    }
  end

  # The client sends the diff only when the baseline request said it isn't
  # stored.
  defp changed_files(project, params, commit_sha, baseline_sha) do
    case Map.get(params, :changed_files) do
      nil ->
        case Storage.get_diff(project.id, commit_sha, baseline_sha) do
          {:ok, diff} -> {:ok, diff.changed_files, diff.changed_files_count}
          {:error, :not_found} -> {:diff_fallback, :diff_unavailable}
        end

      files ->
        files =
          Enum.map(
            files,
            &Map.merge(%{blob: nil, affected_modules: nil}, Map.take(&1, [:path, :status, :blob, :affected_modules]))
          )

        count = Map.get(params, :changed_files_count) || length(files)

        :ok =
          Storage.put_diff(%{
            project_id: project.id,
            commit_sha: commit_sha,
            baseline_sha: baseline_sha,
            changed_files: files,
            changed_files_count: count
          })

        {:ok, files, count}
    end
  end

  defp within_diff_limit(count) when count > @changed_files_limit, do: {:diff_fallback, :diff_too_large}
  defp within_diff_limit(_count), do: :ok

  @doc """
  Writes the file changes of those of `shas` that have a stored diff from
  the project's runs requests, against a baseline whose file changes are
  written, so the client isn't asked to upload their listings. Returns the
  SHAs written.
  """
  def write_file_changes(project, repository_id, shas) do
    project.id
    |> stored_diffs(shas)
    |> Enum.group_by(& &1.commit_sha)
    |> Enum.filter(fn {sha, diffs} ->
      Enum.any?(diffs, fn diff ->
        write_file_changes(project, repository_id, sha, diff.baseline_sha, diff.changed_files, diff.changed_files_count) ==
          :written
      end)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp stored_diffs(project_id, shas), do: best_effort(shas, [], fn -> Storage.list_diffs(project_id, shas) end)

  # A clean checkout's whole diff against a baseline whose file changes are
  # written gives the commit's files (`Tuist.GitHistory.FileChanges.write_from_diff/5`).
  # Best effort: when it doesn't apply or fails, the client uploads the
  # commit's listing as it would otherwise.
  defp write_file_changes(project, repository_id, sha, baseline_sha, changed_files, changed_files_count) do
    best_effort(sha, :failed, fn ->
      if changed_files_count == length(changed_files) do
        limit = GitHistory.settings(project).commit_file_limit
        FileChanges.write_from_diff(repository_id, sha, baseline_sha, changed_files, limit)
      else
        :incomplete
      end
    end)
  end

  defp best_effort(shas, failed, fun) do
    fun.()
  rescue
    error ->
      Logger.warning(
        "Writing the file changes of #{inspect(shas)} from a selection diff failed: #{Exception.message(error)}"
      )

      failed
  end

  defp resolve(project, scope, baseline_sha) do
    case Baselines.resolve(project, scope, baseline_sha: baseline_sha) do
      {:ok, baseline} -> {:ok, baseline}
      {:error, reason} -> {:fallback, reason, %{baseline_sha: nil}}
    end
  end

  defp record_selection(project, attrs, baseline, decisions) do
    {decisions, names} = with_names(project.id, baseline.checkpoint, decisions)
    :ok = Decision.store(project.id, attrs.id, baseline.checkpoint, decisions)

    module_skipped = total(attrs.skipped_modules)
    {selected, skipped} = decisions |> Map.values() |> Enum.split_with(&(&1.decision == :selected))

    attrs =
      Map.merge(attrs, %{
        outcome: "selected",
        baseline_run_ids: baseline.run_ids,
        rule_trace: TestImpactAnalysis.rule_trace(decisions),
        requested_count: map_size(decisions) + module_skipped,
        selected_count: length(selected),
        skipped_count: length(skipped) + module_skipped
      })

    with {:ok, run} <- Storage.create_run(attrs) do
      tests = Enum.map(selected ++ skipped, &Map.put(&1, :name, get_in(names, [&1.idx, :name])))
      {:ok, %{run: run, skipped_tests: skip_entries(tests, MapSet.new(selected, & &1.test_case_id))}}
    end
  end

  # The names of the tests the decision skips. One `test_cases` doesn't name
  # can't go on a skip list, so it runs.
  defp with_names(project_id, checkpoint, decisions) do
    skipped = for {_id, %{decision: :skipped} = test} <- decisions, do: test.idx
    names = Snapshots.names(project_id, %{checkpoint: checkpoint, overlay: nil}, skipped)

    decisions =
      Map.new(decisions, fn
        {id, %{decision: :skipped} = test} when not is_map_key(names, test.idx) ->
          {id, %{test | decision: :selected, reason: :undecided, matched_path: nil}}

        entry ->
          entry
      end)

    {decisions, names}
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
    case named_decision(project_id, run_id) do
      {tests, selected_ids} ->
        case other_suites do
          nil ->
            tests
            |> Enum.filter(&MapSet.member?(own_suites, {&1.module_name, &1.suite_name}))
            |> Enum.reject(&MapSet.member?(selected_ids, &1.test_case_id))
            |> test_entries()

          other_suites ->
            catch_all_skip(tests, selected_ids, other_suites)
        end

      nil ->
        nil
    end
  end

  @doc """
  The skip list of the impact run `run_id`, as the runs request returned it
  (`skip_entries/2`): what a shard of a plan that distributes the selection
  by module reads, keeping the entries of the tests it runs. Nil when the run
  doesn't exist or isn't a selection.
  """
  def skipped_tests(project_id, run_id) do
    case named_decision(project_id, run_id) do
      {tests, selected_ids} -> skip_entries(tests, selected_ids)
      nil -> nil
    end
  end

  # The stored decision's tests, the skipped ones named, and the ids of the
  # selected ones. A skipped test without a name can't be listed, so it runs.
  defp named_decision(project_id, run_id) do
    case stored(project_id, run_id) do
      %{tests: tests} = decision ->
        skipped = for %{decision: :skipped} = test <- tests, do: test.idx
        names = Snapshots.names(project_id, %{checkpoint: %Snapshot{id: decision.snapshot_id}, overlay: nil}, skipped)
        tests = Enum.map(tests, &named(&1, names))
        {tests, for(%{decision: :selected} = test <- tests, into: MapSet.new(), do: test.test_case_id)}

      nil ->
        nil
    end
  end

  defp named(%{decision: :selected} = test, _names), do: test

  defp named(test, names) do
    case Map.get(names, test.idx) do
      nil -> %{test | decision: :selected}
      %{name: name} -> Map.put(test, :name, name)
    end
  end

  # A selection's stored decision; nil for a run that doesn't exist, fell
  # back or has none.
  defp stored(project_id, run_id) do
    case Storage.get_run(project_id, run_id) do
      {:ok, %{outcome: "selected"}} -> Decision.stored(project_id, run_id)
      _ -> nil
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
  the median of those with one). `{:ok, %{run_id, granularity: "suite",
  durations}}`, or `{:error, :not_selected}` when the run doesn't exist or
  stored no decision (a fallback). A build system whose plans distribute a
  selection by module (`BuildSystem.shard_granularity/1`) gets `{:ok,
  %{run_id, granularity: "module"}}` for any run, whatever its outcome: its
  plan balances the modules the client sends, as without a selection, and
  its shards, which learn the run only from the plan, report it.
  """
  def shard_units(project_id, run_id) do
    case Storage.get_run(project_id, run_id) do
      {:ok, %{build_system: build_system}} ->
        case BuildSystem.shard_granularity(build_system) do
          "module" -> {:ok, %{run_id: run_id, granularity: "module"}}
          "suite" -> suite_units(project_id, run_id)
        end

      _ ->
        {:error, :not_selected}
    end
  end

  defp suite_units(project_id, run_id) do
    case Decision.stored(project_id, run_id) do
      %{tests: tests} ->
        tests = Enum.filter(tests, &(&1.decision == :selected and &1.suite_name != ""))
        known = test_durations(project_id, Enum.map(tests, & &1.test_case_id))
        default = known |> Map.values() |> median(@default_test_duration_ms)

        durations =
          tests
          |> Enum.group_by(&"#{&1.module_name}/#{&1.suite_name}", &Map.get(known, &1.test_case_id, default))
          |> Map.new(fn {unit, durations} -> {unit, Enum.sum(durations)} end)

        {:ok, %{run_id: run_id, granularity: "suite", durations: durations}}

      nil ->
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
