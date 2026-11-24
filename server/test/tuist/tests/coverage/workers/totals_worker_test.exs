defmodule Tuist.Tests.Coverage.Workers.TotalsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouse.Insert
  alias Tuist.ClickHouse.Inserts
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.Coverage.Workers.TotalsWorker
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    %{account: user.account, project: project}
  end

  test "publishes a run's totals at once when every replica holds its rows", %{account: account, project: project} do
    run =
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
        recompute: false,
        coverage_evidence: %{paths: ["Sources/A.swift"], scopes: [%{kind: "target", module: "App", files: [0]}]}
      })

    assert [%{covered_lines: 1, executable_lines: 2}] = totals(run.id)
    inserts = Inserts.by_table(Coverage.report_key(run.id, 0))
    assert Map.keys(inserts) == ["coverage_files", "coverage_run_files"]
    assert Enum.all?(Map.values(inserts), & &1.synced_at)
    refute_enqueued(worker: TotalsWorker)
  end

  test "holds the totals back until the replica holds the evidence the shard stored", %{project: project} do
    {key, run} = run_row(project)
    Inserts.record("coverage_files", key, project.id, ~N[2026-11-24 10:00:00.000001])

    TotalsWorker.publish(run, 0, NaiveDateTime.utc_now(), 0)

    assert totals(run.test_run_id) == []
    [job] = all_enqueued(worker: TotalsWorker)
    assert perform_job(TotalsWorker, job.args) == {:snooze, 5}

    Evidence.record(%{id: run.test_run_id, project_id: project.id, git_commit_sha: "c1"}, %{
      paths: ["Sources/A.swift"],
      scopes: [%{kind: "target", module: "App", files: [0]}]
    })

    assert perform_job(TotalsWorker, job.args) == :ok
    assert [%{version: 7}] = totals(run.test_run_id)
    assert_enqueued(worker: CommitWorker, args: %{project_id: project.id, git_commit_sha: "c1"})
  end

  test "holds the totals back until the replica holds every shard report they pin", %{project: project} do
    {_key, run} = run_row(project)
    other_shard_at = ~N[2026-11-24 10:00:00.000001]
    run = %{run | report_shards: [1], report_inserted_at: [other_shard_at]}

    TotalsWorker.publish(run, 0, NaiveDateTime.utc_now(), 0)

    assert totals(run.test_run_id) == []
    [job] = all_enqueued(worker: TotalsWorker)
    assert perform_job(TotalsWorker, job.args) == {:snooze, 5}

    insert_report_row(project, run.test_run_id, 1, other_shard_at, executable_lines: 2)

    assert perform_job(TotalsWorker, job.args) == :ok
    assert [%{report_shards: [1], report_inserted_at: [^other_shard_at]}] = totals(run.test_run_id)
  end

  test "publishes nothing for a report a newer report of the same shard replaced", %{project: project} do
    {key, run} = run_row(project)
    reported_at = NaiveDateTime.utc_now()
    Inserts.record("coverage_files", key, project.id, ~N[2026-11-24 10:00:00.000001])
    TotalsWorker.publish(run, 0, reported_at, 0)
    [job] = all_enqueued(worker: TotalsWorker)

    Inserts.record("coverage_run_files", key, project.id, NaiveDateTime.add(reported_at, 1))

    assert perform_job(TotalsWorker, job.args) == :ok
    assert totals(run.test_run_id) == []
  end

  test "publishes the totals anyway once it waited ten minutes", %{project: project} do
    {key, run} = run_row(project)
    Inserts.record("coverage_files", key, project.id, ~N[2026-11-24 10:00:00.000001])
    TotalsWorker.publish(run, 0, NaiveDateTime.utc_now(), 0)
    [job] = all_enqueued(worker: TotalsWorker)

    assert TotalsWorker.perform(%{job | inserted_at: DateTime.add(DateTime.utc_now(), -11, :minute)}) == :ok
    assert [_] = totals(run.test_run_id)
    refute Repo.one(from(i in Insert, where: i.key == ^key, select: i.synced_at))
  end

  test "readers take the report the totals pin, not a newer one the totals don't cover yet", %{
    account: account,
    project: project
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])])
    assert [%{report_shards: [0], report_inserted_at: [pinned]}] = totals(run.id)

    # A retried shard's rows, on this replica before its totals are written.
    insert_report_row(project, run.id, 0, NaiveDateTime.add(pinned, 1), executable_lines: 9)

    assert [%{executable_lines: 2}] = Coverage.merged_files(project.id, run.id)
  end

  test "raw queries pick the reports report_files_for_runs reads: the pinned ones only", %{
    account: account,
    project: project
  } do
    run = CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])])
    [%{report_inserted_at: [pinned]}] = totals(run.id)
    # A retried shard 0 and a shard 1 the totals don't cover yet.
    insert_report_row(project, run.id, 0, NaiveDateTime.add(pinned, 1), executable_lines: 9)
    insert_report_row(project, run.id, 1, NaiveDateTime.add(pinned, 1), executable_lines: 9)

    # Totals that pin nothing: no report of the run is read.
    unpinned_run_id = UUIDv7.generate()
    {_key, row} = run_row(project)
    IngestRepo.insert_all(CoverageRun, [%{row | test_run_id: unpinned_run_id}])
    insert_report_row(project, unpinned_run_id, 0, ~N[2026-11-24 10:00:01.000000], executable_lines: 9)

    run_ids = [run.id, unpinned_run_id]

    %{rows: raw} =
      IngestRepo.query!(
        "SELECT toString(test_run_id), shard_index, report_inserted_at FROM (#{Coverage.pinned_reports_sql()})",
        %{project_id: project.id, run_ids: run_ids}
      )

    read =
      ClickHouseRepo.all(
        from(f in Coverage.report_files_for_runs(project.id, run_ids, lines: false),
          distinct: true,
          select: [f.test_run_id, f.shard_index, f.inserted_at]
        )
      )

    assert raw == [[run.id, 0, pinned]]
    assert read == raw
  end

  defp insert_report_row(project, test_run_id, shard_index, inserted_at, executable_lines: executable_lines) do
    IngestRepo.insert_all(CoverageRunFile, [
      %{
        project_id: project.id,
        test_run_id: test_run_id,
        shard_index: shard_index,
        path: "Sources/A.swift",
        layout_id: 0,
        build_system: "xcode",
        partial: false,
        in_repository: true,
        is_test: false,
        targets: ["App"],
        git_commit_sha: "c1",
        covered_lines: 0,
        executable_lines: executable_lines,
        execution_counts: [],
        function_execution_counts: [],
        function_covered_lines: [],
        inserted_at: inserted_at
      }
    ])
  end

  defp run_row(project) do
    test_run_id = UUIDv7.generate()

    run = %{
      project_id: project.id,
      test_run_id: test_run_id,
      build_system: "xcode",
      coverage_tool: "llvm-cov",
      coverage_tool_version: "",
      git_object_format: "sha1",
      scheme: "App",
      platform: "ios",
      git_commit_sha: "c1",
      covered_lines: 1,
      executable_lines: 2,
      files: 1,
      partial: false,
      version: 7,
      inserted_at: NaiveDateTime.utc_now(),
      report_shards: [],
      report_inserted_at: []
    }

    {Coverage.report_key(test_run_id, 0), run}
  end

  defp totals(test_run_id), do: ClickHouseRepo.all(from(c in CoverageRun, where: c.test_run_id == ^test_run_id))
end
