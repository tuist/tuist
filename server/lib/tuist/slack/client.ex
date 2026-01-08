defmodule Tuist.Slack.Client do
  @moduledoc """
  Slack API client for OAuth operations and messaging.
  """

  alias Tuist.Environment

  @oauth_token_url "https://slack.com/api/oauth.v2.access"
  @chat_post_message_url "https://slack.com/api/chat.postMessage"

  @doc """
  Exchanges an OAuth authorization code for an access token.
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
  Posts a message to a channel using the provided access token.
  """
  def post_message(access_token, channel_id, blocks) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    body = JSON.encode!(%{channel: channel_id, blocks: blocks})

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
          channel_id: webhook["channel_id"]
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

  defp handle_post_response({:ok, %Req.Response{status: 200, body: %{"ok" => true}}}) do
    :ok
  end

  defp handle_post_response({:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}}) do
    {:error, error}
  end

  defp handle_post_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_post_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
