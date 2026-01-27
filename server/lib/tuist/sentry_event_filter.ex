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

  def before_send(event) do
    TuistCommon.SentryEventFilter.before_send(event, @additional_ignored_exceptions)
  end
end
