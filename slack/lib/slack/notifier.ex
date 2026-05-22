defmodule Slack.Notifier do
  @moduledoc """
  Sends Slack messages via the Bot API when noteworthy events happen
  (e.g. a new invitation is confirmed and ready for review).

  No-ops when `SLACK_BOT_TOKEN` or `SLACK_CHANNEL_ID` are not configured,
  so dev/test never hit the network.
  """

  alias Slack.Invitations.Invitation

  require Logger

  @api_url "https://slack.com/api/chat.postMessage"

  def config, do: Application.get_env(:slack, :notifier, [])

  def enabled? do
    conf = config()
    token = Keyword.get(conf, :bot_token)
    channel = Keyword.get(conf, :channel_id)
    is_binary(token) and token != "" and is_binary(channel) and channel != ""
  end

  def invitation_confirmed(%Invitation{} = invitation) do
    if enabled?() do
      send_message(build_message(invitation))
    else
      :ok
    end
  end

  defp build_message(invitation) do
    admin_url = Application.get_env(:slack, :notifier, [])[:admin_url] || "/admin/invitations"

    %{
      channel: config()[:channel_id],
      text: "New Slack invitation request from #{invitation.email}",
      blocks: [
        %{
          type: "section",
          text: %{
            type: "mrkdwn",
            text:
              "*New Slack invitation request*\n\n" <>
                "*Email:* #{invitation.email}\n" <>
                "*Reason:* #{invitation.reason}"
          }
        },
        %{
          type: "actions",
          elements: [
            %{
              type: "button",
              text: %{type: "plain_text", text: "Review in admin panel"},
              url: admin_url,
              style: "primary"
            }
          ]
        }
      ]
    }
  end

  defp send_message(payload) do
    headers = [
      {"authorization", "Bearer #{config()[:bot_token]}"},
      {"content-type", "application/json; charset=utf-8"}
    ]

    case Req.post(@api_url, json: payload, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.warning("Slack notification failed: #{error}")
        {:error, error}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Slack API returned unexpected status: #{status}")
        {:error, {:unexpected_status, status}}

      {:error, exception} ->
        Logger.warning("Slack notification request failed: #{Exception.message(exception)}")
        {:error, {:request_failed, exception}}
    end
  end
end
