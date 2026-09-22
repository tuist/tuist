defmodule Tuist.OnceEventsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.RunCompleted
  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.TargetCompleted
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.RunEventService
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

  defmodule HeadersAdapter do
    @moduledoc false
    def get_headers(headers), do: headers
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

  defp project(run, payload) do
    kind =
      case payload do
        %ActionCompleted{} -> :action_completed
        %TargetCompleted{} -> :target_completed
        %RunCompleted{} -> :run_completed
      end

    Projector.project(%RunEvent{epoch_ms: 1_789_405_000_000, payload: {kind, payload}}, run.project_id, run.run_id)
  end
end
