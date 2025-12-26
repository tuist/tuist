defmodule Tuist.Slack.Client do
  @moduledoc """
  Slack API client for OAuth operations and channel management.
  """

  alias Tuist.Environment

  @oauth_token_url "https://slack.com/api/oauth.v2.access"
  @conversations_list_url "https://slack.com/api/conversations.list"
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
  Lists a page of channels available to the bot in the workspace.
  Returns {:ok, channels, next_cursor} or {:error, reason}.
  """
  def list_channels(access_token, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 200)

    params = maybe_add_cursor(%{types: "public_channel,private_channel", exclude_archived: true, limit: limit}, cursor)

    headers = [{"Authorization", "Bearer #{access_token}"}]

    @conversations_list_url
    |> Req.get(headers: headers, params: params)
    |> handle_channels_response()
  end

  @doc """
  Lists all channels available to the bot in the workspace by fetching all pages.
  Returns {:ok, channels} or {:error, reason}.
  """
  def list_all_channels(access_token) do
    list_all_channels_recursively(access_token, [], nil)
  end

  defp list_all_channels_recursively(access_token, accumulated_channels, cursor) do
    opts = if cursor, do: [cursor: cursor], else: []

    case list_channels(access_token, opts) do
      {:ok, channels, next_cursor} ->
        all_channels = accumulated_channels ++ channels

        case next_cursor do
          nil -> {:ok, all_channels}
          "" -> {:ok, all_channels}
          _ -> list_all_channels_recursively(access_token, all_channels, next_cursor)
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Posts a message to a channel using the provided access token.
  """
  def post_message(access_token, channel_id, blocks) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{channel: channel_id, blocks: blocks})

    @chat_post_message_url
    |> Req.post(headers: headers, body: body)
    |> handle_post_response()
  end

  defp maybe_add_cursor(params, nil), do: params
  defp maybe_add_cursor(params, cursor), do: Map.put(params, :cursor, cursor)

  defp handle_oauth_response({:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}}) do
    {:ok,
     %{
       access_token: body["access_token"],
       team_id: body["team"]["id"],
       team_name: body["team"]["name"],
       bot_user_id: body["bot_user_id"]
     }}
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

  defp handle_channels_response({:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}}) do
    channels =
      Enum.map(body["channels"], fn channel ->
        %{
          id: channel["id"],
          name: channel["name"],
          is_private: channel["is_private"]
        }
      end)

    {:ok, channels, body["response_metadata"]["next_cursor"]}
  end

  defp handle_channels_response({:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}}) do
    {:error, error}
  end

  defp handle_channels_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_channels_response({:error, reason}) do
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
