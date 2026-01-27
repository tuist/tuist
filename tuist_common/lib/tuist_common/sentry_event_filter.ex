defmodule TuistCommon.SentryEventFilter do
  @moduledoc """
  Shared Sentry event filter logic for Tuist services.

  This module provides a `before_send` callback that filters out expected errors
  that are not actionable. Services can use this directly or extend it with
  additional exceptions.

  ## Usage

  In your config (with default exceptions only):

      config :sentry,
        before_send: {TuistCommon.SentryEventFilter, :before_send}

  With additional exceptions:

      config :sentry,
        before_send: {TuistCommon.SentryEventFilter, :before_send, [[MyApp.CustomError]]}
  """

  @default_ignored_exceptions [
    Bandit.TransportError,
    Phoenix.Router.NoRouteError
  ]

  @doc """
  Filters Sentry events, returning `false` for ignored exceptions or the event otherwise.

  Can be used directly as a `before_send` callback or called with additional exceptions.
  """
  def before_send(event, additional_ignored \\ [])

  def before_send(%Sentry.Event{original_exception: exception} = event, additional_ignored) do
    ignored = @default_ignored_exceptions ++ additional_ignored

    if exception.__struct__ in ignored do
      false
    else
      event
    end
  end

  def before_send(event, _additional_ignored), do: event
end
