defmodule TuistCommon.SentryEventFilterTest do
  use ExUnit.Case, async: true

  alias TuistCommon.SentryEventFilter

  defp event(overrides) do
    defaults = %{
      event_id: String.duplicate("a", 32),
      timestamp: "2020-01-01T00:00:00Z"
    }

    struct!(Sentry.Event, Map.merge(defaults, overrides))
  end

  describe "before_send/1" do
    test "excludes Bandit.TransportError" do
      event = event(%{original_exception: %Bandit.TransportError{message: "test"}})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes Phoenix.Router.NoRouteError" do
      event = event(%{original_exception: %Phoenix.Router.NoRouteError{}})
      assert SentryEventFilter.before_send(event) == false
    end

    test "allows other exceptions through" do
      event = event(%{original_exception: %RuntimeError{message: "test"}})
      assert SentryEventFilter.before_send(event) == event
    end

    test "allows events without original_exception through" do
      event = event(%{original_exception: nil, exception: []})
      assert SentryEventFilter.before_send(event) == event
    end

    test "excludes ignored exception types even without original_exception" do
      event = event(%{
        original_exception: nil,
        exception: [%Sentry.Interfaces.Exception{type: "Phoenix.Router.NoRouteError", value: "no route"}]
      })

      assert SentryEventFilter.before_send(event) == false
    end
  end

  describe "before_send/2 with additional exceptions" do
    test "excludes additional exceptions" do
      event = event(%{original_exception: %ArgumentError{message: "test"}})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == false
    end

    test "still excludes default exceptions" do
      event = event(%{original_exception: %Bandit.TransportError{message: "test"}})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == false
    end

    test "allows non-listed exceptions through" do
      event = event(%{original_exception: %RuntimeError{message: "test"}})
      assert SentryEventFilter.before_send(event, [ArgumentError]) == event
    end
  end
end
