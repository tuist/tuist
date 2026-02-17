defmodule Tuist.SentryEventFilterTest do
  use ExUnit.Case, async: true

  alias Tuist.SentryEventFilter

  defp event(overrides) do
    defaults = %{
      event_id: String.duplicate("a", 32),
      timestamp: "2020-01-01T00:00:00Z"
    }

    struct!(Sentry.Event, Map.merge(defaults, overrides))
  end

  describe "before_send/1" do
    test "excludes webhook body read timeout errors" do
      event =
        event(%{
          exception: [
            %Sentry.Interfaces.Exception{type: "Bandit.HTTPError", value: "Body read timeout"}
          ],
          tags: [{"url", "http://tuist.dev/webhooks/github"}]
        })

      assert SentryEventFilter.before_send(event) == false
    end

    test "allows body read timeout errors on non-webhook URLs" do
      event =
        event(%{
          exception: [
            %Sentry.Interfaces.Exception{type: "Bandit.HTTPError", value: "Body read timeout"}
          ],
          tags: [{"url", "http://tuist.dev/api/v1/builds"}]
        })

      assert SentryEventFilter.before_send(event) == event
    end

    test "still applies shared sentry event filters" do
      event = event(%{original_exception: %Bandit.TransportError{message: "test"}})
      assert SentryEventFilter.before_send(event) == false
    end
  end
end
