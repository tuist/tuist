defmodule Tuist.RemoteExecution.RunAnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.OnceEvents
  alias Tuist.RemoteExecution.Actions
  alias Tuist.RemoteExecution.RunAnalytics
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  defp record(run_id, start_us, queue_ms, execution_ms, overrides \\ %{}) do
    worker_start = start_us + queue_ms * 1000

    Map.merge(
      %{
        "operation_id" => Ecto.UUID.generate(),
        "action_hash" => String.duplicate("b", 64),
        "invocation_id" => run_id,
        "tool_name" => "struo",
        "mnemonic" => "elixir-compile",
        "target" => "atlas/mix_application_test",
        "exit_code" => 0,
        "timestamps" => %{
          "queued" => start_us,
          "worker_start" => worker_start,
          "execution_start" => worker_start + 100_000,
          "execution_completed" => worker_start + 100_000 + execution_ms * 1000,
          "worker_completed" => worker_start + 200_000 + execution_ms * 1000
        }
      },
      overrides
    )
  end

  test "counts Struo runs, their outcome and phase timings from the gateway's records" do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    other = ProjectsFixtures.project_fixture(build_system: :once)
    now_us = System.os_time(:microsecond) - 60_000_000

    {:ok, _} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: "run-a",
        kind: "build",
        command_display: "struo build atlas/mix_application_test",
        started_at: DateTime.utc_now()
      })

    {:ok, 4} =
      Actions.ingest(project, [
        record("run-a", now_us, 1_000, 2_000),
        record("run-a", now_us + 500_000, 3_000, 4_000),
        record("run-b", now_us, 500, 10_000, %{"exit_code" => 1}),
        # Answered from the action cache: never ran.
        record("run-b", now_us, 9_000, 9_000, %{"cached_result" => true})
      ])

    {:ok, 1} = Actions.ingest(other, [record("run-c", now_us, 1, 1)])

    opts = [
      since: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
      until: NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
    ]

    summary = RunAnalytics.summary(project.id, opts)
    assert %{invocations: 2, actions: 3} = summary
    assert_in_delta summary.queue.avg, 1500.0, 0.01
    assert_in_delta summary.execution.avg, 16_000 / 3, 0.01

    %{rows: rows, has_next_page?: false} = RunAnalytics.activity(project.id, opts)
    by_id = Map.new(rows, &{&1.invocation_id, &1})

    assert %{status: "success", actions: 2, command: "struo build atlas/mix_application_test"} = by_id["run-a"]
    # Span of its remote actions: first queued to last worker completion.
    assert by_id["run-a"].duration_ms == 500 + 3_000 + 200 + 4_000
    assert %{status: "failure", actions: 1, command: nil, run: nil} = by_id["run-b"]
    assert by_id["run-b"].target_patterns == ["atlas/mix_application_test"]

    failed =
      RunAnalytics.activity(project.id, Keyword.put(opts, :filters, [%{field: :status, op: :==, value: "failure"}]))

    assert Enum.map(failed.rows, & &1.invocation_id) == ["run-b"]

    series = RunAnalytics.time_series(project.id, opts)
    assert Enum.sum(series.actions) == 3
  end
end
