defmodule TuistTestSupport.Fixtures.TestSelectionFixtures do
  @moduledoc """
  Fixtures for coverage-based test selection: impact runs with the decision
  they stored, their diffs, the snapshots decisions are numbered by, and the
  baseline runs whose tests a fallback's and the modules hashing skipped are
  derived from.
  """
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Run
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.RunsFixtures

  @doc """
  Inserts an impact run for `project_id` and returns it. `selected` and
  `skipped` are the tests its decision selected and skipped as `unaffected`
  (maps over a test's fields; `name` at least, and `reason` and
  `matched_path` for a selected one): a selected run with a baseline and
  tests stores them as its decision, numbered by a checkpoint at the
  baseline that holds them (`snapshot_fixture/1`). The selected count is
  derived from them. `skipped_count` defaults to the `unaffected` rule's
  skips in `rule_trace` plus the tests in `skipped_modules` (the modules
  hashing found not changed and their tests).

  The run is inserted as given rather than through `Storage.create_run/1`,
  which stamps it with the current time: callers place runs in periods.
  """
  def run_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    id = Keyword.get(attrs, :id, UUIDv7.generate())
    inserted_at = Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    commit_sha = Keyword.get(attrs, :commit_sha, "a1b2c3d4e5f6")
    baseline_sha = Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f")
    outcome = Keyword.get(attrs, :outcome, "selected")
    build_context = Keyword.get(attrs, :build_context, %{"scheme" => "App", "destination" => "iPhone 17 Pro · iOS 26.1"})
    platform = Keyword.get(attrs, :platform, "ios")

    selected =
      attrs
      |> Keyword.get(:selected, [])
      |> Enum.map(&Map.merge(%{reason: "impacted", matched_path: ""}, test_attrs(&1)))

    skipped =
      attrs
      |> Keyword.get(:skipped, [])
      |> Enum.map(&Map.merge(test_attrs(&1), %{reason: "unaffected", matched_path: ""}))

    rule_trace = Keyword.get(attrs, :rule_trace, [])

    unaffected =
      Enum.find_value(rule_trace, 0, fn entry -> if entry.rule == "unaffected", do: entry.skipped end)

    skipped_modules = Keyword.get(attrs, :skipped_modules, %{})
    skipped_count = Keyword.get(attrs, :skipped_count, unaffected + Enum.sum(Map.values(skipped_modules)))

    run =
      struct(Run, %{
        id: id,
        project_id: project_id,
        inserted_at: inserted_at,
        head_sha: Keyword.get(attrs, :head_sha, commit_sha),
        commit_sha: commit_sha,
        baseline_sha: baseline_sha,
        git_branch: Keyword.get(attrs, :git_branch, "feature/search"),
        dirty: Keyword.get(attrs, :dirty, false),
        dirty_files: attrs |> Keyword.get(:dirty_files, []) |> Enum.map(&{&1.path, &1.status, &1.blob}),
        strategy: "coverage",
        build_system: "xcode",
        platform: platform,
        build_context: build_context,
        requested_modules: Keyword.get(attrs, :requested_modules, []),
        outcome: outcome,
        reason: Keyword.get(attrs, :reason, ""),
        matched_path: Keyword.get(attrs, :matched_path, ""),
        matched_pattern: Keyword.get(attrs, :matched_pattern, ""),
        tracked_files: Keyword.get(attrs, :tracked_files, []),
        rules_version: Keyword.get(attrs, :rules_version, "1"),
        rule_trace: Enum.map(rule_trace, &{&1.rule, &1.selected, &1.skipped, &1.verdict}),
        requested_count:
          Keyword.get(attrs, :requested_count, if(outcome == "fallback", do: 0, else: length(selected) + skipped_count)),
        selected_count: Keyword.get(attrs, :selected_count, if(outcome == "fallback", do: 0, else: length(selected))),
        skipped_count: if(outcome == "fallback", do: Keyword.get(attrs, :skipped_count, 0), else: skipped_count),
        skipped_modules: skipped_modules
      })

    {:ok, _} = IngestRepo.insert(run)

    if outcome == "selected" and baseline_sha not in [nil, ""] and selected ++ skipped != [] do
      snapshot =
        snapshot_fixture(
          project_id: project_id,
          commit_sha: baseline_sha,
          scheme: Map.get(build_context, "scheme", ""),
          platform: platform,
          tests: selected ++ skipped
        )

      decision_fixture(project_id: project_id, run_id: id, snapshot: snapshot, tests: selected ++ skipped)
    end

    {:ok, run} = Storage.get_run(project_id, id)
    run
  end

  defp test_attrs(test) do
    Map.merge(%{test_case_id: UUIDv7.generate(), module_name: "AppTests", suite_name: "AppTests"}, test)
  end

  @doc """
  Inserts a checkpoint (`Tuist.TestImpactAnalysis.Snapshot`) at `commit_sha`
  for the scope (`scheme`, `platform`) holding `tests` (maps with
  `test_case_id`, `module_name`, `suite_name` and `name`, and optionally
  `files`, the paths the test executed), numbered in module, suite and name
  order, each named in `test_cases`. Returns the snapshot with its tests
  (`tests`, each with its number as `idx`).
  """
  def snapshot_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    id = UUIDv7.generate()
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 31, :day)

    tests =
      attrs
      |> Keyword.get(:tests, [])
      |> Enum.sort_by(&{&1.module_name, &1.suite_name, &1.name})
      |> Enum.with_index(&Map.put(&1, :idx, &2))

    snapshot =
      Repo.insert!(%Snapshot{
        id: id,
        project_id: project_id,
        repository_id: Keyword.get(attrs, :repository_id, 1),
        commit_sha: Keyword.get(attrs, :commit_sha, "0f0f0f0f0f0f"),
        kind: :checkpoint,
        scheme: Keyword.get(attrs, :scheme, "App"),
        platform: Keyword.get(attrs, :platform, "ios"),
        test_run_ids: Keyword.get(attrs, :test_run_ids, []),
        tests_count: length(tests),
        ran_at: now,
        expires_at: expires_at
      })

    params = %{project_id: project_id, snapshot_id: id, expires_at: DateTime.to_unix(expires_at)}

    if tests != [] do
      IngestRepo.query!(
        """
        INSERT INTO test_impact_snapshot_tests (project_id, snapshot_id, test_idx, test_case_id, module_name,
          suite_name, status, files_hash, lines_hash, expires_at)
        SELECT {project_id:Int64}, {snapshot_id:UUID}, idx, toUUID(id), module_name, suite_name, 'passed', 0, 0,
          toDateTime({expires_at:Int64})
        FROM (
          SELECT arrayJoin(arrayZip({idx:Array(UInt32)}, {ids:Array(String)}, {modules:Array(String)},
            {suites:Array(String)})) AS t, t.1 AS idx, t.2 AS id, t.3 AS module_name, t.4 AS suite_name
        )
        """,
        Map.merge(params, %{
          idx: Enum.map(tests, & &1.idx),
          ids: Enum.map(tests, & &1.test_case_id),
          modules: Enum.map(tests, & &1.module_name),
          suites: Enum.map(tests, & &1.suite_name)
        })
      )

      IngestRepo.insert_all(
        TestCase,
        Enum.map(tests, fn test ->
          %{
            id: test.test_case_id,
            project_id: project_id,
            name: test.name,
            module_name: test.module_name,
            suite_name: test.suite_name,
            last_status: "success",
            last_duration: 0,
            last_ran_at: NaiveDateTime.utc_now(),
            state: "enabled",
            inserted_at: NaiveDateTime.utc_now(),
            recent_durations: [],
            avg_duration: 0
          }
        end)
      )
    end

    tests
    |> Enum.flat_map(fn test -> Enum.map(Map.get(test, :files, []), &{&1, test.idx}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {path, idx} ->
      IngestRepo.query!(
        """
        INSERT INTO test_impact_snapshot_files (project_id, snapshot_id, path, is_test, tests, suite_tests,
          target_tests, expires_at)
        SELECT {project_id:Int64}, {snapshot_id:UUID}, {path:String}, false, bitmapBuild({idx:Array(UInt32)}),
          bitmapBuild(emptyArrayUInt32()), bitmapBuild(emptyArrayUInt32()), toDateTime({expires_at:Int64})
        """,
        Map.merge(params, %{path: path, idx: idx})
      )
    end)

    Map.put(snapshot, :tests, tests)
  end

  @doc """
  Stores the decision of the impact run `run_id` over `snapshot`'s tests
  (`snapshot_fixture/1`): `tests` are maps with `test_case_id`, `reason`
  and `matched_path`, a bitmap per decision, reason and matched path,
  `unaffected` ones skipped. `decided` defaults to how many tests that is;
  more makes the decision incomplete.
  """
  def decision_fixture(attrs \\ []) do
    snapshot = Keyword.fetch!(attrs, :snapshot)
    tests = Keyword.fetch!(attrs, :tests)
    idx = Map.new(snapshot.tests, &{&1.test_case_id, &1.idx})
    decided = Keyword.get(attrs, :decided, length(tests))

    tests
    |> Enum.group_by(&{if(&1.reason == "unaffected", do: "skipped", else: "selected"), &1.reason, &1.matched_path})
    |> Enum.each(fn {{decision, reason, matched_path}, tests} ->
      IngestRepo.query!(
        """
        INSERT INTO test_impact_run_decisions (project_id, test_impact_run_id, snapshot_id, evidence_snapshot_id,
          decision, reason, matched_path, chunk, tests, decided, inserted_at)
        SELECT {project_id:Int64}, {run_id:UUID}, {snapshot_id:UUID}, {snapshot_id:UUID}, {decision:String},
          {reason:String}, {matched_path:String}, 0, bitmapBuild({idx:Array(UInt32)}), {decided:UInt32}, now64(6)
        """,
        %{
          project_id: Keyword.fetch!(attrs, :project_id),
          run_id: Keyword.fetch!(attrs, :run_id),
          snapshot_id: snapshot.id,
          decision: decision,
          reason: reason,
          matched_path: matched_path,
          idx: Enum.map(tests, &Map.fetch!(idx, &1.test_case_id)),
          decided: decided
        }
      )
    end)
  end

  @doc """
  Stores the diff between `baseline_sha` and the checked-out `commit_sha`
  with the given `changed_files` (maps with `path` at least).
  """
  def diff_fixture(attrs \\ []) do
    changed_files =
      attrs
      |> Keyword.get(:changed_files, [])
      |> Enum.map(&Map.merge(%{status: "modified", blob: "", affected_modules: []}, &1))

    :ok =
      Storage.put_diff(%{
        project_id: Keyword.fetch!(attrs, :project_id),
        commit_sha: Keyword.get(attrs, :commit_sha, "a1b2c3d4e5f6"),
        baseline_sha: Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f"),
        changed_files: changed_files,
        changed_files_count: Keyword.get(attrs, :changed_files_count)
      })
  end

  @doc """
  Inserts the baseline run of `baseline_sha`: a test run that reported
  coverage for `scheme`, with a test case run per test in `tests` (maps
  with `test_case_id` and `name` at least). Returns the test run.
  """
  def baseline_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    baseline_sha = Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f")
    scheme = Keyword.get(attrs, :scheme, "App")

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project_id,
        git_commit_sha: baseline_sha,
        scheme: scheme,
        git_branch: "main",
        test_modules: []
      )

    for test <- Keyword.get(attrs, :tests, []) do
      RunsFixtures.test_case_run_fixture(
        Keyword.merge(
          [project_id: project_id, test_run_id: test_run.id, git_commit_sha: baseline_sha, scheme: scheme],
          Map.to_list(test)
        )
      )
    end

    IngestRepo.insert_all(CoverageRun, [
      %{
        project_id: project_id,
        test_run_id: test_run.id,
        scheme: scheme,
        git_commit_sha: baseline_sha,
        covered_lines: 1,
        executable_lines: 2,
        version: 1,
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    test_run
  end
end
