defmodule Tuist.Tests.Coverage.RunInputsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouse.Insert
  alias Tuist.ClickHouse.Inserts
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.RunInputs
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    %{account: user.account, project: project}
  end

  test "a run's report declares what its commit's fold reads, and the gate opens once it is stored", %{
    account: account,
    project: project
  } do
    run =
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
        recompute: false,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1,
            test_cases: [
              %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10},
              %{name: "testSub()", test_suite_name: "MathTests", status: "success", duration: 10}
            ]
          }
        ]
      })

    assert %{"test_runs" => %{row_count: 1}, "test_case_runs" => %{row_count: 2}} = manifest(project, "abc123")
    assert RunInputs.status(project.id, "abc123") == :ready
    assert Enum.all?(Map.values(manifest(project, "abc123")), & &1.synced_at)
    assert manifest(project, "abc123")["test_runs"].key == "#{run.id}/0"
  end

  test "holds the fold until the replica holds every test case run the shard declared", %{project: project} do
    run_id = UUIDv7.generate()
    at = NaiveDateTime.utc_now()
    Inserts.record("test_case_runs", "#{run_id}/1", project.id, at, sha: "c1", rows: 2)

    insert_rows("test_case_runs", [%{id: UUIDv7.generate(), test_run_id: run_id, project_id: project.id, shard_index: 1}])
    # Another shard's rows are not this one's.
    insert_rows("test_case_runs", [%{id: UUIDv7.generate(), test_run_id: run_id, project_id: project.id, shard_index: 0}])
    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows("test_case_runs", [%{id: UUIDv7.generate(), test_run_id: run_id, project_id: project.id, shard_index: 1}])
    assert RunInputs.status(project.id, "c1") == :ready
  end

  test "counts only a retried shard's own test case runs, not its earlier attempt's", %{project: project} do
    {other, run_id} = {UUIDv7.generate(), UUIDv7.generate()}
    # Another run of the commit, declared earlier, lowers the window the query reads.
    Inserts.record("test_case_runs", "#{other}/0", project.id, ~N[2026-11-24 10:00:00.000000], sha: "c1", rows: 1)
    insert_rows("test_case_runs", [%{id: UUIDv7.generate(), test_run_id: other, project_id: project.id, shard_index: 0}])

    first_attempt = ~N[2026-11-24 10:01:00.000000]

    insert_rows(
      "test_case_runs",
      for(
        _ <- 1..2,
        do: %{
          id: UUIDv7.generate(),
          test_run_id: run_id,
          project_id: project.id,
          shard_index: 2,
          inserted_at: first_attempt
        }
      )
    )

    retry = ~N[2026-11-24 10:02:00.000000]
    Inserts.record("test_case_runs", "#{run_id}/2", project.id, retry, sha: "c1", rows: 2)
    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows(
      "test_case_runs",
      for(
        _ <- 1..2,
        do: %{id: UUIDv7.generate(), test_run_id: run_id, project_id: project.id, shard_index: 2, inserted_at: retry}
      )
    )

    assert RunInputs.status(project.id, "c1") == :ready
  end

  test "counts a run's row at the version the report wrote", %{project: project} do
    run_id = UUIDv7.generate()
    written_at = ~N[2026-11-24 10:00:05.000001]
    Inserts.record("test_runs", "#{run_id}/0", project.id, written_at, sha: "c1", rows: 1)

    insert_rows("test_runs", [%{id: run_id, project_id: project.id, inserted_at: ~N[2026-11-24 10:00:00.000001]}])
    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows("test_runs", [%{id: run_id, project_id: project.id, inserted_at: written_at}])
    assert RunInputs.status(project.id, "c1") == :ready
  end

  test "holds the fold until every retried shard's own rows are stored, when a re-run retries two of three", %{
    project: project
  } do
    run_id = UUIDv7.generate()

    row = fn shard, at ->
      %{id: UUIDv7.generate(), test_run_id: run_id, project_id: project.id, shard_index: shard, inserted_at: at}
    end

    first = ~N[2026-11-24 10:00:00.000001]

    # The first attempt: three shards of two tests each, all seen synced.
    for shard <- 0..2 do
      Inserts.record("test_case_runs", "#{run_id}/#{shard}", project.id, first, sha: "c1", rows: 2)
      insert_rows("test_case_runs", [row.(shard, first), row.(shard, first)])
    end

    assert RunInputs.status(project.id, "c1") == :ready

    # Re-running the failed jobs retries shards 0 and 2, at different times.
    {retry_0, retry_2} = {~N[2026-11-24 10:05:00.000001], ~N[2026-11-24 10:06:00.000001]}
    Inserts.record("test_case_runs", "#{run_id}/0", project.id, retry_0, sha: "c1", rows: 2)
    Inserts.record("test_case_runs", "#{run_id}/2", project.id, retry_2, sha: "c1", rows: 2)

    insert_rows("test_case_runs", [row.(0, retry_0), row.(0, retry_0)])
    # Shard 2's first attempt plus one retried row would make two if counted together.
    insert_rows("test_case_runs", [row.(2, retry_2)])
    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows("test_case_runs", [row.(2, retry_2)])
    assert RunInputs.status(project.id, "c1") == :ready
  end

  test "takes a shard's version of the run's row as stored once a later shard's version replaced it", %{
    project: project
  } do
    run_id = UUIDv7.generate()
    {shard_0_at, shard_1_at} = {~N[2026-11-24 10:00:05.000001], ~N[2026-11-24 10:00:09.000001]}
    Inserts.record("test_runs", "#{run_id}/0", project.id, shard_0_at, sha: "c1", rows: 1)
    Inserts.record("test_runs", "#{run_id}/1", project.id, shard_1_at, sha: "c1", rows: 1)

    # Shard 0's version alone isn't shard 1's.
    insert_rows("test_runs", [%{id: run_id, project_id: project.id, inserted_at: shard_0_at}])
    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows("test_runs", [%{id: run_id, project_id: project.id, inserted_at: shard_1_at}])
    assert RunInputs.status(project.id, "c1") == :ready

    # What a replica holds once a merge kept only the newest version
    # (`ReplacingMergeTree(inserted_at)`), which the test sandbox can't do.
    merged = UUIDv7.generate()
    Inserts.record("test_runs", "#{merged}/0", project.id, shard_0_at, sha: "c2", rows: 1)
    Inserts.record("test_runs", "#{merged}/1", project.id, shard_1_at, sha: "c2", rows: 1)
    insert_rows("test_runs", [%{id: merged, project_id: project.id, inserted_at: shard_1_at}])
    assert RunInputs.status(project.id, "c2") == :ready
  end

  test "holds the fold while a declared insert is still being written, until it is too old to wait for", %{
    project: project
  } do
    Inserts.record("test_case_runs", "#{UUIDv7.generate()}/0", project.id, NaiveDateTime.utc_now(), sha: "c1")
    assert RunInputs.status(project.id, "c1") == :wait

    Repo.update_all(Insert, set: [inserted_at: DateTime.add(DateTime.utc_now(), -11, :minute)])
    assert {:incomplete, [%Insert{clickhouse_table: "test_case_runs"}]} = RunInputs.status(project.id, "c1")
  end

  test "holds the fold until the replica holds the targets a run's command event stored", %{project: project} do
    event_id = UUIDv7.generate()
    targets_at = ~N[2026-11-24 10:00:07]

    event = %{
      id: event_id,
      project_id: project.id,
      test_run_id: UUIDv7.generate(),
      git_commit_sha: "c1",
      created_at: ~N[2026-11-24 10:00:06.000001]
    }

    assert :ok = RunInputs.event_written(event, %{targets: 2, inserted_at: targets_at}, true)
    insert_rows("command_events", [%{id: event_id, project_id: project.id, name: "test"}])

    insert_rows("xcode_targets", [
      %{id: UUIDv7.generate(), command_event_id: event_id, inserted_at: targets_at},
      # Another event's target is not this one's.
      %{id: UUIDv7.generate(), command_event_id: UUIDv7.generate(), inserted_at: targets_at}
    ])

    assert RunInputs.status(project.id, "c1") == :wait

    insert_rows("xcode_targets", [%{id: UUIDv7.generate(), command_event_id: event_id, inserted_at: targets_at}])
    assert RunInputs.status(project.id, "c1") == :ready
  end

  test "a command event that landed before its run's report declared the run joins the commit with that report", %{
    project: project
  } do
    # A shard that reported no coverage sent this event, without a hit; a later shard reports coverage.
    run = %Test{id: UUIDv7.generate(), project_id: project.id, git_commit_sha: "c1"}

    event = %{
      id: UUIDv7.generate(),
      project_id: project.id,
      test_run_id: run.id,
      git_commit_sha: "c1",
      created_at: NaiveDateTime.utc_now()
    }

    assert :ok = RunInputs.event_written(event, %{targets: 2, inserted_at: NaiveDateTime.utc_now()}, false)
    assert manifest(project, "c1") == %{}

    RunInputs.declare(run, 1, %{})

    assert %{"command_events" => %{key: key, row_count: 1}, "xcode_targets" => %{row_count: 2}} =
             manifest(project, "c1")

    assert key == event.id
  end

  test "a fold snoozes, writing nothing, until its runs' inputs are stored", %{account: account, project: project} do
    CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
      recompute: false
    })

    key = "#{UUIDv7.generate()}/0"
    Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123")
    args = %{"project_id" => project.id, "git_commit_sha" => "abc123"}
    # No fold pending after this one, which would otherwise take over.
    Repo.delete_all(Oban.Job)

    assert perform_job(CommitWorker, args) == {:snooze, 5}
    assert Commits.summary(project.id, "abc123") == nil

    Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123", rows: 0)
    assert perform_job(CommitWorker, args) == :ok
    assert %{covered_lines: 1} = Commits.summary(project.id, "abc123")
  end

  describe "a fold past the deadline of an input that never reached every replica" do
    # A run whose report and tests are stored, and another input of the
    # commit declared `minutes` ago and never written.
    defp folded_without_an_input(project, account, minutes) do
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
        recompute: false,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1,
            test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 10}]
          }
        ]
      })

      key = "#{UUIDv7.generate()}/0"
      Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123")
      aged = DateTime.add(DateTime.utc_now(), -minutes, :minute)
      Repo.update_all(from(i in Insert, where: i.key == ^key), set: [inserted_at: aged])
      Repo.delete_all(Oban.Job)
      key
    end

    test "publishes the figure as a lower bound, derives nothing from the runs' tests, and folds once more", %{
      account: account,
      project: project
    } do
      key = folded_without_an_input(project, account, 11)
      args = %{"project_id" => project.id, "git_commit_sha" => "abc123"}

      assert perform_job(CommitWorker, args) == :ok
      summary = Commits.summary(project.id, "abc123")
      assert %{covered_lines: 1, reported_kind: "partial"} = summary
      assert :run_data_unavailable in Commits.gap_reasons(summary)
      assert Repo.aggregate(Snapshot, :count) == 0

      assert [follow_up] = all_enqueued(worker: CommitWorker)
      assert DateTime.diff(follow_up.scheduled_at, DateTime.utc_now()) in 590..600

      # The input arrives late, and the follow-up fold reads all of it.
      Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123", rows: 0)
      assert perform_job(CommitWorker, args) == :ok
      summary = Commits.summary(project.id, "abc123")
      assert summary.reported_kind != "partial"
      refute :run_data_unavailable in Commits.gap_reasons(summary)
      assert Repo.aggregate(Snapshot, :count) > 0
    end

    test "folds no more once the input is twice the deadline old", %{account: account, project: project} do
      folded_without_an_input(project, account, 21)

      assert perform_job(CommitWorker, %{"project_id" => project.id, "git_commit_sha" => "abc123"}) == :ok
      assert %{reported_kind: "partial"} = Commits.summary(project.id, "abc123")
      assert all_enqueued(worker: CommitWorker) == []
    end

    test "completes the commit on the signal, as a lower bound", %{account: account, project: project} do
      folded_without_an_input(project, account, 11)

      assert %{complete: true, reported_kind: "partial"} =
               summary = Commits.signal_complete(project, "abc123", wait_ms: 0)

      assert :run_data_unavailable in Commits.gap_reasons(summary)
      assert [_follow_up] = all_enqueued(worker: CommitWorker)
    end
  end

  test "a completion signal the stored inputs can't serve yet is kept for the fold", %{
    account: account,
    project: project
  } do
    CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])])
    key = "#{UUIDv7.generate()}/0"
    Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123")

    assert Commits.signal_complete(project, "abc123", wait_ms: 0) == nil
    assert %{complete: false} = Commits.summary(project.id, "abc123")

    Inserts.record("test_case_runs", key, project.id, NaiveDateTime.utc_now(), sha: "abc123", rows: 0)
    assert :ok = perform_job(CommitWorker, %{"project_id" => project.id, "git_commit_sha" => "abc123"})
    assert %{complete: true, completeness: "signal"} = Commits.summary(project.id, "abc123")
  end

  defp manifest(project, sha) do
    from(i in Insert, where: i.project_id == ^project.id and i.git_commit_sha == ^sha)
    |> Repo.all()
    |> Map.new(&{&1.clickhouse_table, &1})
  end

  defp insert_rows(table, rows) do
    for row <- rows do
      row = if table == "command_events", do: row, else: Map.put_new(row, :inserted_at, NaiveDateTime.utc_now())
      columns = row |> Map.keys() |> Enum.map_join(", ", &to_string/1)
      values = row |> Map.values() |> Enum.map_join(", ", &literal/1)
      IngestRepo.query!("INSERT INTO #{table} (#{columns}) VALUES (#{values})")
    end
  end

  defp literal(value) when is_integer(value), do: Integer.to_string(value)
  defp literal(%NaiveDateTime{} = at), do: "'#{NaiveDateTime.to_iso8601(at)}'"
  defp literal(value) when is_binary(value), do: "'#{value}'"
end
