defmodule Tuist.SentryEventFilter do
  @moduledoc """
  Filters events before they are sent to Sentry.
  This module is used to exclude expected errors that are not actionable.
  """

  @behaviour Sentry.EventFilter

  @ignored_exceptions [
    Bandit.TransportError,
    TuistWeb.Errors.BadRequestError,
    TuistWeb.Errors.NotFoundError,
    TuistWeb.Errors.TooManyRequestsError,
    TuistWeb.Errors.UnauthorizedError
  ]

  @impl Sentry.EventFilter
  def exclude_exception?(%{original_exception: exception}, :plug) do
    exception.__struct__ in @ignored_exceptions
  end

  def exclude_exception?(_, _), do: false
end
