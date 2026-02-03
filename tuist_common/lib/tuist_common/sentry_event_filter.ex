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

  def before_send(%Sentry.Event{original_exception: exception, source: event_source} = event, additional_ignored)
      when is_exception(exception) do
    ignored = ignored_exceptions(additional_ignored)

    if exception.__struct__ in ignored or Sentry.DefaultEventFilter.exclude_exception?(exception, event_source) do
      false
    else
      event
    end
  end

  def before_send(%Sentry.Event{} = event, additional_ignored) do
    ignored = ignored_exceptions(additional_ignored)

    if ignored_exception_type?(event, ignored) do
      false
    else
      event
    end
  end

  def before_send(event, _additional_ignored), do: event

  defp ignored_exceptions(additional_ignored) do
    @default_ignored_exceptions ++ additional_ignored
  end

  defp ignored_exception_type?(%Sentry.Event{exception: exceptions}, ignored)
       when is_list(exceptions) do
    ignored_types =
      ignored
      |> Enum.map(&inspect/1)
      |> MapSet.new()

    Enum.any?(exceptions, fn
      %Sentry.Interfaces.Exception{type: type} -> MapSet.member?(ignored_types, type)
      %{type: type} when is_binary(type) -> MapSet.member?(ignored_types, type)
      _ -> false
    end)
  end

  defp ignored_exception_type?(_event, _ignored), do: false
end
