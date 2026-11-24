defmodule Tuist.Tests.Coverage.Workers.RunFilesBackfillWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Workers.PinsBackfillWorker
  alias Tuist.Tests.Coverage.Workers.RunFilesBackfillWorker
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # A run row as `coverage_files` stored it before the split.
  defp old_row(project, run_id, shard, path, lines, counts, functions, inserted_at) do
    %{
      id: UUIDv7.generate(),
      test_run_id: run_id,
      project_id: project.id,
      shard_index: shard,
      scope_kind: "run",
      scope_id: "",
      path: path,
      git_blob_id: "blob-" <> path,
      targets: ["App"],
      git_commit_sha: "a",
      covered_lines: Enum.count(counts, &(&1 > 0)),
      executable_lines: length(lines),
      line_numbers: lines,
      execution_counts: counts,
      branch_line_numbers: [],
      branch_covered: [],
      branch_total: [],
      function_names: Enum.map(functions, &elem(&1, 0)),
      function_line_numbers: Enum.map(functions, &elem(&1, 1)),
      function_execution_counts: Enum.map(functions, &elem(&1, 2)),
      function_covered_lines: Enum.map(functions, &elem(&1, 3)),
      function_executable_lines: Enum.map(functions, &elem(&1, 4)),
      inserted_at: inserted_at
    }
  end

  defp copied_rows(run_id) do
    ClickHouseRepo.one(from(f in CoverageRunFile, where: f.test_run_id == ^run_id, select: count()))
  end

  test "copies the run rows coverage_files holds, once, with their layouts" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    run_id = UUIDv7.generate()
    reported_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 86_400)

    old = [
      old_row(project, run_id, 0, "Sources/A.swift", [1, 2, 4], [3, 0, 1], [{"a()", 1, 3, 2, 3}], reported_at),
      # Nothing ran in this shard: the copy stores no counts, and reads give zeros.
      old_row(project, run_id, 1, "Sources/A.swift", [1, 2, 4], [0, 0, 0], [{"a()", 1, 0, 0, 3}], reported_at),
      old_row(project, run_id, 0, "Sources/B.swift", [], [], [], reported_at)
    ]

    IngestRepo.insert_all(CoverageFile, old)

    # Evidence stays where it is.
    IngestRepo.insert_all(CoverageFile, [
      %{
        old_row(project, run_id, 0, "Sources/A.swift", [1], [], [], reported_at)
        | scope_kind: "test",
          scope_id: "AppTests\x1FATests\x1Ftest()"
      }
    ])

    assert :ok = perform_job(RunFilesBackfillWorker, %{pass: 2})
    assert copied_rows(run_id) == 3

    # The run's totals predate the pins, which the pins backfill writes next.
    IngestRepo.insert_all(CoverageRun, [
      %{
        project_id: project.id,
        test_run_id: run_id,
        git_commit_sha: "a",
        covered_lines: 2,
        executable_lines: 3,
        files: 2,
        version: 1,
        inserted_at: reported_at,
        report_shards: [],
        report_inserted_at: []
      }
    ])

    assert :ok = perform_job(PinsBackfillWorker, %{pass: 2})

    rows = Commits.file_rows(project.id, [run_id], "Sources/A.swift")

    # Read back as the rows they were, but for what the copy doesn't keep.
    dropped = [
      :id,
      :project_id,
      :git_commit_sha,
      :scope_kind,
      :scope_id,
      :branch_line_numbers,
      :branch_covered,
      :branch_total
    ]

    expected = old |> Enum.filter(&(&1.path == "Sources/A.swift")) |> Enum.map(&Map.drop(&1, dropped))

    assert rows |> Enum.map(&Map.take(&1, Map.keys(hd(expected)))) |> Enum.sort_by(& &1.shard_index) == expected

    assert [%{git_blob_id: "blob-Sources/B.swift", line_numbers: [], execution_counts: []}] =
             Commits.file_rows(project.id, [run_id], "Sources/B.swift")

    # Each path's week starts on its own weekday, as a report written then names it.
    reported_on = NaiveDateTime.to_date(reported_at)

    assert from(f in CoverageRunFile, where: f.test_run_id == ^run_id, distinct: true, select: {f.path, f.epoch})
           |> ClickHouseRepo.all()
           |> Enum.sort() ==
             for(path <- ["Sources/A.swift", "Sources/B.swift"], do: {path, Coverage.layout_epoch(path, reported_on)})

    # A second pass, as the one an hour later, copies nothing again.
    assert :ok = perform_job(RunFilesBackfillWorker, %{pass: 2})
    assert copied_rows(run_id) == 3
  end

  test "schedules a second pass after the first" do
    assert :ok = perform_job(RunFilesBackfillWorker, %{pass: 1})
    assert_enqueued(worker: RunFilesBackfillWorker, args: %{pass: 2})
  end
end
