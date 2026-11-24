defmodule Tuist.Tests.Coverage.Workers.PinsBackfillWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Workers.PinsBackfillWorker
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{project: ProjectsFixtures.project_fixture(account_id: account.id)}
  end

  test "pins each shard's newest report on totals published without pins, once", %{project: project} do
    legacy = UUIDv7.generate()
    at = ~N[2026-11-20 10:00:00.000000]
    retried_at = ~N[2026-11-20 10:05:00.250000]
    shard_1_at = ~N[2026-11-20 10:02:00.500000]

    totals(project, legacy, version: 3, report_shards: [], report_inserted_at: [])
    run_file(project, legacy, 0, "Sources/A.swift", at, executable_lines: 9)
    # Shard 0 was retried: readers took the newer report.
    run_file(project, legacy, 0, "Sources/A.swift", retried_at, executable_lines: 2)
    run_file(project, legacy, 1, "Sources/B.swift", shard_1_at, executable_lines: 3)

    # Already pinned by a newer report: left as it is.
    pinned = UUIDv7.generate()
    totals(project, pinned, version: 5, report_shards: [], report_inserted_at: [])
    totals(project, pinned, version: 6, report_shards: [0], report_inserted_at: [at])
    run_file(project, pinned, 0, "Sources/A.swift", at, executable_lines: 1)
    run_file(project, pinned, 0, "Sources/A.swift", retried_at, executable_lines: 1)

    # Listed no file: nothing to pin.
    empty = UUIDv7.generate()
    totals(project, empty, version: 1, files: 0, report_shards: [], report_inserted_at: [])

    assert :ok = perform_job(PinsBackfillWorker, %{pass: 1})

    assert [newest | _] = rows(legacy)
    assert {newest.version, newest.report_shards, newest.report_inserted_at} == {4, [0, 1], [retried_at, shard_1_at]}

    assert Map.drop(newest, [:version, :report_shards, :report_inserted_at]) ==
             legacy |> rows() |> List.last() |> Map.drop([:version, :report_shards, :report_inserted_at])

    assert legacy |> rows() |> length() == 2
    assert pinned |> rows() |> length() == 2
    assert empty |> rows() |> length() == 1

    paths =
      ClickHouseRepo.all(
        from(f in Coverage.report_files_for_runs(project.id, [legacy], lines: false),
          order_by: f.path,
          select: {f.path, f.executable_lines}
        )
      )

    assert paths == [{"Sources/A.swift", 2}, {"Sources/B.swift", 3}]
    assert_enqueued(worker: PinsBackfillWorker, args: %{pass: 2})

    assert :ok = perform_job(PinsBackfillWorker, %{pass: 2})
    assert legacy |> rows() |> length() == 2
  end

  test "leaves a run alone that a new report pinned after the pass listed it", %{project: project} do
    run_id = UUIDv7.generate()
    at = ~N[2026-11-20 10:00:00.000000]
    retried_at = ~N[2026-11-20 10:05:00.000000]
    totals(project, run_id, version: 3, report_shards: [], report_inserted_at: [])
    run_file(project, run_id, 0, "Sources/A.swift", at, executable_lines: 1)

    # The retry's totals land between the listing and the insert, pinning the
    # report every replica holds; the retry's rows reached this one already.
    stub(IngestRepo, :query!, fn sql, params, opts ->
      result = call_original(IngestRepo, :query!, [sql, params, opts])

      if sql =~ "ORDER BY project_id, test_run_id" do
        totals(project, run_id, version: 9, report_shards: [0], report_inserted_at: [at])
        run_file(project, run_id, 0, "Sources/A.swift", retried_at, executable_lines: 1)
      end

      result
    end)

    assert :ok = perform_job(PinsBackfillWorker, %{pass: 2})
    assert [%{version: 9, report_inserted_at: [^at]} | _] = rows(run_id)
  end

  defp totals(project, test_run_id, attrs) do
    IngestRepo.insert_all(CoverageRun, [
      Map.merge(
        %{
          project_id: project.id,
          test_run_id: test_run_id,
          build_system: "xcode",
          coverage_tool: "llvm-cov",
          coverage_tool_version: "17",
          git_object_format: "sha1",
          scheme: "App",
          platform: "ios",
          git_commit_sha: "c1",
          covered_lines: 1,
          executable_lines: 5,
          files: 2,
          partial: false,
          inserted_at: ~N[2026-11-20 10:06:00.000000]
        },
        Map.new(attrs)
      )
    ])
  end

  defp run_file(project, test_run_id, shard_index, path, inserted_at, executable_lines: executable_lines) do
    IngestRepo.insert_all(CoverageRunFile, [
      %{
        project_id: project.id,
        test_run_id: test_run_id,
        shard_index: shard_index,
        path: path,
        layout_id: 0,
        build_system: "xcode",
        git_commit_sha: "c1",
        targets: ["App"],
        covered_lines: 0,
        executable_lines: executable_lines,
        execution_counts: [],
        function_execution_counts: [],
        function_covered_lines: [],
        inserted_at: inserted_at
      }
    ])
  end

  defp rows(test_run_id) do
    ClickHouseRepo.all(
      from(c in CoverageRun,
        where: c.test_run_id == ^test_run_id,
        order_by: [desc: c.version],
        select: map(c, ^CoverageRun.__schema__(:fields))
      )
    )
  end
end
