defmodule TuistOps.JIT.SlackClient do
  @moduledoc """
  Thin Slack API wrapper for the JIT elevation bot. Only the calls
  the bot actually needs (chat.postMessage, chat.update,
  chat.postEphemeral) so the surface is small and the credentials
  pass-through is obvious.

  Slack calls live here rather than a shared client because this
  service has no other Slack use case.
  """

  alias TuistOps.Environment

  @chat_post_message_url "https://slack.com/api/chat.postMessage"
  @chat_update_url "https://slack.com/api/chat.update"
  @chat_post_ephemeral_url "https://slack.com/api/chat.postEphemeral"
  @users_info_url "https://slack.com/api/users.info"

  @doc """
  Resolves a Slack user id to their workspace email. Requires the
  `users:read` + `users:read.email` scopes on the bot app. The
  caller treats the returned email as the tailnet identity for
  ACL mutations (assumes Slack workspace email matches each
  person's tailnet login email).
  """
  def user_email(user_id) when is_binary(user_id) do
    @users_info_url
    |> Req.get(headers: headers(), params: [user: user_id])
    |> handle_user_info()
  end

  defp handle_user_info({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    case body do
      %{"ok" => true, "user" => %{"profile" => %{"email" => email}}} when is_binary(email) ->
        {:ok, email}

      %{"ok" => true} ->
        {:error, :missing_email_scope_or_email}

      %{"ok" => false, "error" => err} ->
        {:error, {:slack_error, err}}

      other ->
        {:error, {:slack_unexpected, other}}
    end
  end

  defp handle_user_info({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_status, status, body}}
  end

  defp handle_user_info({:error, reason}), do: {:error, {:http_error, reason}}

  @doc """
  Posts a message to `channel_id`. Returns `{:ok, message_ts}` so
  the caller can `update_message/3` later to mutate the same
  Block Kit card.
  """
  def post_message(channel_id, blocks, opts \\ []) do
    body = %{
      channel: channel_id,
      blocks: blocks,
      text: Keyword.get(opts, :fallback_text, "Tailscale JIT request"),
      unfurl_links: false,
      unfurl_media: false
    }

    @chat_post_message_url
    |> Req.post(headers: headers(), body: JSON.encode!(body))
    |> handle_post(:ts)
  end

  @doc """
  Replaces the blocks on an existing message. Used to mutate the
  approval card after Approve/Deny/Revoke.
  """
  def update_message(channel_id, message_ts, blocks, opts \\ []) do
    body = %{
      channel: channel_id,
      ts: message_ts,
      blocks: blocks,
      text: Keyword.get(opts, :fallback_text, "Tailscale JIT request")
    }

    @chat_update_url
    |> Req.post(headers: headers(), body: JSON.encode!(body))
    |> handle_post(:ok)
  end

  @doc """
  Posts a message visible only to `user_id` in `channel_id`. Used
  for "cannot self-approve" feedback to the clicker.
  """
  def ephemeral(channel_id, user_id, text) do
    body = %{
      channel: channel_id,
      user: user_id,
      text: text
    }

    @chat_post_ephemeral_url
    |> Req.post(headers: headers(), body: JSON.encode!(body))
    |> handle_post(:ok)
  end

  defp headers do
    [
      {"Authorization", "Bearer #{Environment.slack_bot_token()}"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]
  end

  defp handle_post({:ok, %Req.Response{status: status, body: body}}, return) when status in 200..299 do
    case body do
      %{"ok" => true} = parsed ->
        case return do
          :ts -> {:ok, parsed["ts"]}
          :ok -> :ok
        end

      %{"ok" => false, "error" => err} ->
        {:error, {:slack_error, err}}

      other ->
        {:error, {:slack_unexpected, other}}
    end
  end

  defp handle_post({:ok, %Req.Response{status: status, body: body}}, _) do
    {:error, {:http_status, status, body}}
  end

  defp handle_post({:error, reason}, _), do: {:error, {:http_error, reason}}
end
