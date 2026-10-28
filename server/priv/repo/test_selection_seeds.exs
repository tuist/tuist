# Test selection seed data for the `tuist/tuist` project.
#
# Plans what each commit the coverage seeds measured would have had to run,
# from the data those seeds left behind, so the Test Selection pages show
# figures that agree with the Code Coverage ones:
#
#   - the baseline of a commit is the newest `main` commit measured before it;
#   - its changed files are the difference between the two commits' file
#     listings (`git_commit_files`), plus a few non-code files (a strings
#     file, a doc, now and then `Package.resolved`) so every kind shows up;
#   - a test's files are what the baseline runs' `test` evidence says it
#     executed, plus its own test file and, for view models, the API client
#     they call;
#   - a test runs when one of its files changed, when a resource of its
#     target changed, when it failed or flaked recently, when it has no
#     evidence of its own, or when a tracked file changed (then everything
#     runs); otherwise it is skipped.
#
# About a third of the plans decide per test target instead of per test, as
# a project without per-test evidence would. Plans are written as if made a
# few minutes before the commit's first run, mostly in dry-run mode.
#
# Starts from a clean slate on every run. Runnable on its own after the main
# seed: `mix run priv/repo/test_selection_seeds.exs`.

import Ecto.Query

alias Tuist.ClickHouseRepo
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Tests.TestSelection
alias Tuist.Tests.TestSelectionChangedFile
alias Tuist.Tests.TestSelectionDecision

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
        do: [{"Sources/Features/#{Enum.at(features, h({sha, :feature}, length(features)))}/Resources/Localizable.strings", "modified"}],
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
end

{:ok, project} = Projects.get_project_by_slug("tuist/tuist")
now = NaiveDateTime.utc_now()

for table <- ~w(test_selections test_selection_decisions test_selection_changed_files) do
  IngestRepo.query!("ALTER TABLE #{table} DELETE WHERE project_id = {project_id:Int64} SETTINGS mutations_sync = 2", %{
    "project_id" => project.id
  })
end

# Every commit a run measured coverage for, with its branch and first run.
commits =
  TestSelectionSeed.query(
    """
    SELECT t.git_commit_sha, any(t.git_branch), min(t.ran_at)
    FROM test_runs AS t
    WHERE t.project_id = {project_id:Int64} AND t.git_commit_sha != ''
      AND t.git_commit_sha IN (SELECT git_commit_sha FROM coverage_runs WHERE project_id = {project_id:Int64})
      AND t.ran_at >= now() - INTERVAL 60 DAY
    GROUP BY t.git_commit_sha
    ORDER BY min(t.ran_at)
    """,
    %{"project_id" => project.id}
  )
  |> Enum.map(fn [sha, branch, ran_at] -> %{sha: sha, branch: branch, ran_at: ran_at} end)

main_commits = Enum.filter(commits, &(&1.branch == "main"))

listing = fn sha ->
  "SELECT path, git_blob_id FROM git_commit_files WHERE sha = {sha:String}"
  |> TestSelectionSeed.query(%{"sha" => sha})
  |> Map.new(fn [path, blob] -> {path, blob} end)
end

listings = commits |> Enum.map(&{&1.sha, listing.(&1.sha)}) |> Map.new()

# The per-test evidence of a commit's runs: module, suite and name with the
# files each test executed, the run that recorded it and that run's scheme.
evidence_for = fn sha ->
  """
  SELECT f.scope_id, groupUniqArray(f.path), any(f.test_run_id), any(t.scheme)
  FROM coverage_files AS f
  INNER JOIN test_runs AS t ON t.id = f.test_run_id
  WHERE f.project_id = {project_id:Int64} AND f.scope_kind = 'test' AND t.git_commit_sha = {sha:String}
  GROUP BY f.scope_id
  """
  |> TestSelectionSeed.query(%{"project_id" => project.id, "sha" => sha})
  |> Enum.flat_map(fn [scope_id, paths, test_run_id, scheme] ->
    case String.split(scope_id, "\u001F") do
      [module, suite, name] ->
        [%{module: module, suite: suite, name: name, paths: paths, test_run_id: test_run_id, scheme: scheme}]

      _ ->
        []
    end
  end)
  |> Enum.sort_by(&{&1.module, &1.suite, &1.name})
end

test_cases =
  from(c in Tuist.Tests.TestCase,
    where: c.project_id == ^project.id,
    select: {{c.module_name, c.suite_name, c.name}, c.id}
  )
  |> ClickHouseRepo.all()
  |> Map.new()

durations =
  "SELECT test_case_id, toUInt32(avg(duration)) FROM test_case_runs WHERE project_id = {project_id:Int64} GROUP BY test_case_id"
  |> TestSelectionSeed.query(%{"project_id" => project.id})
  |> Map.new(fn [id, duration] -> {id, duration} end)

baselines = Map.new(main_commits, &{&1.sha, evidence_for.(&1.sha)})

# A commit's baseline: the newest `main` commit measured before it that
# recorded per-test evidence. Commits without one are left unplanned.
plans =
  Enum.flat_map(commits, fn commit ->
    main_commits
    |> Enum.filter(&(NaiveDateTime.before?(&1.ran_at, commit.ran_at) and baselines[&1.sha] != []))
    |> List.last()
    |> case do
      nil -> []
      baseline -> [{commit, baseline}]
    end
  end)

seeded =
  Enum.map(plans, fn {commit, baseline} ->
    evidence = baselines[baseline.sha]
    before = listings[baseline.sha] || %{}
    head = listings[commit.sha] || %{}

    listed_changes =
      (Map.keys(before) ++ Map.keys(head))
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        case {Map.get(before, path), Map.get(head, path)} do
          {same, same} -> []
          {nil, _blob} -> [{path, "added"}]
          {_blob, nil} -> [{path, "deleted"}]
          _changed -> [{path, "modified"}]
        end
      end)

    changes = Enum.uniq_by(listed_changes ++ TestSelectionSeed.extras(commit.sha, evidence), &elem(&1, 0))
    changed = MapSet.new(changes, &elem(&1, 0))
    kinds = Map.new(changes, fn {path, _status} -> {path, TestSelectionSeed.kind(path)} end)
    tracked? = Enum.any?(kinds, fn {_path, kind} -> kind == "tracked" end)

    resource_modules =
      kinds
      |> Enum.filter(fn {_path, kind} -> kind == "resource" end)
      |> MapSet.new(fn {path, _kind} -> TestSelectionSeed.resource_module(path) end)

    scope = if TestSelectionSeed.h({commit.sha, :scope}, 3) == 0, do: "target", else: "test"
    selection_id = UUIDv7.generate()

    candidates =
      case scope do
        "test" ->
          Enum.map(evidence, fn test ->
            covered = TestSelectionSeed.covered_paths(test.module, test.suite, test.paths)
            test_case_id = Map.get(test_cases, {test.module, test.suite, test.name})

            %{
              scope_kind: "test",
              scheme: test.scheme,
              module_name: test.module,
              suite_name: test.suite,
              name: test.name,
              test_case_id: test_case_id,
              source_path: "Tests/#{test.module}/#{test.suite}.swift",
              covered_paths: covered,
              evidence_test_run_id: test.test_run_id,
              duration: Map.get(durations, test_case_id) || 40 + TestSelectionSeed.h(test, 900),
              key: {test.module, test.suite, test.name}
            }
          end)

        "target" ->
          evidence
          |> Enum.group_by(&{&1.module, &1.scheme})
          |> Enum.map(fn {{module, scheme}, tests} ->
            covered =
              tests |> Enum.flat_map(&TestSelectionSeed.covered_paths(&1.module, &1.suite, &1.paths)) |> Enum.uniq()

            %{
              scope_kind: "target",
              scheme: scheme,
              module_name: module,
              suite_name: "",
              name: "",
              test_case_id: nil,
              source_path: "Tests/#{module}",
              covered_paths: Enum.sort(covered),
              evidence_test_run_id: hd(tests).test_run_id,
              duration:
                tests
                |> Enum.map(&(Map.get(durations, Map.get(test_cases, {&1.module, &1.suite, &1.name})) || 200))
                |> Enum.sum(),
              key: {module}
            }
          end)
          |> Enum.sort_by(& &1.module_name)
      end

    decisions =
      Enum.map(candidates, fn candidate ->
        changed_paths = Enum.filter(candidate.covered_paths, &MapSet.member?(changed, &1))
        roll = TestSelectionSeed.h({commit.sha, candidate.key}, 60)

        {decision, reason} =
          cond do
            tracked? -> {"selected", "tracked_file_changed"}
            changed_paths != [] -> {"selected", "covers_changed_file"}
            MapSet.member?(resource_modules, candidate.module_name) -> {"selected", "unattributed_change"}
            candidate.module_name == "AppIntegrationTests" -> {"selected", "unskippable"}
            roll == 0 -> {"selected", "recently_failed"}
            roll == 1 -> {"selected", "flaky"}
            roll == 2 and candidate.scope_kind == "test" -> {"selected", "no_evidence"}
            true -> {"skipped", "unaffected"}
          end

        candidate
        |> Map.delete(:key)
        |> Map.merge(%{
          id: UUIDv7.generate(),
          test_selection_id: selection_id,
          project_id: project.id,
          decision: decision,
          reason: reason,
          changed_paths: changed_paths,
          covered_paths: if(reason == "no_evidence", do: [], else: candidate.covered_paths),
          inserted_at: now
        })
      end)

    changed_rows =
      Enum.map(changes, fn {path, status} ->
        selected =
          Enum.count(decisions, fn decision ->
            path in decision.changed_paths or
              (decision.reason == "unattributed_change" and TestSelectionSeed.resource_module(path) == decision.module_name)
          end)

        %{
          test_selection_id: selection_id,
          project_id: project.id,
          path: path,
          status: status,
          kind: Map.fetch!(kinds, path),
          selected_count: if(tracked?, do: length(decisions), else: selected),
          inserted_at: now
        }
      end)

    count = fn value -> Enum.count(decisions, &(&1.decision == value)) end

    selection = %{
      id: selection_id,
      project_id: project.id,
      git_commit_sha: commit.sha,
      git_branch: commit.branch,
      scope: scope,
      mode: if(TestSelectionSeed.h({commit.sha, :mode}, 5) == 0, do: "enabled", else: "dry_run"),
      baseline_commit_sha: baseline.sha,
      fallback_reason: if(tracked?, do: "tracked_file_changed", else: ""),
      selected_count: count.("selected"),
      skipped_count: count.("skipped"),
      changed_files_count: length(changed_rows),
      skipped_duration: decisions |> Enum.filter(&(&1.decision == "skipped")) |> Enum.map(& &1.duration) |> Enum.sum(),
      inserted_at: NaiveDateTime.add(commit.ran_at, -(120 + TestSelectionSeed.h(commit.sha, 600)), :second)
    }

    {selection, decisions, changed_rows}
  end)

IngestRepo.insert_all(TestSelection, Enum.map(seeded, &elem(&1, 0)))

seeded
|> Enum.flat_map(&elem(&1, 1))
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(TestSelectionDecision, &1))

seeded
|> Enum.flat_map(&elem(&1, 2))
|> Enum.chunk_every(2_000)
|> Enum.each(&IngestRepo.insert_all(TestSelectionChangedFile, &1))

decisions_count = seeded |> Enum.map(&length(elem(&1, 1))) |> Enum.sum()

IO.puts("  - test selection: #{length(seeded)} commit plans, #{decisions_count} decisions")
IO.puts("    /tuist/tuist/tests/test-selection")
