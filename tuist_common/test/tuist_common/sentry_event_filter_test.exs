defmodule TuistCommon.SentryEventFilterTest do
  use ExUnit.Case, async: true

  alias TuistCommon.SentryEventFilter

  defp build_event(original_exception) do
    %Sentry.Event{
      event_id: "test-event-id",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      original_exception: original_exception
    }
  end

  describe "before_send/1" do
    test "excludes Bandit.TransportError" do
      event = build_event(%Bandit.TransportError{message: "test"})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes Phoenix.Router.NoRouteError" do
      event = build_event(%Phoenix.Router.NoRouteError{})
      assert SentryEventFilter.before_send(event) == false
    end

    test "allows other exceptions through" do
      event = build_event(%RuntimeError{message: "test"})
      assert SentryEventFilter.before_send(event) == event
    end

    test "allows events without original_exception through" do
      event = build_event(nil)
      assert SentryEventFilter.before_send(event) == event
    end

    test "does not crash when original_exception is nil (capture_message case)" do
      # This is what happens when Sentry.capture_message is called
      # The event has original_exception: nil
      event = build_event(nil)
      # Should not raise and should return the event unchanged
      result = SentryEventFilter.before_send(event)
      assert result == event
    end
  end

  describe "before_send/2 with additional exceptions" do
    test "excludes additional exceptions" do
      event = build_event(%ArgumentError{message: "test"})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == false
    end

    test "still excludes default exceptions" do
      event = build_event(%Bandit.TransportError{message: "test"})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == false
    end

    test "allows non-listed exceptions through" do
      event = build_event(%RuntimeError{message: "test"})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == event
    end
  end
end
