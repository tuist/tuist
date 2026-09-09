defmodule TuistTestSupport.TelemetryCapture do
  @moduledoc """
  `:telemetry_test.attach_event_handlers/2` narrowed to the events the calling
  test emits itself.

  Telemetry handlers are global and the suite runs its async files
  concurrently, so a handler one test attaches also fires for the same event
  emitted by any other test running beside it. The message carries the
  attaching test's own ref either way, because the ref identifies the handler
  rather than the emitter, so pinning it does not tell the two apart: a test
  that refutes an event fails on another test's, and a test that asserts one
  can pass on it.

  Handlers run in the process that called `:telemetry.execute/3`, which is the
  one thing that does separate them. Only events emitted from the attaching
  process are forwarded, so an event emitted by a task or a worker the test
  starts is dropped, and a test that needs one of those wants
  `:telemetry_test.attach_event_handlers/2` and metadata narrow enough to
  identify itself.
  """

  def attach_event_handlers(event_names) when is_list(event_names) do
    ref = make_ref()

    :telemetry.attach_many(ref, event_names, &__MODULE__.handle_event/4, %{emitter: self(), ref: ref})

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(ref) end)

    ref
  end

  @doc false
  def handle_event(event_name, measurements, metadata, %{emitter: emitter, ref: ref}) do
    if self() == emitter do
      send(emitter, {event_name, ref, measurements, metadata})
    end

    :ok
  end
end
