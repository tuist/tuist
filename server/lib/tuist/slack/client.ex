defmodule Tuist.Slack.Client do
  @moduledoc """
  Slack API client for OAuth operations and incoming-webhook messaging.

  Tuist requests only the `incoming-webhook` OAuth scope. Notifications are
  delivered by POSTing to the webhook URL Slack returns at install time.
  """

  alias Tuist.Environment

  @oauth_token_url "https://slack.com/api/oauth.v2.access"

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
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_oauth_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  defp handle_post_response({:ok, %Req.Response{status: status}}) when status in 200..299 do
    :ok
  end

  defp handle_post_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_post_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
