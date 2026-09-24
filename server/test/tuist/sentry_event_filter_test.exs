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
    test "drops Oban.PerformError events from the webhook delivery worker" do
      event =
        event(%{
          original_exception: %Oban.PerformError{
            message: "Tuist.Webhooks.Workers.DeliveryWorker failed with {:error, \"HTTP 400\"}",
            reason: {:error, "HTTP 400"}
          },
          tags: %{
            oban_worker: "Tuist.Webhooks.Workers.DeliveryWorker",
            oban_queue: "webhooks",
            oban_state: "failure"
          }
        })

      assert SentryEventFilter.before_send(event) == false
    end

    test "keeps Oban.PerformError events from other workers" do
      event =
        event(%{
          original_exception: %Oban.PerformError{
            message: "SomeWorker failed with {:error, :boom}",
            reason: {:error, :boom}
          },
          tags: %{oban_worker: "SomeWorker", oban_queue: "default", oban_state: "failure"}
        })

      assert SentryEventFilter.before_send(event) == event
    end

    test "keeps raised exceptions from the webhook delivery worker" do
      event =
        event(%{
          original_exception: %RuntimeError{message: "boom"},
          tags: %{
            oban_worker: "Tuist.Webhooks.Workers.DeliveryWorker",
            oban_queue: "webhooks",
            oban_state: "failure"
          }
        })

      assert SentryEventFilter.before_send(event) == event
    end

    test "drops ignored web errors" do
      event = event(%{original_exception: %TuistWeb.Errors.NotFoundError{message: "not found"}})

      assert SentryEventFilter.before_send(event) == false
    end

    test "keeps other exceptions" do
      event = event(%{original_exception: %RuntimeError{message: "boom"}})

      assert SentryEventFilter.before_send(event) == event
    end
  end
end
