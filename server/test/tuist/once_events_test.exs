defmodule Tuist.OnceEventsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Once.Events.V1.AckDisposition
  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.BatchAck
  alias Once.Events.V1.CacheDownload
  alias Once.Events.V1.ContentRef
  alias Once.Events.V1.RunCompleted
  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.RunEventBatch
  alias Once.Events.V1.RunStarted
  alias Once.Events.V1.TargetCompleted
  alias Once.Events.V1.TestCaseCompleted
  alias Once.Events.V1.TestSuiteStarted
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Analytics
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.RunEventService
  alias Tuist.OnceEvents.TestCaseRun
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, run} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
    %{run: run, project: Tuist.Projects.get_project_by_id(project.id)}
  end

  test "records each declared action without adding target summaries", %{run: run} do
    project(run, %TargetCompleted{target_execution_id: "mise", result: :TARGET_RESULT_SUCCEEDED})
    assert OnceEvents.list_actions(run) == []

    for {index, cached} <- [{0, true}, {1, false}, {2, false}] do
      project(run, %ActionCompleted{
        target_execution_id: "mise",
        capability: "build",
        action_index: index,
        identifier: "action-#{index}",
        result: :TARGET_RESULT_SUCCEEDED,
        was_cached: cached,
        duration_ms: 10 + index
      })
    end

    project(run, %TargetCompleted{target_execution_id: "mise", result: :TARGET_RESULT_SUCCEEDED})
    actions = OnceEvents.list_actions(run)
    assert Enum.map(actions, & &1.identifier) == ["action-0", "action-1", "action-2"]
    assert Enum.map(actions, & &1.duration_ms) == [10, 11, 12]
    assert [%{identifier: "action-1"}] = OnceEvents.list_actions(run, limit: 1, offset: 1)
    assert %{total_actions: 3, cached_actions: 1, executed_actions: 2} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "replayed actions do not inflate counters and capabilities remain distinct", %{run: run} do
    action = %ActionCompleted{
      target_execution_id: "mise",
      capability: "build",
      action_index: 0,
      identifier: "compile",
      result: :TARGET_RESULT_FAILED,
      duration_ms: 10
    }

    project(run, action)
    project(run, action)
    project(run, %{action | capability: "test", identifier: "test", result: :TARGET_RESULT_SUCCEEDED, was_cached: true})
    assert length(OnceEvents.list_actions(run)) == 2

    assert %{total_actions: 2, cached_actions: 1, executed_actions: 1, failed_actions: 1} =
             OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "decoded failed run result remains failed", %{run: run} do
    project(run, %RunCompleted{result: :RUN_RESULT_FAILED, wall_ms: 123})
    assert %{exit_status: 1, wall_ms: 123, finalization: "finalized"} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "search and filters apply before pagination and remain run scoped", %{run: run} do
    for index <- 0..59 do
      project(run, %ActionCompleted{
        target_execution_id: "crate_#{index}",
        capability: "build",
        action_index: 0,
        identifier: "compile-#{index}",
        result: :TARGET_RESULT_SUCCEEDED,
        was_cached: rem(index, 2) == 0,
        duration_ms: index
      })
    end

    {:ok, other} = OnceEvents.upsert_run(%{project_id: run.project_id, run_id: UUIDv7.generate()})

    project(other, %ActionCompleted{
      target_execution_id: "crate_59",
      identifier: "compile-59",
      result: :TARGET_RESULT_SUCCEEDED
    })

    opts = [
      search: "COMPILE",
      filters: [%{field: :cache, op: :==, value: "miss"}],
      sort_by: "duration",
      sort_order: "desc"
    ]

    assert OnceEvents.count_actions(run, opts) == 30
    assert [%{duration_ms: 55}, %{duration_ms: 53}] = OnceEvents.list_actions(run, opts ++ [limit: 2, offset: 2])
    assert [%{duration_ms: 59}] = OnceEvents.list_actions(run, search: "crate_59")
    assert OnceEvents.count_actions(run, search: "%") == 0
    assert OnceEvents.count_actions(run, search: "crate_") == 60
    assert OnceEvents.count_actions(run, filters: [%{field: :result, op: :!=, value: "succeeded"}]) == 0
    assert OnceEvents.count_actions(run, filters: [%{field: :cache, op: :!=, value: "miss"}]) == 30
  end

  test "every column sorts both ways with stable ties", %{run: run} do
    project(run, %ActionCompleted{
      target_execution_id: "a",
      identifier: "alpha",
      result: :TARGET_RESULT_FAILED,
      duration_ms: 1
    })

    project(run, %ActionCompleted{
      target_execution_id: "b",
      identifier: "beta",
      result: :TARGET_RESULT_SUCCEEDED,
      was_cached: true,
      duration_ms: 2
    })

    for column <- ["action", "status", "cache", "duration"] do
      assert Enum.map(OnceEvents.list_actions(run, sort_by: column, sort_order: "asc"), & &1.target_execution_id) == [
               "a",
               "b"
             ]

      assert Enum.map(OnceEvents.list_actions(run, sort_by: column, sort_order: "desc"), & &1.target_execution_id) == [
               "b",
               "a"
             ]
    end

    for direction <- ["asc", "desc"] do
      assert Enum.map(OnceEvents.list_actions(run, sort_by: "finished", sort_order: direction), & &1.target_execution_id) ==
               ["a", "b"]
    end
  end

  test "a replayed cache event neither duplicates the row nor doubles the transfer roll-up", %{run: run} do
    download = %CacheDownload{
      target_execution_id: "mise",
      content: %ContentRef{digest: "abc123", size_bytes: 4096},
      bytes_transferred: 4096,
      duration_ms: 12
    }

    project(run, download)
    project(run, download)

    reloaded = OnceEvents.get_run(run.project_id, run.run_id)

    assert OnceEvents.count_cache_events(reloaded, view: "content-objects", search: "", outcome: nil) == 1
    assert reloaded.cache_bytes_downloaded == 4096
    assert reloaded.cache_action_read_count == 1
  end

  test "a content object is listed once however many actions share its target", %{run: run} do
    # One target, three declared actions, one transfer of one object.
    for index <- 0..2 do
      project(run, %ActionCompleted{
        target_execution_id: "mise",
        capability: "build",
        action_index: index,
        identifier: "compiler-#{index}",
        result: :TARGET_RESULT_SUCCEEDED
      })
    end

    project(run, %CacheDownload{
      target_execution_id: "mise",
      content: %ContentRef{digest: "abc123", size_bytes: 4096},
      bytes_transferred: 4096,
      duration_ms: 12
    })

    reloaded = OnceEvents.get_run(run.project_id, run.run_id)
    opts = [view: "content-objects", search: "", outcome: nil]

    # The page and the count have to describe the same rows, otherwise
    # pagination puts objects beyond reach.
    assert length(OnceEvents.list_cache_events(reloaded, opts)) == 1
    assert OnceEvents.count_cache_events(reloaded, opts) == 1
  end

  test "a run in flight is reported as in progress rather than failed", %{run: run} do
    status = fn ->
      {[invocation], _meta} =
        Analytics.list_invocations(run.project_id, %{page: 1, page_size: 10}, [])

      invocation.status
    end

    # Started, nothing reported yet. Before the fix this was "failure",
    # which also counted it in the failed roll-ups on the listings.
    assert status.() == "in_progress"

    project(run, %RunEvent{payload: {:run_finalizing, %Once.Events.V1.RunFinalizing{}}})
    assert status.() == "in_progress"

    project(run, %RunCompleted{result: :RUN_RESULT_SUCCEEDED, wall_ms: 10})
    assert status.() == "success"
  end

  test "a replayed test suite start does not inflate the run's suite count", %{run: run} do
    started = %TestSuiteStarted{target_execution_id: "mise", suite_id: "unit", planned_case_count: 3}

    project(run, started)
    project(run, started)
    project(run, %TestSuiteStarted{target_execution_id: "mise", suite_id: "integration"})

    assert OnceEvents.get_run(run.project_id, run.run_id).test_suite_count == 2
  end

  test "an attempt carried only by the legacy composite id still separates retries", %{run: run} do
    for attempt <- [1, 2] do
      project(run, %TestCaseCompleted{
        test_case_execution_id: "mise#tests::flaky##{attempt}",
        result: :TEST_CASE_RESULT_FAILED,
        duration_ms: 5
      })
    end

    attempts =
      TestCaseRun
      |> where(once_run_id: ^run.id)
      |> select([c], c.attempt)
      |> Repo.all()
      |> Enum.sort()

    assert attempts == [1, 2]
  end

  defmodule HeadersAdapter do
    @moduledoc false
    def get_headers(headers), do: headers
  end

  test "a batch whose projection fails is not acknowledged as accepted", %{project: project, run: run} do
    stub(OnceEvents, :ingest_action, fn _run, _attrs -> raise "postgres is down" end)

    batch = %RunEventBatch{
      run_id: run.run_id,
      batch_id: "batch-1",
      seq_from: 7,
      events: [
        %RunEvent{
          seq: 7,
          epoch_ms: 1_789_405_000_000,
          payload:
            {:action_completed, %ActionCompleted{target_execution_id: "mise", capability: "build", action_index: 0}}
        }
      ]
    }

    RunEventService.publish_run_events([batch], reply_stream(project))

    assert_received {:ack, %BatchAck{} = ack}
    assert ack.disposition == AckDisposition.value(:ACK_DISPOSITION_NEEDS_RESYNC)
    # The failing event is seq 7, so the client must resend from there.
    assert ack.acked_seq == 6
    assert ack.expected_next_seq == 7
    assert OnceEvents.acked_seq(project.id, run.run_id) == 0
  end

  test "an empty batch advancing past a producer gap is acknowledged at the gap", %{project: project, run: run} do
    batch = %RunEventBatch{
      run_id: run.run_id,
      batch_id: "batch-gap",
      seq_from: 31,
      gap_advances: [%Once.Events.V1.GapAdvance{first_dropped_seq: 21, last_dropped_seq: 30}],
      events: []
    }

    RunEventService.publish_run_events([batch], reply_stream(project))

    assert_received {:ack, %BatchAck{} = ack}
    assert ack.disposition == AckDisposition.value(:ACK_DISPOSITION_ACCEPTED)
    assert ack.acked_seq == 30
    assert ack.expected_next_seq == 31
  end

  test "a replayed batch is acknowledged at the stored mark rather than walking it back", %{
    project: project,
    run: run
  } do
    OnceEvents.observe_acked_seq(project.id, run.run_id, 20)

    batch = %RunEventBatch{run_id: run.run_id, batch_id: "batch-replay", seq_from: 15, events: []}

    RunEventService.publish_run_events([batch], reply_stream(project))

    assert_received {:ack, %BatchAck{acked_seq: 20, expected_next_seq: 21}}
  end

  test "acknowledgement state does not leak across projects that reuse a run id", %{project: project, run: run} do
    other_project = ProjectsFixtures.project_fixture()

    OnceEvents.observe_acked_seq(project.id, run.run_id, 42)

    assert OnceEvents.acked_seq(project.id, run.run_id) == 42
    assert OnceEvents.acked_seq(other_project.id, run.run_id) == 0
  end

  test "the acknowledged sequence never walks backwards", %{project: project, run: run} do
    OnceEvents.observe_acked_seq(project.id, run.run_id, 42)
    OnceEvents.observe_acked_seq(project.id, run.run_id, 7)

    assert OnceEvents.acked_seq(project.id, run.run_id) == 42
  end

  test "authenticates the configured project slug and rejects another project", %{project: project} do
    stream = %GRPC.Server.Stream{adapter: HeadersAdapter, payload: %{"authorization" => "Bearer " <> project.token}}
    request = %Once.Events.V1.GetArgvHashKeyRequest{project_id: "#{project.account.name}/#{project.name}"}
    assert %Once.Events.V1.ArgvHashKey{key_bytes: key} = RunEventService.get_argv_hash_key(request, stream)
    assert byte_size(key) == 32

    assert_raise GRPC.RPCError, ~r/project token does not match/, fn ->
      RunEventService.get_argv_hash_key(%{request | project_id: "another/project"}, stream)
    end
  end

  test "a RunStarted carries its CI flag onto the run", %{run: run} do
    project(
      run,
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload: {:run_started, %RunStarted{once_version: "0.60.0", is_ci: true}}
      }
    )

    assert OnceEvents.get_run(run.project_id, run.run_id).is_ci
  end

  test "a RunStarted carries its branch onto the run", %{run: run} do
    project(
      run,
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload: {:run_started, %RunStarted{git_rev: "abc123", git_branch: "release/1.2"}}
      }
    )

    assert %{git_branch: "release/1.2", git_rev: "abc123"} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "a RunStarted without a branch stores an empty string rather than nil", %{run: run} do
    # The column is not nullable, so a client that cannot determine a branch
    # (detached HEAD outside CI, or one predating the field) must still write.
    project(
      run,
      %RunEvent{epoch_ms: 1_789_405_000_000, payload: {:run_started, %RunStarted{git_rev: "abc123"}}}
    )

    assert %{git_branch: ""} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "a RunStarted from a client that predates the field reads as not CI", %{run: run} do
    # Implicit presence on the wire: an older client sends no field at all and
    # protobuf decodes it as `false`, which is the same thing a local run
    # sends. Both belong under "Local", matching how Xcode builds behave.
    project(
      run,
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload: {:run_started, %RunStarted{once_version: "0.59.0"}}
      }
    )

    refute OnceEvents.get_run(run.project_id, run.run_id).is_ci
  end

  test "the Builds analytics split runs by environment", %{project: project} do
    for {run_id, is_ci, wall_ms} <- [{"ci-run", true, 4000}, {"local-run", false, 2000}] do
      {:ok, started} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: run_id,
          kind: "build",
          is_ci: is_ci,
          started_at: DateTime.utc_now()
        })

      {:ok, _} =
        OnceEvents.finalize_run(started, %{
          finalization: "finalized",
          exit_status: 0,
          wall_ms: wall_ms,
          finalized_at: DateTime.utc_now()
        })
    end

    assert Analytics.summary(project.id, commands: ["build"], is_ci: true).total == 1
    assert Analytics.summary(project.id, commands: ["build"], is_ci: false).total == 1
    # No `:is_ci` opt is the "Any" selection, which must not filter.
    assert Analytics.summary(project.id, commands: ["build"]).total == 2
  end

  test "a raw digest is stored as hex rather than rejected by Postgres", %{run: run} do
    # `ContentRef.digest` is `bytes` and the client sends the raw digest.
    # Written straight into the varchar, Postgres rejects it with 22021 and
    # the batch is acked NEEDS_RESYNC forever, blocking the rest of the run.
    digest = <<0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF>>

    project(run, %CacheDownload{
      target_execution_id: "mise",
      content: %ContentRef{digest: digest, size_bytes: 10},
      bytes_transferred: 10,
      duration_ms: 1
    })

    reloaded = OnceEvents.get_run(run.project_id, run.run_id)
    assert OnceEvents.count_cache_events(reloaded, view: "content-objects", search: "", outcome: nil) == 1
    assert reloaded.cache_bytes_downloaded == 10
  end

  test "retried attempts count as one case, with the final verdict", %{run: run} do
    # Once retries in place, and its pytest normalizer reports setup, call and
    # teardown as three attempts of one case.
    for {attempt, result} <- [{1, "failed"}, {2, "failed"}, {3, "passed"}] do
      OnceEvents.ingest_test_case_run(run, %{
        target_execution_id: "cargo_aqua",
        suite_id: "unit",
        case_id: "cargo_aqua::unit::case_1",
        name: "case_1",
        attempt: attempt,
        result: result,
        duration_ms: 5,
        finished_at: DateTime.utc_now()
      })
    end

    assert %{test_case_count: 1, passed_test_cases: 1, failed_test_cases: 0} =
             OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "separate cases still count separately", %{run: run} do
    for case_id <- ["a", "b"] do
      OnceEvents.ingest_test_case_run(run, %{
        target_execution_id: "cargo_aqua",
        suite_id: "unit",
        case_id: case_id,
        name: case_id,
        attempt: 1,
        result: "passed",
        duration_ms: 5,
        finished_at: DateTime.utc_now()
      })
    end

    assert %{test_case_count: 2, passed_test_cases: 2} =
             OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "the acked sequence survives a restart, so a reconnect is not told zero", %{
    project: project,
    run: run
  } do
    OnceEvents.observe_acked_seq(project.id, run.run_id, 12)

    # Nothing is cached in this process: a different pod, or this one after a
    # deploy, reads the same value. Answering 0 here makes the client treat
    # the regressing `expected_next_seq` as a protocol violation and drop the
    # rest of the run.
    assert OnceEvents.acked_seq(project.id, run.run_id) == 12
    assert Tuist.Repo.get_by(Run, id: run.id).acked_seq == 12
  end

  test "a heartbeat keeps a slow run from looking abandoned", %{run: run} do
    stale = DateTime.add(DateTime.utc_now(), -7200, :second)

    {1, _} =
      Run
      |> where([r], r.id == ^run.id)
      |> Tuist.Repo.update_all(set: [started_at: stale, heartbeat_at: stale])

    # The client sends these every few seconds; the projector used to drop
    # them, so a run doing slow work aged out like an abandoned one.
    project(run, %RunEvent{
      epoch_ms: DateTime.to_unix(DateTime.utc_now(), :millisecond),
      payload: {:run_heartbeat, %Once.Events.V1.RunHeartbeat{}}
    })

    assert {:ok, 0} = OnceEvents.expire_stale_runs()
    assert %{finalization: "active"} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  test "a run that stopped reporting is marked lost rather than Running forever", %{run: run} do
    stale = DateTime.add(DateTime.utc_now(), -7200, :second)

    {1, _} =
      Run
      |> where([r], r.id == ^run.id)
      |> Tuist.Repo.update_all(set: [started_at: stale, heartbeat_at: stale])

    assert {:ok, 1} = OnceEvents.expire_stale_runs()

    reloaded = OnceEvents.get_run(run.project_id, run.run_id)
    assert reloaded.finalization == "lost"
    assert reloaded.finalized_at

    # `run_status/1` already treats lost as terminal, so the listing stops
    # reporting it as in progress.
    {[invocation], _meta} = Analytics.list_invocations(run.project_id, %{page: 1, page_size: 10}, [])
    assert invocation.status == "failure"
  end

  test "a finalized run is left alone by the sweep", %{run: run} do
    stale = DateTime.add(DateTime.utc_now(), -7200, :second)

    {:ok, _} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: 0,
        wall_ms: 10,
        finalized_at: stale
      })

    {1, _} =
      Run
      |> where([r], r.id == ^run.id)
      |> Tuist.Repo.update_all(set: [started_at: stale, heartbeat_at: stale])

    assert {:ok, 0} = OnceEvents.expire_stale_runs()
    assert %{finalization: "finalized"} = OnceEvents.get_run(run.project_id, run.run_id)
  end

  defp project(run, %RunEvent{} = event), do: Projector.project(event, run.project_id, run.run_id)

  defp project(run, payload) do
    kind =
      case payload do
        %ActionCompleted{} -> :action_completed
        %TargetCompleted{} -> :target_completed
        %RunCompleted{} -> :run_completed
        %CacheDownload{} -> :cache_download
        %TestSuiteStarted{} -> :test_suite_started
        %TestCaseCompleted{} -> :test_case_completed
      end

    Projector.project(%RunEvent{epoch_ms: 1_789_405_000_000, payload: {kind, payload}}, run.project_id, run.run_id)
  end

  defp reply_stream(project) do
    test_process = self()

    %GRPC.Server.Stream{
      adapter: HeadersAdapter,
      payload: %{"authorization" => "Bearer " <> project.token},
      __interface__: %{
        send_reply: fn stream, reply, _opts ->
          send(test_process, {:ack, reply})
          stream
        end
      }
    }
  end
end
