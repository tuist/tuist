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

  # Built the way `TuistCommon.ObanTelemetry` reports a raised job exception.
  defp clickhouse_memory_limit_event(worker, attempt: attempt, max_attempts: max_attempts) do
    Sentry.Event.transform_exception(
      %Ch.Error{code: 241, message: "Code: 241. DB::Exception: (total) memory limit exceeded. (MEMORY_LIMIT_EXCEEDED)"},
      tags: %{oban_worker: worker, oban_queue: "process_build", oban_state: "failure"},
      extra: %{attempt: attempt, max_attempts: max_attempts, worker: worker, oban_state: :failure}
    )
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

    test "drops ClickHouse memory limit errors from the first build processing attempt" do
      event = clickhouse_memory_limit_event("Tuist.Builds.Workers.ProcessBuildWorker", attempt: 1, max_attempts: 5)

      assert SentryEventFilter.before_send(event) == false
    end

    test "keeps ClickHouse memory limit errors from build processing retries" do
      for attempt <- 2..5 do
        event =
          clickhouse_memory_limit_event("Tuist.Builds.Workers.ProcessBuildWorker", attempt: attempt, max_attempts: 5)

        assert SentryEventFilter.before_send(event) == event
      end
    end

    test "keeps ClickHouse memory limit errors from other workers" do
      event = clickhouse_memory_limit_event("SomeWorker", attempt: 1, max_attempts: 5)

      assert SentryEventFilter.before_send(event) == event
    end

    test "drops ignored web errors" do
      event = event(%{original_exception: %TuistWeb.Errors.NotFoundError{message: "not found"}})

      assert SentryEventFilter.before_send(event) == false
    end

    test "drops CSRF token errors as background scanner noise" do
      event = event(%{original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}})

      assert SentryEventFilter.before_send(event) == false
    end

    test "keeps cross-origin JS request errors so layout regressions still page us" do
      event = event(%{original_exception: %Plug.CSRFProtection.InvalidCrossOriginRequestError{}})

      assert SentryEventFilter.before_send(event) == event
    end

    test "keeps other exceptions" do
      event = event(%{original_exception: %RuntimeError{message: "boom"}})

      assert SentryEventFilter.before_send(event) == event
    end
  end
end
