defmodule Tuist.Slack.Client do
  @moduledoc """
  Slack API client for OAuth operations and notification delivery.

  New OAuth flows request only the `incoming-webhook` scope and notifications
  are delivered by POSTing to the webhook URL Slack returns at install time
  (`post_to_webhook/2`).

  Notification destinations created before the webhook flow existed only have
  a bot token + channel id, so `post_message/3` (chat.postMessage) is kept as
  a fallback. Each destination upgrades to the webhook path the next time the
  user re-selects its channel.
  """

  alias Tuist.Environment

  @oauth_token_url "https://slack.com/api/oauth.v2.access"
  @chat_post_message_url "https://slack.com/api/chat.postMessage"

  # Slack incoming-webhook error strings that mean the destination is dead
  # and further attempts will keep failing until the user re-authorizes the
  # app: token revoked, workspace uninstalled the app, service or team is
  # gone. Slack returns these as a plain-text body alongside a 400/401/403
  # (or 404 for `no_service`, already handled by the status-only clause).
  # See https://api.slack.com/messaging/webhooks#handling_errors.
  @permanent_webhook_errors ~w(invalid_token no_service no_service_id no_team team_disabled action_prohibited)

  @doc """
  Exchanges an OAuth authorization code for an `incoming-webhook` token.
  """
  def exchange_code_for_token(code, redirect_uri) do
    client_id = Environment.slack_client_id()
    client_secret = Environment.slack_client_secret()

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: redirect_uri
    }

    @oauth_token_url
    |> Req.post(form: body)
    |> handle_oauth_response()
  end

  @doc """
  Posts a Slack Block Kit message to the given incoming-webhook URL.
  """
  def post_to_webhook(webhook_url, blocks) when is_binary(webhook_url) do
    headers = [{"Content-Type", "application/json"}]
    body = JSON.encode!(%{blocks: blocks, unfurl_links: false, unfurl_media: false})

    webhook_url
    |> Req.post(headers: headers, body: body)
    |> handle_webhook_response()
  end

  @doc """
  Posts a Slack Block Kit message via `chat.postMessage` using a legacy bot
  token. Kept as a fallback for destinations installed before the webhook
  flow existed.
  """
  def post_message(access_token, channel_id, blocks) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    body = JSON.encode!(%{channel: channel_id, blocks: blocks, unfurl_links: false, unfurl_media: false})

    @chat_post_message_url
    |> Req.post(headers: headers, body: body)
    |> handle_post_response()
  end

  defp handle_oauth_response({:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}}) do
    result = %{
      access_token: body["access_token"],
      team_id: body["team"]["id"],
      team_name: body["team"]["name"],
      bot_user_id: body["bot_user_id"]
    }

    result =
      if body["incoming_webhook"] do
        webhook = body["incoming_webhook"]

        Map.put(result, :incoming_webhook, %{
          channel: webhook["channel"],
          channel_id: webhook["channel_id"],
          url: webhook["url"]
        })
      else
        result
      end

    {:ok, result}
  end

  defp handle_oauth_response({:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}}) do
    {:error, error}
  end

  defp handle_oauth_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Slack OAuth responded #{status} with body: #{inspect(body)}"}
  end

  defp handle_oauth_response({:error, reason}) do
    {:error, "Slack OAuth request failed: #{inspect(reason)}"}
  end

  defp handle_webhook_response({:ok, %Req.Response{status: status}}) when status in 200..299 do
    :ok
  end

  # Any 4xx from Slack is a client-side error: the same request will fail
  # the same way on retry. Split it into "the webhook is permanently dead"
  # (caller clears the destination) and "we sent something Slack rejected"
  # (caller discards the job without touching the destination, so we still
  # see the failure once for investigation).
  #
  # 404 always maps to :webhook_revoked — a Slack hooks URL only 404s when
  # it isn't a live webhook any more (revoked, uninstalled, deleted). The
  # other 4xx cases only clear the destination when the body matches one of
  # Slack's documented permanent-error strings.
  defp handle_webhook_response({:ok, %Req.Response{status: 404}}) do
    {:error, :webhook_revoked}
  end

  defp handle_webhook_response({:ok, %Req.Response{status: status, body: body}}) when status in 400..499 do
    if permanent_webhook_error?(body) do
      {:error, :webhook_revoked}
    else
      {:error, {:bad_request, status, body}}
    end
  end

  # 5xx is Slack's side — return a transient error so Oban retries.
  defp handle_webhook_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Slack incoming-webhook responded #{status} with response body: #{inspect(body)}"}
  end

  defp handle_webhook_response({:error, reason}) do
    {:error, "Slack incoming-webhook request failed: #{inspect(reason)}"}
  end

  defp permanent_webhook_error?(body) when is_binary(body) do
    String.trim(body) in @permanent_webhook_errors
  end

  defp permanent_webhook_error?(_body), do: false

  defp handle_post_response({:ok, %Req.Response{status: 200, body: %{"ok" => true}}}) do
    :ok
  end

  defp handle_post_response({:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}}) do
    {:error, error}
  end

  defp handle_post_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Slack chat.postMessage responded #{status} with response body: #{inspect(body)}"}
  end

  defp handle_post_response({:error, reason}) do
    {:error, "Slack chat.postMessage request failed: #{inspect(reason)}"}
  end
end
