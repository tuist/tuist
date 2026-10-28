# Test selection seed data for the `tuist/tuist` project.
#
# Selects, for every test run the coverage seeds left on a branch other than
# `main`, what that invocation would have run, from the data those seeds left
# behind, so the Test Selection pages agree with the Code Coverage and test
# run pages:
#
#   - a run's baseline is the newest `main` commit measured before it whose
#     coverage completed, that measured the run's scheme fully and that
#     recorded per-test evidence; now and then a commit's first run used the
#     one before, as if the newest baseline's coverage had not completed yet,
#     so the commit has two impacts;
#   - the impact of a commit against its baseline is the difference between
#     the two commits' file listings (`git_commit_files`), plus a few
#     non-code files (a strings file, a doc, a test file, now and then
#     `Package.resolved`), and the tests whose baseline evidence executed a
#     changed file (`impacted`), whose target changed (`target_changed`: a
#     resource in it, or a tracked file for every target) or that failed at
#     the baseline (`failed_at_baseline`);
#   - each test run is one selection run: it requests the tests it ran plus
#     the baseline's tests of the same targets (so tests removed since show
#     up as planned but not run), selects what the impact reaches and what
#     has no evidence, and skips the rest; a few fall back to running
#     everything; some are sharded, packed by duration;
#   - mostly dry runs, so the would-skip tests that failed in the run are the
#     misses.
#
# Starts from a clean slate on every run. Runnable on its own after the main
# seed: `mix run priv/repo/test_selection_seeds.exs`.

import Ecto.Query

alias Tuist.ClickHouseRepo
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Tests.TestImpact
alias Tuist.Tests.TestImpactChangedFile
alias Tuist.Tests.TestImpactTest
alias Tuist.Tests.TestSelectionRun
alias Tuist.Tests.TestSelectionTest

defmodule TestSelectionSeed do
  @moduledoc false

  def h(term, n), do: rem(:erlang.phash2(term), n)

  def query(sql, params), do: IngestRepo.query!(sql, params).rows

  def kind(path) do
    cond do
      path in ["Package.resolved", "Project.swift", "Tuist.swift"] or String.ends_with?(path, ".xcconfig") -> "tracked"
      String.starts_with?(path, "docs/") or String.ends_with?(path, ".md") -> "ignored"
      String.ends_with?(path, [".strings", ".xcassets", ".json", ".storyboard", ".xib"]) -> "resource"
      String.starts_with?(path, "Tests/") -> "test"
      true -> "source"
    end
  end

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

  # Greedy longest-first packing: each test goes to the shard with the least
  # estimated time so far.
  def pack(tests, 1), do: Enum.map(tests, &Map.put(&1, :shard_index, 0))

  def pack(tests, shard_count) do
    {packed, _loads} =
      tests
      |> Enum.sort_by(&{-&1.estimated_duration_ms, &1.module_name, &1.name})
      |> Enum.map_reduce(List.duplicate(0, shard_count), fn test, loads ->
        {load, index} = loads |> Enum.with_index() |> Enum.min()
        {Map.put(test, :shard_index, index), List.replace_at(loads, index, load + test.estimated_duration_ms)}
      end)

    packed
  end
end

{:ok, project} = Projects.get_project_by_slug("tuist/tuist")
now = NaiveDateTime.utc_now()

for table <- ~w(test_impacts test_impact_changed_files test_impact_tests test_selection_runs test_selection_tests) do
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

# The impact of `head` against `baseline`: the changed paths and the tests
# they reach.
impact_for = fn head, baseline, computed_at ->
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
  kinds = Map.new(changes, fn {path, _status} -> {path, TestSelectionSeed.kind(path)} end)
  tracked = Enum.find_value(changes, fn {path, _status} -> if kinds[path] == "tracked", do: path end)

  resources =
    for {path, "resource"} <- kinds, into: %{}, do: {TestSelectionSeed.resource_module(path), path}

  tests =
    Enum.flat_map(baseline.evidence, fn test ->
      covered = TestSelectionSeed.covered_paths(test.module, test.suite, test.paths)
      matched = Enum.find(covered, &MapSet.member?(changed, &1))

      reason =
        cond do
          matched -> {"impacted", matched}
          tracked -> {"target_changed", tracked}
          Map.has_key?(resources, test.module) -> {"target_changed", resources[test.module]}
          MapSet.member?(baseline.failed, test.test_case_id) -> {"failed_at_baseline", ""}
          TestSelectionSeed.h({baseline.sha, test.test_case_id}, 70) == 0 -> {"failed_at_baseline", ""}
          true -> nil
        end

      case reason do
        nil ->
          []

        {reason, matched_path} ->
          [
            %{
              project_id: project.id,
              head_sha: head.sha,
              baseline_sha: baseline.sha,
              test_case_id: test.test_case_id,
              module_name: test.module,
              suite_name: test.suite,
              name: test.name,
              reason: reason,
              matched_path: matched_path,
              inserted_at: computed_at
            }
          ]
      end
    end)

  reached = Enum.frequencies_by(tests, & &1.matched_path)

  files =
    Enum.map(changes, fn {path, status} ->
      %{
        project_id: project.id,
        head_sha: head.sha,
        baseline_sha: baseline.sha,
        path: path,
        status: status,
        kind: Map.fetch!(kinds, path),
        impacted_tests_count: Map.get(reached, path, 0),
        inserted_at: computed_at
      }
    end)

  %{
    impact: %{
      project_id: project.id,
      head_sha: head.sha,
      baseline_sha: baseline.sha,
      git_branch: head.branch,
      changed_files_count: length(files),
      impacted_tests_count: length(tests),
      inserted_at: computed_at
    },
    files: files,
    tests: Map.new(tests, &{&1.test_case_id, &1})
  }
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

fallbacks = %{0 => "baseline_too_far", 1 => "deepen_budget_exhausted", 2 => "timeout", 3 => "platform_mismatch"}

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

      fallback =
        if is_nil(baseline),
          do: "no_baseline",
          else: Map.get(fallbacks, TestSelectionSeed.h({test_run.id, :fallback}, 30), "")

      if ran == [] do
        []
      else
        targets = ran |> Enum.map(& &1.module) |> Enum.uniq() |> Enum.sort()
        target_set = MapSet.new(targets)
        ran_ids = MapSet.new(ran, & &1.test_case_id)

        # The baseline's tests of the same targets that this run didn't
        # run: requested by the plan, but gone from the scheme since.
        missing =
          if baseline do
            baseline.evidence
            |> Enum.filter(&(MapSet.member?(target_set, &1.module) and not MapSet.member?(ran_ids, &1.test_case_id)))
            |> Enum.map(&%{test_case_id: &1.test_case_id, module: &1.module, suite: &1.suite, name: &1.name, status: nil})
          else
            []
          end

        # Now and then, tests Tuist knows in the requested targets that the
        # run never reported: renamed or removed since, or lost with a shard.
        known =
          if TestSelectionSeed.h({test_run.id, :gone}, 4) == 0 do
            seen = MapSet.union(ran_ids, MapSet.new(missing, & &1.test_case_id))

            targets
            |> Enum.flat_map(&Map.get(known_by_module, &1, []))
            |> Enum.reject(&MapSet.member?(seen, &1.test_case_id))
            |> Enum.sort_by(& &1.test_case_id)
            |> Enum.take(1 + TestSelectionSeed.h(test_run.id, 3))
          else
            []
          end

        requested = ran ++ missing ++ known
        selected_at = NaiveDateTime.add(test_run.ran_at, -(60 + TestSelectionSeed.h(test_run.id, 300)), :second)
        impact = if baseline && fallback == "", do: impact_for.(commit, baseline, selected_at)
        evidence_ids = if baseline, do: MapSet.new(baseline.evidence, & &1.test_case_id), else: MapSet.new()
        run_id = UUIDv7.generate()

        tests =
          Enum.map(requested, fn test ->
            {decision, reason, matched} =
              cond do
                fallback != "" -> {"selected", "run_all", ""}
                hit = impact.tests[test.test_case_id] -> {"selected", hit.reason, hit.matched_path}
                not MapSet.member?(evidence_ids, test.test_case_id) -> {"selected", "no_evidence", ""}
                true -> {"skipped", "unaffected", ""}
              end

            %{
              project_id: project.id,
              selection_run_id: run_id,
              test_case_id: test.test_case_id,
              module_name: test.module,
              suite_name: test.suite,
              name: test.name,
              decision: decision,
              shard_index: 0,
              reason: reason,
              matched_path: matched,
              estimated_duration_ms: Map.get(durations, test.test_case_id) || 40 + TestSelectionSeed.h(test, 900),
              inserted_at: now,
              status: test.status
            }
          end)

        shard_count =
          if TestSelectionSeed.h({test_run.id, :shards}, 3) == 0, do: 2 + TestSelectionSeed.h(test_run.id, 3), else: 1

        {selected, skipped} = Enum.split_with(tests, &(&1.decision == "selected"))
        tests = TestSelectionSeed.pack(selected, shard_count) ++ skipped
        mode = if TestSelectionSeed.h({commit.sha, :mode}, 5) == 0, do: "enabled", else: "dry_run"

        ci_run_id =
          if test_run.ci_run_id in [nil, ""],
            do: "#{18_000_000_000 + TestSelectionSeed.h(test_run.id, 900_000_000)}",
            else: test_run.ci_run_id

        job = "test (#{test_run.scheme})"

        # Now and then a dry run's would-skip tests fail: the misses the
        # dry run exists to measure. The seed marks them failed in the run.
        failing =
          if mode == "dry_run" and fallback == "" and TestSelectionSeed.h({test_run.id, :miss}, 5) == 0 do
            skipped
            |> Enum.reject(&is_nil(&1.status))
            |> Enum.sort_by(&{TestSelectionSeed.h({&1.test_case_id, :miss}, 1000), &1.test_case_id})
            |> Enum.take(1 + TestSelectionSeed.h(test_run.id, 2))
          else
            []
          end

        failing_ids = MapSet.new(failing, & &1.test_case_id)

        missed =
          if mode == "dry_run",
            do: Enum.count(skipped, &(&1.status == "failure" or MapSet.member?(failing_ids, &1.test_case_id))),
            else: 0

        run = %{
          id: run_id,
          project_id: project.id,
          idempotency_key: "github:#{ci_run_id}:#{job}",
          git_commit_sha: commit.sha,
          git_branch: commit.branch,
          baseline_sha: if(fallback in ["", "platform_mismatch"] and not is_nil(baseline), do: baseline.sha, else: ""),
          scheme: test_run.scheme,
          test_plan: if(TestSelectionSeed.h({test_run.id, :plan}, 4) == 0, do: "#{test_run.scheme}.xctestplan", else: ""),
          destination: Enum.at(destinations, TestSelectionSeed.h({commit.branch, test_run.scheme}, length(destinations))),
          requested_targets: targets,
          mode: mode,
          shard_count: shard_count,
          shard_plan_id: UUIDv7.generate(),
          test_run_id: test_run.id,
          ci_provider: "github",
          ci_run_id: ci_run_id,
          ci_job_id: job,
          requested_count: length(tests),
          selected_count: length(selected),
          skipped_count: length(skipped),
          missed_count: missed,
          skipped_duration: skipped |> Enum.map(& &1.estimated_duration_ms) |> Enum.sum(),
          fallback_reason: fallback,
          inserted_at: selected_at,
          updated_at: NaiveDateTime.add(test_run.ran_at, max(div(test_run.duration, 1000), 1), :second)
        }

        [{run, Enum.map(tests, &Map.delete(&1, :status)), impact, Enum.map(failing, &{test_run.id, &1.test_case_id})}]
      end
    end)
  end)

failures = Enum.flat_map(seeded, &elem(&1, 3))

if failures != [] do
  pairs = Enum.map_join(failures, ", ", fn {run_id, case_id} -> "(toUUID('#{run_id}'), toUUID('#{case_id}'))" end)
  runs = failures |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map_join(", ", &"toUUID('#{&1}')")

  IngestRepo.query!(
    "ALTER TABLE test_case_runs UPDATE status = 'failure' WHERE (test_run_id, assumeNotNull(test_case_id)) IN (#{pairs}) SETTINGS mutations_sync = 2"
  )

  IngestRepo.query!("ALTER TABLE test_runs UPDATE status = 'failure' WHERE id IN (#{runs}) SETTINGS mutations_sync = 2")
end

impacts =
  seeded
  |> Enum.map(&elem(&1, 2))
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq_by(&{&1.impact.head_sha, &1.impact.baseline_sha})

IngestRepo.insert_all(TestImpact, Enum.map(impacts, & &1.impact))

impacts
|> Enum.flat_map(& &1.files)
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(TestImpactChangedFile, &1))

impacts
|> Enum.flat_map(&Map.values(&1.tests))
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(TestImpactTest, &1))

IngestRepo.insert_all(TestSelectionRun, Enum.map(seeded, &elem(&1, 0)))

seeded
|> Enum.flat_map(&elem(&1, 1))
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(TestSelectionTest, &1))

tests_count = seeded |> Enum.map(&length(elem(&1, 1))) |> Enum.sum()

IO.puts("  - test selection: #{length(seeded)} selection runs, #{length(impacts)} impacts, #{tests_count} tests")
IO.puts("    /tuist/tuist/tests/test-selection")
