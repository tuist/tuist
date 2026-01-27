defmodule Tuist.SentryEventFilterTest do
  use ExUnit.Case, async: true

  alias Tuist.SentryEventFilter

  defp build_event(original_exception) do
    %Sentry.Event{
      event_id: "test-event-id",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      original_exception: original_exception
    }
  end

  describe "before_send/1" do
    test "excludes Bandit.TransportError (from common filter)" do
      event = build_event(%Bandit.TransportError{message: "test"})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes Phoenix.Router.NoRouteError (from common filter)" do
      event = build_event(%Phoenix.Router.NoRouteError{})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes TuistWeb.Errors.BadRequestError" do
      event = build_event(%TuistWeb.Errors.BadRequestError{message: "test"})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes TuistWeb.Errors.NotFoundError" do
      event = build_event(%TuistWeb.Errors.NotFoundError{message: "test"})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes TuistWeb.Errors.TooManyRequestsError" do
      event = build_event(%TuistWeb.Errors.TooManyRequestsError{message: "test"})
      assert SentryEventFilter.before_send(event) == false
    end

    test "excludes TuistWeb.Errors.UnauthorizedError" do
      event = build_event(%TuistWeb.Errors.UnauthorizedError{message: "test"})
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
  end
end
