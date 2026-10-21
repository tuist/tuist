defmodule Tuist.OnceEvents.TestReportIngestorTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.TestCaseCompleted
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.TestReportIngestor
  alias Tuist.OnceEvents.Workers.PublishTestReportWorker
  alias Tuist.Tests.Test.Buffer
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    at = DateTime.utc_now()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: "once-test-run-#{System.unique_integer([:positive])}",
        kind: "test",
        command_display: "once test //...",
        git_rev: "abc123",
        git_branch: "main",
        is_ci: true,
        started_at: at
      })

    %{project: project, run: run, at: at}
  end

  defp stage_case(run, attrs) do
    OnceEvents.ingest_test_case_run(
      run,
      Map.merge(
        %{
          target_execution_id: "cargo_aqua",
          suite_id: "unit",
          case_id: "case",
          name: "case",
          attempt: 1,
          result: "passed",
          duration_ms: 10,
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  defp finalize(run, exit_status \\ 0) do
    {:ok, finalized} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: exit_status,
        wall_ms: 1234,
        finalized_at: DateTime.utc_now()
      })

    finalized
  end

  defp case_run_count(test_run_id) do
    TestCaseRun
    |> where([c], c.test_run_id == ^test_run_id)
    |> Tuist.IngestRepo.aggregate(:count)
  end

  test "intent and immutable chunks precede publication, and acknowledged progress resumes without replay", %{run: run} do
    stage_case(run, %{})
    run = finalize(run)
    assert {:ok, intent} = TestReportIngestor.enqueue(run)
    assert intent.state == "preparing"
    assert intent.payload == nil

    assert_enqueued(
      worker: PublishTestReportWorker,
      queue: "once_test_reports",
      args: %{run_id: run.id, phase: "publish"}
    )

    assert {:ok, publication} = TestReportIngestor.prepare_snapshot(run.id)
    %{version: 2, test: test, chunks: [first | remaining]} = :erlang.binary_to_term(publication.payload, [:safe])
    assert Tuist.Repo.get!(OnceEvents.Run, run.id).test_report_published_at
    assert publication.state == "pending"
    assert Tuist.ClickHouseRepo.get(Tuist.Tests.Test, test.id) == nil
    {schema, rows, _token} = first
    Tuist.IngestRepo.insert_all(schema, rows)

    publication
    |> Ecto.Changeset.change(
      next_chunk: 1,
      state: "publishing",
      owner: "dead-owner",
      updated_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -1_000)
    )
    |> Tuist.Repo.update!()

    parent = self()

    stub(Tuist.IngestRepo, :insert_all, fn schema, rows, opts ->
      send(parent, {:chunk_token, opts[:settings][:insert_deduplication_token]})
      Mimic.call_original(Tuist.IngestRepo, :insert_all, [schema, rows, opts])
    end)

    assert {:ok, _} = TestReportIngestor.publish_prepared(run.id)
    for {_, _, token} <- remaining, do: assert_receive({:chunk_token, "once-report:" <> ^token})
    refute_receive {:chunk_token, _}
    assert Tuist.Repo.get!(OnceEvents.Run, run.id).test_report_published_at
  end

  test "the unchanged legacy claim protocol cannot win after a durable new reservation", %{run: run} do
    stage_case(run, %{})
    assert {:ok, publication} = TestReportIngestor.enqueue(finalize(run))

    assert {0, _} =
             Tuist.Repo.update_all(
               from(r in OnceEvents.Run, where: r.id == ^run.id and is_nil(r.test_report_published_at)),
               set: [test_report_published_at: DateTime.utc_now()]
             )

    assert publication.state == "preparing"
  end

  test "snapshot failure retains the durable intent without rejecting a completed event", %{run: run} do
    stage_case(run, %{})
    run = finalize(run)
    stub(Tuist.Tests, :create_test, fn _ -> raise "capture failed" end)
    assert {:ok, _} = TestReportIngestor.enqueue_safely(run)
    assert {:error, :preparation_failed} = TestReportIngestor.prepare_snapshot(run.id)
    assert Tuist.Repo.get!(OnceEvents.Run, run.id).test_report_published_at
    publication = Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id)
    assert publication.state == "preparing"
    assert publication.preparation_attempts == 1
    assert publication.preparation_error == "builder_failed"
    assert publication.owner == nil
    refute Tuist.Ingestion.Capture.active?()
  end

  test "preparation failures alert, stop after the durable attempt limit and require explicit retry", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.enqueue(finalize(run))
    parent = self()
    handler = "once-preparation-#{Ecto.UUID.generate()}"

    :telemetry.attach(
      handler,
      [:tuist, :once_events, :test_report_publication],
      fn _, _, meta, pid -> send(pid, {:publication_outcome, meta.outcome}) end,
      parent
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    stub(Tuist.Tests, :create_test, fn _ -> raise "invalid staged source" end)
    for _ <- 1..7, do: assert({:error, :preparation_failed} = TestReportIngestor.prepare_snapshot(run.id))
    assert {:error, :publication_preparation_failed} = TestReportIngestor.prepare_snapshot(run.id)
    for _ <- 1..8, do: assert_receive({:publication_outcome, :preparation_failed})
    publication = Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id)
    assert publication.state == "failed_preparation"
    assert publication.preparation_attempts == 8
    assert publication.payload == nil
    Tuist.Repo.delete_all(from(j in Oban.Job, where: fragment("?->>'run_id'", j.args) == ^run.id))
    assert :ok = TestReportIngestor.recover_recent()
    assert all_enqueued(worker: PublishTestReportWorker, args: %{run_id: run.id, phase: "publish"}) == []
    assert {:error, :publication_preparation_failed} = TestReportIngestor.prepare_snapshot(run.id)
    refute_receive {:publication_outcome, _}
    assert {:ok, reset} = TestReportIngestor.retry_preparation(run.id)
    assert reset.preparation_attempts == 0
    assert reset.preparation_error == nil
    stub(Tuist.Tests, :create_test, fn attrs -> Mimic.call_original(Tuist.Tests, :create_test, [attrs]) end)
    assert {:ok, %{state: "pending"}} = TestReportIngestor.prepare_snapshot(run.id)
  end

  test "permanent preparation failures stop immediately and retain source", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.enqueue(finalize(run))
    stub(Tuist.Projects, :get_project_by_id, fn _ -> nil end)
    assert {:error, :publication_preparation_failed} = TestReportIngestor.prepare_snapshot(run.id)
    publication = Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id)
    assert publication.state == "failed_preparation"
    assert publication.preparation_error == "project_not_found"
    assert publication.preparation_attempts == 1
    assert OnceEvents.list_test_case_runs(run) != []
  end

  test "killed preparation attempts are bounded across replacement jobs", %{run: run} do
    stage_case(run, %{})
    assert {:ok, publication} = TestReportIngestor.enqueue(finalize(run))

    publication
    |> Ecto.Changeset.change(
      owner: "dead-preparer",
      preparation_attempts: 8,
      updated_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -1_000)
    )
    |> Tuist.Repo.update!()

    reject(&Tuist.Tests.create_test/1)
    assert {:error, :publication_preparation_failed} = TestReportIngestor.prepare_snapshot(run.id)
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id).preparation_error == "attempt_limit"
  end

  test "a soft deadline yields between acknowledged chunks and the next job resumes without replay", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.enqueue(finalize(run))
    assert {:ok, publication} = TestReportIngestor.prepare_snapshot(run.id)
    %{chunks: [{_, _, first_token} | remaining]} = :erlang.binary_to_term(publication.payload, [:safe])
    clock = :atomics.new(1, [])
    parent = self()

    stub(Tuist.IngestRepo, :insert_all, fn schema, rows, opts ->
      send(parent, {:chunk_token, opts[:settings][:insert_deduplication_token]})
      result = Mimic.call_original(Tuist.IngestRepo, :insert_all, [schema, rows, opts])
      :atomics.put(clock, 1, 10)
      result
    end)

    assert {:ok, :yielded} =
             TestReportIngestor.publish_prepared(run.id, budget_ms: 10, clock: fn -> :atomics.get(clock, 1) end)

    assert_receive {:chunk_token, "once-report:" <> ^first_token}
    refute_receive {:chunk_token, _}
    current = Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id)
    assert current.state == "pending"
    assert current.next_chunk == 1
    assert current.in_flight_chunk == nil
    assert current.owner == nil
    assert current.payload == publication.payload
    assert {:ok, _} = TestReportIngestor.publish_prepared(run.id)
    for {_, _, token} <- remaining, do: assert_receive({:chunk_token, "once-report:" <> ^token})
    refute_receive {:chunk_token, _}
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id).state == "published"
  end

  test "an acknowledged ClickHouse write with a lost response is never blindly replayed", %{run: run} do
    stage_case(run, %{})
    run = finalize(run)
    assert {:ok, _} = TestReportIngestor.enqueue(run)
    assert {:ok, publication} = TestReportIngestor.prepare_snapshot(run.id)
    parent = self()

    stub(Tuist.IngestRepo, :insert_all, fn schema, rows, opts ->
      result = Mimic.call_original(Tuist.IngestRepo, :insert_all, [schema, rows, opts])
      send(parent, {:attempted, schema, result})
      raise "response lost after insert"
    end)

    assert {:error, :publication_uncertain} = TestReportIngestor.publish_prepared(run.id)
    assert_receive {:attempted, _, _}
    assert {:error, :publication_uncertain} = TestReportIngestor.publish_prepared(run.id)
    refute_receive {:attempted, _, _}
    current = Tuist.Repo.get!(OnceEvents.TestReportPublication, publication.id)
    assert current.state == "uncertain"
    assert current.in_flight_chunk == 0
    assert current.next_chunk == 0
    assert current.payload == publication.payload
    assert current.state != "published"
    assert {:error, :not_failed_preparation} = TestReportIngestor.retry_preparation(run.id)
    # This fixture KNOWS the first write committed. Reconciliation acknowledges
    # that exact chunk; a real operator must establish quiescence and contents.
    assert {:ok, _} = TestReportIngestor.reconcile_chunk(run.id, current.owner, 0, :present)
    assert {:error, :stale_reconciliation} = TestReportIngestor.reconcile_chunk(run.id, current.owner, 0, :present)

    stub(Tuist.IngestRepo, :insert_all, fn schema, rows, opts ->
      send(parent, {:resumed_token, opts[:settings][:insert_deduplication_token]})
      Mimic.call_original(Tuist.IngestRepo, :insert_all, [schema, rows, opts])
    end)

    %{chunks: [{_, _, first_token} | _]} = :erlang.binary_to_term(publication.payload, [:safe])
    assert {:ok, _} = TestReportIngestor.publish_prepared(run.id)
    refute_receive {:resumed_token, "once-report:" <> ^first_token}
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id).state == "published"
  end

  test "a proven pool checkout failure can retry without becoming an uncertain write", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.enqueue(finalize(run))
    counter = :atomics.new(1, [])
    parent = self()

    stub(Tuist.IngestRepo, :insert_all, fn schema, rows, opts ->
      send(parent, {:insert_opts, opts})

      if :atomics.add_get(counter, 1, 1) == 1 do
        raise DBConnection.ConnectionError, message: "checkout queue full", reason: :queue_timeout
      else
        Mimic.call_original(Tuist.IngestRepo, :insert_all, [schema, rows, opts])
      end
    end)

    assert {:error, :publication_checkout_timeout} = TestReportIngestor.publish_prepared(run.id)
    assert_receive {:insert_opts, opts}
    assert opts[:retry] == false
    assert opts[:checkout_retries] == 0
    publication = Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id)
    assert publication.state == "pending"
    assert publication.in_flight_chunk == nil
    assert publication.next_chunk == 0
    assert {:ok, _} = TestReportIngestor.publish_prepared(run.id)
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id).state == "published"
  end

  test "an expired owner with an in-flight chunk requires reconciliation rather than takeover", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.enqueue(finalize(run))
    assert {:ok, publication} = TestReportIngestor.prepare_snapshot(run.id)

    publication
    |> Ecto.Changeset.change(
      state: "publishing",
      owner: "dead-owner",
      in_flight_chunk: 0,
      updated_at: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -1_000)
    )
    |> Tuist.Repo.update!()

    parent = self()

    stub(Tuist.IngestRepo, :insert_all, fn _, _, _ ->
      send(parent, :unsafe_replay)
      {0, nil}
    end)

    assert {:error, :publication_uncertain} = TestReportIngestor.publish_prepared(run.id)
    refute_receive :unsafe_replay
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, publication.id).state == "uncertain"
  end

  test "durable intent recovery is independent of the two-hour terminal-run scan", %{run: run} do
    stage_case(run, %{})
    run = finalize(run)
    run |> Ecto.Changeset.change(finalized_at: DateTime.add(DateTime.utc_now(), -86_400)) |> Tuist.Repo.update!()
    assert {:ok, _} = TestReportIngestor.enqueue(run)
    jobs = all_enqueued(worker: PublishTestReportWorker)
    ids = Enum.map(jobs, & &1.id)
    Tuist.Repo.update_all(from(j in Oban.Job, where: j.id in ^ids), set: [state: "discarded"])
    assert :ok = TestReportIngestor.recover_recent()
    assert [_] = all_enqueued(worker: PublishTestReportWorker)
  end

  test "retrying optional follow-ups does not enqueue created-case webhooks twice", %{run: run} do
    stage_case(run, %{})
    assert {:ok, _} = TestReportIngestor.publish(finalize(run))
    parent = self()

    stub(Tuist.Tests, :finish_captured_effects, fn _ ->
      send(parent, :effects_dispatched)
      %{run_id: Ecto.UUID.generate(), phase: "effect"} |> PublishTestReportWorker.new() |> Oban.insert!()
      :ok
    end)

    stub(Tuist.Tests, :finish_test_publication, fn _ -> raise "optional followup failed" end)
    job = %Oban.Job{args: %{"run_id" => run.id, "phase" => "followups"}}
    assert_raise RuntimeError, fn -> PublishTestReportWorker.perform(job) end
    assert_receive :effects_dispatched
    assert Tuist.Repo.get!(OnceEvents.TestReportPublication, run.id).effects_dispatched_at
    stub(Tuist.Tests, :finish_test_publication, fn _ -> :ok end)
    assert :ok = PublishTestReportWorker.perform(job)
    refute_receive :effects_dispatched
  end

  test "a case that failed then passed on retry is recorded as flaky", %{run: run, project: project} do
    # Once retries in place and reports each attempt as its own event, so the
    # repetitions are the only evidence of flakiness.
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed", duration_ms: 10})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "passed", duration_ms: 12})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    # The verdict is the final attempt's, and the run is marked flaky.
    assert test.status == "success"
    assert test.is_flaky

    Buffer.flush()
    assert {:ok, %{is_flaky: true}} = Tuist.Tests.get_test(test.id)
    assert project.id == test.project_id
  end

  test "a case that keeps failing is not flaky", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed"})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "failed"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    refute test.is_flaky
    assert test.status == "failure"
  end

  test "retries collapse to one case rather than counting twice", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a", attempt: 1, result: "failed", duration_ms: 10})
    stage_case(run, %{case_id: "a", name: "a", attempt: 2, result: "passed", duration_ms: 12})
    stage_case(run, %{case_id: "b", name: "b", attempt: 1, result: "passed", duration_ms: 5})

    assert {:ok, first} = TestReportIngestor.publish(finalize(run))

    Buffer.flush()
    assert case_run_count(first.id) == 2
  end

  test "a quarantined case is flagged on the published run", %{run: run, project: project} do
    stage_case(run, %{case_id: "muted_one", name: "muted_one", result: "failed"})

    # Quarantine the case before the run started. Without the marking step the
    # shared store never learns it is quarantined, so it keeps failing runs.
    identity = Tuist.Tests.generate_test_case_id(project.id, "muted_one", "cargo_aqua", "unit")

    Tuist.IngestRepo.insert_all(Tuist.Tests.TestCaseState, [
      %{
        project_id: project.id,
        test_case_id: identity,
        state: "muted",
        is_flaky: true,
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.to_naive()
      }
    ])

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    Buffer.flush()

    quarantined =
      TestCaseRun
      |> where([c], c.test_run_id == ^test.id and c.is_quarantined == true)
      |> Tuist.IngestRepo.aggregate(:count)

    assert quarantined == 1
  end

  test "a build run with no test cases publishes nothing", %{run: run} do
    assert TestReportIngestor.publish(finalize(run)) == {:ok, :no_test_cases}
  end

  test "a finished test run lands in the shared store as a Once run", %{run: run, project: project} do
    stage_case(run, %{case_id: "a", name: "a", result: "passed", duration_ms: 10})
    stage_case(run, %{case_id: "b", name: "b", result: "failed", duration_ms: 20})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    assert test.build_system == "once"
    assert test.once_run_id == run.run_id
    assert test.project_id == project.id
    # Branch, commit and CI all have to reach the shared row: flaky detection
    # and quarantine key off them, so a build-system label alone is not enough.
    assert test.git_branch == "main"
    assert test.git_commit_sha == "abc123"
    assert test.git_ref == "refs/heads/main"
    assert test.is_ci
    assert test.status == "failure"
  end

  test "every Once case result maps onto the shared enum", %{run: run, project: project} do
    # Driven through the projector rather than by writing staged strings, so
    # the proto values a client actually sends are what gets mapped. An
    # earlier version of this test wrote the strings directly and missed that
    # unknown results were being recorded as passes.
    results = [
      {:TEST_CASE_RESULT_PASSED, "success"},
      {:TEST_CASE_RESULT_FAILED, "failure"},
      {:TEST_CASE_RESULT_SKIPPED, "skipped"},
      {:TEST_CASE_RESULT_ERRORED, "failure"},
      {:TEST_CASE_RESULT_TIMED_OUT, "failure"},
      {:TEST_CASE_RESULT_CANCELLED, "skipped"},
      {:TEST_CASE_RESULT_UNKNOWN, "skipped"},
      {:TEST_CASE_RESULT_UNSPECIFIED, "skipped"}
    ]

    for {result, _expected} <- results do
      Projector.project(
        %RunEvent{
          epoch_ms: 1_789_405_000_000,
          payload:
            {:test_case_completed,
             %TestCaseCompleted{
               test_case_execution_id: "cargo_aqua",
               suite_id: "unit",
               case_id: to_string(result),
               name: to_string(result),
               attempt: 1,
               result: result
             }}
        },
        project.id,
        run.run_id
      )
    end

    assert {:ok, test} = TestReportIngestor.publish(finalize(run, 1))

    Buffer.flush()

    stored =
      TestCaseRun
      |> where([c], c.test_run_id == ^test.id)
      |> select([c], {c.name, c.status})
      |> Tuist.IngestRepo.all()
      |> Map.new()

    for {result, expected} <- results do
      assert stored[to_string(result)] == expected,
             "#{result} should store as #{expected}, got #{inspect(stored[to_string(result)])}"
    end
  end

  test "an interrupted run does not manufacture failures", %{run: run} do
    # Cancelled cases never reached a verdict. Counting them as failures would
    # invent failure and flakiness signals out of an interrupted run.
    stage_case(run, %{case_id: "a", name: "a", result: "cancelled"})
    stage_case(run, %{case_id: "b", name: "b", result: "cancelled"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))
    assert test.status == "skipped"
  end

  test "a replayed RunCompleted does not publish the run twice", %{run: run} do
    stage_case(run, %{case_id: "a", name: "a"})
    finalized = finalize(run)

    assert {:ok, first} = TestReportIngestor.publish(finalized)

    # `create_test/1` is not a single atomic write. The run row dedupes on its
    # derived id, but the module, suite and case children are appended, so
    # without a publication guard a replay silently doubles every test case.
    # Asserting on the returned run alone did not catch that.
    # Both callers hold the run as it was BEFORE the first publish, which is
    # what two pods projecting the same replayed event would have. A read
    # check would let both through; the claim is a conditional update.
    assert {:ok, :already_published} = TestReportIngestor.publish(finalized)
    assert {:ok, :already_published} = TestReportIngestor.publish(finalized)

    Buffer.flush()

    assert case_run_count(first.id) == 1
  end

  test "the published run is readable back from the shared store", %{run: run, project: project} do
    stage_case(run, %{case_id: "a", name: "a", result: "passed"})

    assert {:ok, test} = TestReportIngestor.publish(finalize(run))

    # `create_test/1` writes the run through `Test.Buffer`, so asserting on
    # the returned struct alone proves nothing about persistence. Flush and
    # read it back.
    Buffer.flush()

    assert {:ok, %{build_system: "once", once_run_id: once_run_id, project_id: project_id}} =
             Tuist.Tests.get_test(test.id)

    assert once_run_id == run.run_id
    assert project_id == project.id
  end

  test "the run id is scoped by project, since Once run ids are client minted", %{run: run} do
    other_project = ProjectsFixtures.project_fixture()

    {:ok, other_run} =
      OnceEvents.upsert_run(%{
        project_id: other_project.id,
        run_id: run.run_id,
        kind: "test",
        started_at: DateTime.utc_now()
      })

    stage_case(run, %{case_id: "a", name: "a"})
    stage_case(other_run, %{case_id: "a", name: "a"})

    assert {:ok, first} = TestReportIngestor.publish(finalize(run))
    assert {:ok, second} = TestReportIngestor.publish(finalize(other_run))

    refute first.id == second.id
  end
end
