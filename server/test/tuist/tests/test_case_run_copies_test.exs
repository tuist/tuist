defmodule Tuist.Tests.TestCaseRunCopiesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCaseRunCopies
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "backfill/2" do
    test "copies the rows inside the copy's retention through its view" do
      # Given
      project = ProjectsFixtures.project_fixture()
      now = NaiveDateTime.utc_now()
      shard_id = UUIDv7.generate()

      recent =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          git_commit_sha: "abc",
          inserted_at: NaiveDateTime.add(now, -5, :day)
        )

      older =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          git_commit_sha: "abc",
          inserted_at: NaiveDateTime.add(now, -45, :day)
        )

      _expired =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          git_commit_sha: "abc",
          inserted_at: NaiveDateTime.add(now, -120, :day)
        )

      sharded =
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          shard_id: shard_id,
          shard_index: 2,
          inserted_at: NaiveDateTime.add(now, -5, :day)
        )

      for table <- ~w(test_case_runs_by_commit_v2 test_case_runs_by_test_run_v2 test_case_runs_by_shard_id_v2) do
        IngestRepo.query!(
          "ALTER TABLE #{table} DELETE WHERE project_id = {project_id:Int64} SETTINGS mutations_sync = 2",
          %{project_id: project.id}
        )
      end

      # When
      TestCaseRunCopies.backfill("test_case_runs_by_commit_v2", until: now)
      TestCaseRunCopies.backfill("test_case_runs_by_test_run_v2", until: now)
      TestCaseRunCopies.backfill("test_case_runs_by_shard_id_v2", until: now)

      # Then
      assert copied_ids("test_case_runs_by_commit_v2", project.id) == Enum.sort([recent.id, sharded.id])

      assert copied_ids("test_case_runs_by_test_run_v2", project.id) ==
               Enum.sort([recent.id, older.id, sharded.id])

      assert %{rows: [[^shard_id, 2]]} =
               IngestRepo.query!(
                 "SELECT toString(shard_id), shard_index FROM test_case_runs_by_shard_id_v2 FINAL WHERE project_id = {project_id:Int64}",
                 %{project_id: project.id}
               )
    end

    test "copies each source month in its own statement" do
      # Given
      until = ~N[2026-10-26 12:00:00]

      # When
      ranges = TestCaseRunCopies.backfill("test_case_runs_by_test_run_v2", until: until)

      # Then
      assert ranges == [
               {~N[2026-07-28 12:00:00], ~N[2026-08-01 00:00:00]},
               {~N[2026-08-01 00:00:00], ~N[2026-09-01 00:00:00]},
               {~N[2026-09-01 00:00:00], ~N[2026-10-01 00:00:00]},
               {~N[2026-10-01 00:00:00], ~N[2026-10-26 12:00:00]}
             ]
    end
  end

  defp copied_ids(table, project_id) do
    %{rows: rows} =
      IngestRepo.query!(
        "SELECT DISTINCT toString(id) FROM #{table} FINAL WHERE project_id = {project_id:Int64} ORDER BY 1",
        %{project_id: project_id}
      )

    List.flatten(rows)
  end
end
