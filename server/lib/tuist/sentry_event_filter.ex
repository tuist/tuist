defmodule Tuist.SentryEventFilter do
  @moduledoc """
  Filters events before they are sent to Sentry.
  This module is used to exclude expected errors that are not actionable.
  """

  @additional_ignored_exceptions [
    TuistWeb.Errors.BadRequestError,
    TuistWeb.Errors.NotFoundError,
    TuistWeb.Errors.TooManyRequestsError,
    TuistWeb.Errors.UnauthorizedError
  ]

  # Webhook deliveries fail whenever a customer's receiver misbehaves —
  # non-2xx responses, closed connections, timeouts. Each attempt is
  # already recorded in ClickHouse and surfaced on the dashboard, and
  # Oban retries on the RFC schedule, so the Oban.PerformError wrapping
  # the worker's error return carries no signal for us. Bugs inside the
  # worker raise their own exception types and are still reported.
  @webhook_delivery_worker inspect(Tuist.Webhooks.Workers.DeliveryWorker)

  def before_send(%Sentry.Event{original_exception: %Oban.PerformError{}, tags: %{oban_worker: @webhook_delivery_worker}}) do
    false
  end

  def before_send(event) do
    TuistCommon.SentryEventFilter.before_send(event, @additional_ignored_exceptions)
  end
end
