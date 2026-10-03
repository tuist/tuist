defmodule Tuist.SentryEventFilter do
  @moduledoc """
  Filters events before they are sent to Sentry.
  This module is used to exclude expected errors that are not actionable.
  """

  alias Tuist.Telemetry.QueryErrorContext

  # `InvalidCSRFTokenError` fires whenever a POST reaches a CSRF-protected
  # route without a matching token. Every scanner and misconfigured link
  # previewer that touches a form endpoint raises it, so the report
  # carries no signal about broken code — only about background probing —
  # and the plug has already turned the request into a 403. Legitimate
  # regressions (a broken layout, a stale token in our own JS) still
  # surface through the 403 rate in Loki, request-completed traces, and
  # dashboard reports, all of which move together and stay visible even
  # when the Sentry event is dropped.
  #
  # `InvalidCrossOriginRequestError` is deliberately NOT filtered: it
  # trips when a non-XHR GET returns JS from a CSRF-protected pipeline,
  # which historically caught a real layout bug where FunWithFlags.UI's
  # bundled JS asset was routed through `:browser_app` (see
  # `skip_csrf_for_fun_with_flags_assets/2` in the router). Keeping it
  # visible so the next similar layout regression pages us instead of
  # silently 403-ing.
  @additional_ignored_exceptions [
    Plug.CSRFProtection.InvalidCSRFTokenError,
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
    event
    |> QueryErrorContext.enrich_event()
    |> TuistCommon.SentryEventFilter.before_send(@additional_ignored_exceptions)
  end
end
