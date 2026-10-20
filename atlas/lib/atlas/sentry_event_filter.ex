defmodule Atlas.SentryEventFilter do
  @moduledoc """
  `before_send` callback that drops Sentry events for non-actionable
  exceptions (router 404s, transport errors, etc.) before they reach the
  upstream pipeline.
  """

  alias Phoenix.Router.NoRouteError

  @ignored_exceptions [
    Bandit.HTTPError,
    Bandit.TransportError,
    NoRouteError
  ]

  @ignored_exception_types Enum.map(@ignored_exceptions, &inspect/1)

  def before_send(%Sentry.Event{original_exception: exception, source: source} = event) when is_exception(exception) do
    if exception.__struct__ in @ignored_exceptions or
         Sentry.DefaultEventFilter.exclude_exception?(exception, source) do
      false
    else
      event
    end
  end

  def before_send(%Sentry.Event{exception: exceptions} = event) when is_list(exceptions) do
    if Enum.any?(exceptions, &ignored_exception?/1) do
      false
    else
      event
    end
  end

  def before_send(event), do: event

  defp ignored_exception?(%{type: type}) when is_binary(type), do: type in @ignored_exception_types
  defp ignored_exception?(_), do: false
end
