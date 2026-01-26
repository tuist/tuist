defmodule Cache.SentryEventFilter do
  @moduledoc """
  Filters events before they are sent to Sentry.
  This module is used to exclude expected errors that are not actionable.
  """

  @behaviour Sentry.EventFilter

  @ignored_exceptions [
    Bandit.TransportError
  ]

  @impl Sentry.EventFilter
  def exclude_exception?(%{original_exception: exception}, :plug) do
    exception.__struct__ in @ignored_exceptions
  end

  def exclude_exception?(_, _), do: false
end
