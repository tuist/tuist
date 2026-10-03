defmodule TuistTestSupport.TelemetryCaptureTest do
  use ExUnit.Case, async: true

  alias TuistTestSupport.TelemetryCapture

  @event [:tuist_test_support, :telemetry_capture_test, :event]

  test "forwards an event the attaching process emits" do
    event_ref = TelemetryCapture.attach_event_handlers([@event])

    :telemetry.execute(@event, %{count: 1}, %{source: "self"})

    assert_received {@event, ^event_ref, %{count: 1}, %{source: "self"}}
  end

  test "drops an event another process emits" do
    event_ref = TelemetryCapture.attach_event_handlers([@event])

    emit_from_another_process(%{source: "elsewhere"})

    refute_received {@event, ^event_ref, _measurements, _metadata}
  end

  test "drops the event a global handler delivers under this test's own ref" do
    # What `:telemetry_test.attach_event_handlers/2` does with the same event,
    # stated so the difference is visible: the ref identifies the handler, so a
    # concurrent emitter's event arrives carrying this process's own ref.
    global_ref = :telemetry_test.attach_event_handlers(self(), [@event])
    on_exit(fn -> :telemetry.detach(global_ref) end)
    scoped_ref = TelemetryCapture.attach_event_handlers([@event])

    emit_from_another_process(%{source: "elsewhere"})

    assert_receive {@event, ^global_ref, _measurements, %{source: "elsewhere"}}
    refute_received {@event, ^scoped_ref, _measurements, _metadata}
  end

  defp emit_from_another_process(metadata) do
    task = Task.async(fn -> :telemetry.execute(@event, %{count: 1}, metadata) end)
    Task.await(task)
  end
end
