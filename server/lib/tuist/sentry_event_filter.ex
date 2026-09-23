defmodule Tuist.SentryEventFilter do
  @moduledoc """
  Filters events before they are sent to Sentry.
  This module is used to exclude expected errors that are not actionable.
  """

  alias Tuist.Telemetry.QueryErrorContext

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

  # When a LiveView raises a 4xx exception (e.g. NotFoundError) during a
  # connected mount, such as a live navigation to a missing docs page,
  # LiveView reloads the page and re-raises it as a ReloadError from the
  # static render. The original exception is already ignored above, so its
  # reload wrapper carries no signal either.
  def before_send(%Sentry.Event{original_exception: %Phoenix.LiveView.ReloadError{plug_status: status}})
      when status in 400..499 do
    false
  end

  def before_send(event) do
    event
    |> QueryErrorContext.enrich_event()
    |> TuistCommon.SentryEventFilter.before_send(@additional_ignored_exceptions)
  end
end
