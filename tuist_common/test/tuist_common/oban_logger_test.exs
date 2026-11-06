defmodule TuistCommon.ObanLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias TuistCommon.ObanLogger

  setup do
    assert :ok = ObanLogger.attach()
    on_exit(fn -> :telemetry.detach("tuist-oban-logger") end)

    %{
      job: %{
        id: 42,
        worker: "Tuist.TestWorker",
        queue: "webhooks",
        attempt: 2,
        max_attempts: 5,
        args: %{"payload" => "private webhook payload"},
        meta: %{"secret" => "private metadata"}
      }
    }
  end

  test "logs starts without arguments or metadata", %{job: job} do
    log =
      capture_log([level: :debug], fn ->
        :telemetry.execute([:oban, :job, :start], %{}, %{job: job})
      end)

    assert log =~ "Oban job start"
    assert log =~ "worker=Tuist.TestWorker job_id=42 queue=webhooks attempt=2 max_attempts=5"
    refute log =~ "private webhook payload"
    refute log =~ "private metadata"
    refute log =~ "payload"
  end

  test "logs completion state and millisecond timings", %{job: job} do
    measurements = %{
      duration: System.convert_time_unit(2_500, :millisecond, :native),
      queue_time: System.convert_time_unit(25, :millisecond, :native)
    }

    for state <- [:success, :cancelled, :discard, :snoozed] do
      log =
        capture_log(fn ->
          :telemetry.execute([:oban, :job, :stop], measurements, %{job: job, state: state})
        end)

      assert log =~ "Oban job stop"
      assert log =~ "duration_ms=2500.0 queue_time_ms=25.0"
      assert log =~ "state=#{state}"
      refute log =~ "private webhook payload"
    end
  end

  test "logs exception details and keeps the failure identity", %{job: job} do
    metadata = %{
      job: job,
      state: :failure,
      kind: :error,
      reason: %RuntimeError{message: "job failed"},
      stacktrace: [{Tuist.TestWorker, :perform, 1, [file: "worker.ex", line: 10]}]
    }

    log = capture_log(fn -> :telemetry.execute([:oban, :job, :exception], %{}, metadata) end)

    assert log =~ "[error]"
    assert log =~ "Oban job exception worker=Tuist.TestWorker job_id=42"
    assert log =~ "state=failure"
    assert log =~ "RuntimeError"
    assert log =~ "job failed"
    assert log =~ "worker.ex:10"
    refute log =~ "private webhook payload"
    refute log =~ "private metadata"
    refute log =~ "\n    worker.ex:10"
  end

  test "bounds verbose exception diagnostics", %{job: job} do
    for message <- [String.duplicate("x", 10_000), String.duplicate("x\n", 5_000)] do
      metadata = %{
        job: job,
        kind: :error,
        reason: %RuntimeError{message: message},
        stacktrace: [{ExampleWorker, :perform, 1, [file: ~c"worker.ex", line: 10]}]
      }

      log = capture_log(fn -> :telemetry.execute([:oban, :job, :exception], %{}, metadata) end)

      assert log =~ "job_id=42"
      assert log =~ "RuntimeError"
      assert byte_size(log) < 4_500
      assert log =~ "worker.ex:10"
      assert log =~ "ExampleWorker.perform/1"
      refute log =~ "\nx\n"
    end
  end
end
