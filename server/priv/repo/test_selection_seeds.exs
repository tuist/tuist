# Test selection seed data for the `tuist/tuist` project.
#
# Records, for every test run the coverage seeds left on a branch other than
# `main`, the impact run that invocation would have made, from the data
# those seeds left behind, so the Test Selection pages agree with the Code
# Coverage and test run pages:
#
#   - a run's baseline is the newest `main` commit measured before it whose
#     coverage completed, that measured the run's scheme fully and that
#     recorded per-test evidence; now and then a commit's first run used the
#     one before, as if the newest baseline's coverage had not completed yet,
#     so the commit has two diffs;
#   - the diff of a commit against its baseline is the difference between
#     the two commits' file listings (`git_commit_files`), plus a few
#     non-code files (a strings file, a doc, a test file, now and then
#     `Package.resolved`);
#   - each test run gets one impact run, which the test run points to
#     (`test_runs.test_impact_run_id`): the rules select a test whose test
#     file changed (`test_file_changed`), that failed at the baseline
#     (`failed_last_run`), that has no evidence (`no_evidence`), whose
#     evidence executed a changed file (`impacted`) or whose module owns a
#     changed resource (`owned_without_evidence`), and skip the rest of the
#     baseline's tests in the requested modules; a changed tracked file and a
#     few others fall back; some runs are sharded, packed by duration, with a
#     shard plan that points to the impact run.
#
# Starts from a clean slate on every run. Runnable on its own after the main
# seed: `mix run priv/repo/test_selection_seeds.exs`.

import Ecto.Query

alias Tuist.ClickHouseRepo
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Shards.ShardPlan
alias Tuist.Shards.ShardPlanTestSuite
alias Tuist.TestImpactAnalysis.Run
alias Tuist.TestImpactAnalysis.RunTest
alias Tuist.TestImpactAnalysis.Storage

defmodule TestSelectionSeed do
  @moduledoc false

  def h(term, n), do: rem(:erlang.phash2(term), n)

  def query(sql, params), do: IngestRepo.query!(sql, params).rows

  def tracked?(path),
    do: path in ["Package.resolved", "Project.swift", "Tuist.swift"] or String.ends_with?(path, ".xcconfig")

  def resource?(path), do: String.ends_with?(path, [".strings", ".xcassets", ".json", ".storyboard", ".xib"])

  # The test target a resource belongs to, by the feature directory it sits
  # in: `Sources/Features/Search/Resources/…` is `SearchTests`'s.
  def resource_module(path) do
    case Path.split(path) do
      ["Sources", "Features", feature | _rest] -> feature <> "Tests"
      ["Sources", target | _rest] -> target <> "Tests"
      _ -> nil
    end
  end

  # Non-code changes and a test file change, on files the baseline's
  # evidence knows: a feature's strings, a doc, one of the tests' own files
  # and, now and then, `Package.resolved`.
  def extras(sha, evidence) do
    features =
      evidence
      |> Enum.flat_map(&Enum.map(&1.paths, fn path -> Path.split(path) end))
      |> Enum.flat_map(fn
        ["Sources", "Features", feature | _rest] -> [feature]
        _other -> []
      end)
      |> Enum.uniq()
      |> Enum.sort()

    test = Enum.at(evidence, h({sha, :test}, max(length(evidence), 1)))

    Enum.concat([
      if(features != [] and h({sha, :resource}, 3) == 0,
        do: [
          {"Sources/Features/#{Enum.at(features, h({sha, :feature}, length(features)))}/Resources/Localizable.strings",
           "modified"}
        ],
        else: []
      ),
      if(h({sha, :doc}, 4) == 0, do: [{"docs/testing.md", "modified"}], else: []),
      if(test && h({sha, :test_file}, 3) == 0, do: [{"Tests/#{test.module}/#{test.suite}.swift", "modified"}], else: []),
      if(h({sha, :tracked}, 11) == 0, do: [{"Package.resolved", "modified"}], else: [])
    ])
  end

  def covered_paths(module, suite, paths) do
    shared =
      if String.ends_with?(suite, "ViewModelTests"), do: ["Sources/Networking/APIClient.swift"], else: []

    Enum.uniq(paths ++ ["Tests/#{module}/#{suite}.swift"] ++ shared)
  end

  # Greedy longest-first packing of suites: each goes to the shard with the
  # least estimated time so far.
  def pack(suites, shard_count) do
    {packed, _loads} =
      suites
      |> Enum.sort_by(fn {key, duration} -> {-duration, key} end)
      |> Enum.map_reduce(List.duplicate(0, shard_count), fn {key, duration}, loads ->
        {load, index} = loads |> Enum.with_index() |> Enum.min()
        {{key, duration, index}, List.replace_at(loads, index, load + duration)}
      end)

    packed
  end

  @rules ~w(tracked_files test_file_changed failed_last_run no_evidence impacted owned_without_evidence unaffected)

  # Per rule, in order, how many tests it selected and skipped, and its
  # verdict.
  def trace(selected, skipped_count) do
    counts = Enum.frequencies_by(selected, & &1.reason)

    Enum.map(@rules, fn
      "tracked_files" -> %{rule: "tracked_files", selected: 0, skipped: 0, verdict: "continue"}
      "unaffected" -> %{rule: "unaffected", selected: 0, skipped: skipped_count, verdict: "done"}
      rule -> %{rule: rule, selected: Map.get(counts, rule, 0), skipped: 0, verdict: "continue"}
    end)
  end
end

{:ok, project} = Projects.get_project_by_slug("tuist/tuist")
now = NaiveDateTime.utc_now()

for table <- ~w(test_impact_diffs test_impact_runs test_impact_run_tests) do
  IngestRepo.query!("ALTER TABLE #{table} DELETE WHERE project_id = {project_id:Int64} SETTINGS mutations_sync = 2", %{
    "project_id" => project.id
  })
end

# Every commit a run measured coverage for, with its branch and first run.
commits =
  """
  SELECT t.git_commit_sha, any(t.git_branch), min(t.ran_at)
  FROM test_runs AS t
  WHERE t.project_id = {project_id:Int64} AND t.git_commit_sha != ''
    AND t.git_commit_sha IN (SELECT git_commit_sha FROM coverage_runs WHERE project_id = {project_id:Int64})
    AND t.ran_at >= now() - INTERVAL 60 DAY
  GROUP BY t.git_commit_sha
  ORDER BY min(t.ran_at)
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id})
  |> Enum.map(fn [sha, branch, ran_at] -> %{sha: sha, branch: branch, ran_at: ran_at} end)

main_commits = Enum.filter(commits, &(&1.branch == project.default_branch))
branch_commits = Enum.reject(commits, &(&1.branch == project.default_branch))

listing = fn sha ->
  "SELECT path, git_blob_id FROM git_commit_files WHERE sha = {sha:String}"
  |> TestSelectionSeed.query(%{"sha" => sha})
  |> Map.new(fn [path, blob] -> {path, blob} end)
end

listings = Map.new(commits, &{&1.sha, listing.(&1.sha)})

test_cases =
  from(c in Tuist.Tests.TestCase,
    where: c.project_id == ^project.id,
    select: {{c.module_name, c.suite_name, c.name}, c.id}
  )
  |> ClickHouseRepo.all()
  |> Map.new()

known_by_module =
  test_cases
  |> Enum.map(fn {{module, suite, name}, id} ->
    %{test_case_id: id, module: module, suite: suite, name: name, status: nil}
  end)
  |> Enum.group_by(& &1.module)

# The per-test evidence of a commit's runs: each test with the files it
# executed.
evidence_for = fn sha ->
  """
  SELECT f.scope_id, groupUniqArray(f.path)
  FROM coverage_files AS f
  INNER JOIN test_runs AS t ON t.id = f.test_run_id
  WHERE f.project_id = {project_id:Int64} AND f.scope_kind = 'test' AND t.git_commit_sha = {sha:String}
  GROUP BY f.scope_id
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "sha" => sha})
  |> Enum.flat_map(fn [scope_id, paths] ->
    with [module, suite, name] <- String.split(scope_id, "\u001F"),
         id when not is_nil(id) <- Map.get(test_cases, {module, suite, name}) do
      [%{test_case_id: id, module: module, suite: suite, name: name, paths: paths}]
    else
      _ -> []
    end
  end)
  |> Enum.sort_by(&{&1.module, &1.suite, &1.name})
end

durations =
  "SELECT toString(assumeNotNull(test_case_id)), toUInt32(avg(duration)) FROM test_case_runs WHERE project_id = {project_id:Int64} AND test_case_id IS NOT NULL GROUP BY test_case_id"
  |> TestSelectionSeed.query(%{"project_id" => project.id})
  |> Map.new(fn [id, duration] -> {id, duration} end)

failed_at = fn sha ->
  """
  SELECT DISTINCT toString(assumeNotNull(test_case_id)) FROM test_case_runs
  WHERE project_id = {project_id:Int64} AND git_commit_sha = {sha:String} AND status = 'failure' AND test_case_id IS NOT NULL
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "sha" => sha})
  |> MapSet.new(fn [id] -> id end)
end

# Only commits whose coverage pipeline completed can be baselines, and only
# for the schemes they measured fully.
measured =
  from(c in Tuist.Tests.CoverageCommit,
    where: c.project_id == ^project.id and c.complete,
    select: {c.git_commit_sha, c.partial_schemes}
  )
  |> Tuist.Repo.all()
  |> Map.new()

baselines =
  main_commits
  |> Enum.filter(&Map.has_key?(measured, &1.sha))
  |> Enum.map(&Map.merge(&1, %{evidence: evidence_for.(&1.sha), partial: Map.fetch!(measured, &1.sha)}))
  |> Enum.reject(&(&1.evidence == []))
  |> Enum.map(&Map.put(&1, :failed, failed_at.(&1.sha)))

# The diff of `head` against `baseline` and, when no tracked file changed,
# what each rule selects among the baseline's tests with evidence: a map of
# test case id to `{reason, matched_path}`.
impact_for = fn head, baseline ->
  before = listings[baseline.sha] || %{}
  after_ = listings[head.sha] || %{}

  listed_changes =
    (Map.keys(before) ++ Map.keys(after_))
    |> Enum.uniq()
    |> Enum.flat_map(fn path ->
      case {Map.get(before, path), Map.get(after_, path)} do
        {same, same} -> []
        {nil, _blob} -> [{path, "added"}]
        {_blob, nil} -> [{path, "deleted"}]
        _changed -> [{path, "modified"}]
      end
    end)

  changes = Enum.uniq_by(listed_changes ++ TestSelectionSeed.extras(head.sha, baseline.evidence), &elem(&1, 0))
  changed = MapSet.new(changes, &elem(&1, 0))
  tracked = Enum.find_value(changes, fn {path, _status} -> if TestSelectionSeed.tracked?(path), do: path end)

  resources =
    for {path, _status} <- changes, TestSelectionSeed.resource?(path), into: %{} do
      {TestSelectionSeed.resource_module(path), path}
    end

  changed_files =
    Enum.map(changes, fn {path, status} ->
      %{
        path: path,
        status: status,
        blob: Map.get(after_, path, ""),
        affected_modules:
          if(TestSelectionSeed.resource?(path), do: List.wrap(TestSelectionSeed.resource_module(path)), else: [])
      }
    end)

  decisions =
    Map.new(baseline.evidence, fn test ->
      covered = TestSelectionSeed.covered_paths(test.module, test.suite, test.paths)
      test_file = "Tests/#{test.module}/#{test.suite}.swift"
      matched = Enum.find(covered, &(MapSet.member?(changed, &1) and &1 != test_file))

      decision =
        cond do
          MapSet.member?(changed, test_file) -> {"test_file_changed", test_file}
          MapSet.member?(baseline.failed, test.test_case_id) -> {"failed_last_run", ""}
          TestSelectionSeed.h({baseline.sha, test.test_case_id}, 70) == 0 -> {"failed_last_run", ""}
          matched -> {"impacted", matched}
          Map.has_key?(resources, test.module) -> {"owned_without_evidence", resources[test.module]}
          true -> nil
        end

      {test.test_case_id, decision}
    end)

  %{changed_files: changed_files, tracked: tracked, decisions: decisions}
end

test_runs_of = fn sha ->
  """
  SELECT toString(id), scheme, ran_at, duration, ci_run_id FROM test_runs
  WHERE project_id = {project_id:Int64} AND git_commit_sha = {sha:String}
  ORDER BY ran_at
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "sha" => sha})
  |> Enum.map(fn [id, scheme, ran_at, duration, ci_run_id] ->
    %{id: id, scheme: scheme, ran_at: ran_at, duration: duration, ci_run_id: ci_run_id}
  end)
end

# What a test run ran: each test once, with its outcome.
ran_in = fn test_run_id ->
  """
  SELECT toString(assumeNotNull(test_case_id)), any(module_name), any(suite_name), any(name),
         multiIf(countIf(status = 'failure') > 0, 'failure', countIf(status = 'success') > 0, 'success', 'skipped')
  FROM test_case_runs
  WHERE project_id = {project_id:Int64} AND test_run_id = {id:UUID} AND test_case_id IS NOT NULL
  GROUP BY assumeNotNull(test_case_id)
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "id" => test_run_id})
  |> Enum.map(fn [id, module, suite, name, status] ->
    %{test_case_id: id, module: module, suite: suite, name: name, status: status}
  end)
end

destinations = [
  "iPhone 17 Pro · iOS 26.1",
  "iPhone 17 Pro · iOS 26.1",
  "iPad Air 13-inch · iPadOS 26.1",
  "My Mac · macOS 26.1"
]

fallbacks = %{0 => "baseline_too_old", 1 => "history_unavailable", 2 => "diff_unavailable"}

# The baseline run's tests of a scheme: what a run that selects against it
# could skip.
baseline_tests = fn sha, scheme ->
  """
  SELECT toString(assumeNotNull(c.test_case_id)), any(c.module_name)
  FROM test_case_runs AS c
  WHERE c.project_id = {project_id:Int64} AND c.test_case_id IS NOT NULL
    AND c.test_run_id IN (
      SELECT test_run_id FROM coverage_runs
      WHERE project_id = {project_id:Int64} AND git_commit_sha = {sha:String} AND scheme = {scheme:String}
    )
  GROUP BY assumeNotNull(c.test_case_id)
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "sha" => sha, "scheme" => scheme})
  |> Enum.map(fn [id, module] -> %{test_case_id: id, module: module} end)
end

seeded =
  Enum.flat_map(branch_commits, fn commit ->
    earlier = Enum.filter(baselines, &NaiveDateTime.before?(&1.ran_at, commit.ran_at))
    runs = test_runs_of.(commit.sha)
    use_older? = length(runs) > 1 and TestSelectionSeed.h({commit.sha, :older}, 3) == 0

    runs
    |> Enum.with_index()
    |> Enum.flat_map(fn {test_run, index} ->
      ran = ran_in.(test_run.id)
      candidates = Enum.reject(earlier, &(test_run.scheme in &1.partial))
      older = if length(candidates) > 1, do: Enum.at(candidates, -2)
      baseline = if use_older? and index == 0 and older, do: older, else: List.last(candidates)
      impact = if baseline, do: impact_for.(commit, baseline)

      {reason, matched_path} =
        cond do
          is_nil(baseline) -> {"no_baseline", ""}
          impact.tracked -> {"tracked_file_changed", impact.tracked}
          true -> {Map.get(fallbacks, TestSelectionSeed.h({test_run.id, :fallback}, 30), ""), ""}
        end

      if ran == [] do
        []
      else
        targets = ran |> Enum.map(& &1.module) |> Enum.uniq() |> Enum.sort()
        target_set = MapSet.new(targets)
        ran_ids = MapSet.new(ran, & &1.test_case_id)
        evidence_ids = if baseline, do: MapSet.new(baseline.evidence, & &1.test_case_id), else: MapSet.new()

        # Now and then, tests Tuist knows in the requested targets that the
        # run never reported: renamed or removed since, or lost with a shard.
        known =
          if TestSelectionSeed.h({test_run.id, :gone}, 4) == 0 do
            targets
            |> Enum.flat_map(&Map.get(known_by_module, &1, []))
            |> Enum.reject(&MapSet.member?(ran_ids, &1.test_case_id))
            |> Enum.sort_by(& &1.test_case_id)
            |> Enum.take(1 + TestSelectionSeed.h(test_run.id, 3))
          else
            []
          end

        selected_at = NaiveDateTime.add(test_run.ran_at, -(60 + TestSelectionSeed.h(test_run.id, 300)), :second)
        run_id = UUIDv7.generate()

        selected =
          if reason == "" do
            Enum.flat_map(ran ++ known, fn test ->
              decision =
                cond do
                  not MapSet.member?(evidence_ids, test.test_case_id) -> {"no_evidence", ""}
                  hit = impact.decisions[test.test_case_id] -> hit
                  true -> nil
                end

              case decision do
                nil ->
                  []

                {rule, matched} ->
                  [
                    %{
                      test_impact_run_id: run_id,
                      project_id: project.id,
                      test_case_id: test.test_case_id,
                      module_name: test.module,
                      suite_name: test.suite,
                      name: test.name,
                      reason: rule,
                      matched_path: matched,
                      inserted_at: selected_at
                    }
                  ]
              end
            end)
          else
            []
          end

        selected_ids = MapSet.new(selected, & &1.test_case_id)

        skipped_count =
          if reason == "" do
            baseline.sha
            |> baseline_tests.(test_run.scheme)
            |> Enum.count(&(MapSet.member?(target_set, &1.module) and not MapSet.member?(selected_ids, &1.test_case_id)))
          else
            0
          end

        # The modules the run never reached, which selective testing skipped
        # by hash, each with its number of tests in the baseline.
        skipped_modules =
          if baseline && reason in ["", "tracked_file_changed"] do
            baseline.sha
            |> baseline_tests.(test_run.scheme)
            |> Enum.reject(&MapSet.member?(target_set, &1.module))
            |> Enum.frequencies_by(& &1.module)
          else
            %{}
          end

        module_skipped_count = skipped_modules |> Map.values() |> Enum.sum()

        # A fallback after the baseline still counts the modules left as
        # selected, as nothing was skipped in them.
        left_count =
          if reason == "tracked_file_changed" do
            baseline.sha
            |> baseline_tests.(test_run.scheme)
            |> Enum.count(&MapSet.member?(target_set, &1.module))
          else
            length(selected)
          end

        rule_trace =
          cond do
            reason == "tracked_file_changed" -> [%{rule: "tracked_files", selected: 0, skipped: 0, verdict: "abort"}]
            reason == "" -> TestSelectionSeed.trace(selected, skipped_count)
            true -> []
          end

        run = %{
          id: run_id,
          project_id: project.id,
          head_sha: commit.sha,
          commit_sha: commit.sha,
          baseline_sha: if(baseline && reason in ["", "tracked_file_changed"], do: baseline.sha),
          git_branch: commit.branch,
          dirty: false,
          strategy: "coverage",
          build_system: "xcode",
          platform: "ios",
          build_context: %{
            "scheme" => test_run.scheme,
            "test_plan" =>
              if(TestSelectionSeed.h({test_run.id, :plan}, 4) == 0, do: "#{test_run.scheme}.xctestplan", else: ""),
            "destination" =>
              Enum.at(destinations, TestSelectionSeed.h({commit.branch, test_run.scheme}, length(destinations)))
          },
          requested_modules: targets,
          outcome: if(reason == "", do: "selected", else: "fallback"),
          reason: reason,
          matched_path: matched_path,
          rules_version: "1",
          rule_trace: rule_trace,
          requested_count: left_count + skipped_count + module_skipped_count,
          selected_count: left_count,
          skipped_count: skipped_count + module_skipped_count,
          skipped_modules: skipped_modules,
          inserted_at: selected_at
        }

        shard_count =
          if reason == "" and TestSelectionSeed.h({test_run.id, :shards}, 3) == 0,
            do: 2 + TestSelectionSeed.h(test_run.id, 3),
            else: 1

        diff =
          if baseline && reason in ["", "tracked_file_changed"],
            do: %{commit_sha: commit.sha, baseline_sha: baseline.sha, changed_files: impact.changed_files}

        [%{run: run, selected: selected, test_run_id: test_run.id, shard_count: shard_count, diff: diff}]
      end
    end)
  end)

seeded
|> Enum.map(& &1.diff)
|> Enum.reject(&is_nil/1)
|> Enum.uniq_by(&{&1.commit_sha, &1.baseline_sha})
|> Enum.each(&Storage.put_diff(Map.put(&1, :project_id, project.id)))

seeded
|> Enum.map(fn %{run: run} ->
  %{
    run
    | build_context: Map.reject(run.build_context, fn {_key, value} -> value == "" end),
      rule_trace: Enum.map(run.rule_trace, &{&1.rule, &1.selected, &1.skipped, &1.verdict})
  }
end)
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(Run, &1))

seeded
|> Enum.flat_map(& &1.selected)
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(RunTest, &1))

# Shard plans that distribute the sharded runs' selected tests by suite.
{plans, suites} =
  seeded
  |> Enum.filter(&(&1.shard_count > 1 and &1.selected != []))
  |> Enum.map(fn %{run: run, selected: selected, shard_count: shard_count} ->
    plan_id = UUIDv7.generate()

    suites =
      selected
      |> Enum.group_by(&{&1.module_name, &1.suite_name})
      |> Enum.map(fn {key, tests} ->
        {key, tests |> Enum.map(&(Map.get(durations, &1.test_case_id) || 40)) |> Enum.sum()}
      end)
      |> TestSelectionSeed.pack(shard_count)
      |> Enum.map(fn {{module, suite}, duration, index} ->
        %{
          shard_plan_id: plan_id,
          project_id: project.id,
          shard_index: index,
          module_name: module,
          test_suite_name: suite,
          estimated_duration_ms: duration,
          inserted_at: run.inserted_at
        }
      end)

    plan = %{
      id: plan_id,
      reference: "seed-#{run.id}",
      project_id: project.id,
      shard_count: shard_count,
      granularity: "suite",
      inserted_at: run.inserted_at,
      test_impact_run_id: run.id
    }

    {plan, suites}
  end)
  |> Enum.unzip()

if plans != [] do
  IngestRepo.insert_all(ShardPlan, plans)
  suites |> List.flatten() |> Enum.chunk_every(2_000) |> Enum.each(&IngestRepo.insert_all(ShardPlanTestSuite, &1))
end

# Point each test run to its impact run.
IngestRepo.query!(
  """
  ALTER TABLE test_runs
  UPDATE test_impact_run_id = toUUIDOrNull(transform(toString(id), {test_run_ids:Array(String)}, {run_ids:Array(String)}, ''))
  WHERE project_id = {project_id:Int64}
  SETTINGS mutations_sync = 2
  """,
  %{
    "project_id" => project.id,
    "test_run_ids" => Enum.map(seeded, & &1.test_run_id),
    "run_ids" => Enum.map(seeded, & &1.run.id)
  }
)

tests_count = seeded |> Enum.map(&length(&1.selected)) |> Enum.sum()

IO.puts("  - test selection: #{length(seeded)} impact runs, #{tests_count} selected tests, #{length(plans)} shard plans")
IO.puts("    /tuist/tuist/tests/test-selection")
