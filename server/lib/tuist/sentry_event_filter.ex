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

  def before_send(%Sentry.Event{} = event) do
    if github_webhook_body_read_timeout?(event) do
      false
    else
      TuistCommon.SentryEventFilter.before_send(event, @additional_ignored_exceptions)
    end
  end

  def before_send(event) do
    TuistCommon.SentryEventFilter.before_send(event, @additional_ignored_exceptions)
  end

  defp github_webhook_body_read_timeout?(event) do
    body_read_timeout?(event) and github_webhook_url?(event)
  end

  defp body_read_timeout?(%Sentry.Event{original_exception: %Bandit.HTTPError{message: "Body read timeout"}}), do: true

  defp body_read_timeout?(%Sentry.Event{exception: exceptions}) when is_list(exceptions) do
    Enum.any?(exceptions, fn
      %Sentry.Interfaces.Exception{type: "Bandit.HTTPError", value: "Body read timeout"} -> true
      %{type: "Bandit.HTTPError", value: "Body read timeout"} -> true
      _ -> false
    end)
  end

  defp body_read_timeout?(_event), do: false

  defp github_webhook_url?(event) do
    case event_url(event) do
      nil ->
        false

      url ->
        case URI.parse(url) do
          %URI{path: "/webhooks/github"} -> true
          _ -> false
        end
    end
  end

  defp event_url(%Sentry.Event{request: %Sentry.Interfaces.Request{url: url}}) when is_binary(url), do: url

  defp event_url(%Sentry.Event{request: %{url: url}}) when is_binary(url), do: url
  defp event_url(%Sentry.Event{tags: tags}), do: tag_value(tags, "url")
  defp event_url(_event), do: nil

  defp tag_value(tags, key) when is_map(tags), do: tag_value(Map.to_list(tags), key)

  defp tag_value(tags, key) when is_list(tags) do
    Enum.find_value(tags, fn
      {tag_key, tag_value} when is_binary(tag_value) ->
        if to_string(tag_key) == key, do: tag_value

      %{key: tag_key, value: tag_value} when is_binary(tag_value) ->
        if to_string(tag_key) == key, do: tag_value

      _ ->
        nil
    end)
  end

  defp tag_value(_tags, _key), do: nil
end
