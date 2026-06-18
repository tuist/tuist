defmodule TuistOps.Previews.SlackBlocks do
  @moduledoc """
  Slack Block Kit cards for preview environments.
  """

  alias TuistOps.Previews.Request

  def provisioning(%Request{} = request) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview requested*
          *Requester:* <@#{request.requester_slack_id}>
          *Preview:* `#{request.slug}`
          *URL:* https://#{request.host}
          *Ref:* #{format_ref(request)}
          *TTL:* #{format_seconds(request.ttl_seconds)}
          *Reason:* #{request.reason}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text:
              "GitHub Actions is provisioning it. It expires <!date^#{DateTime.to_unix(request.expires_at)}^{date_short_pretty} at {time}|soon>."
          }
        ]
      },
      %{
        type: "actions",
        block_id: "preview_actions",
        elements: [
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Delete"},
            action_id: "preview_delete",
            value: request.slug
          }
        ]
      }
    ]
  end

  def deleting(%Request{} = request) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview deletion requested*
          *Requester:* <@#{request.requester_slack_id}>
          *Preview:* `#{request.slug}`
          *Reason:* #{request.reason}
          """
        }
      }
    ]
  end

  def failed(%Request{} = request, reason) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview request failed*
          *Requester:* <@#{request.requester_slack_id}>
          *Preview:* `#{request.slug}`
          *Reason:* #{request.reason}
          *Error:* #{inspect(reason)}
          """
        }
      }
    ]
  end

  defp format_ref(%Request{ref_kind: nil}), do: "`workflow default`"
  defp format_ref(%Request{ref_kind: kind, ref_value: value}), do: "`#{kind}:#{value}`"

  defp format_seconds(nil), do: "n/a"
  defp format_seconds(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  defp format_seconds(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)

    cond do
      days > 0 and hours > 0 -> "#{days}d #{hours}h"
      days > 0 -> "#{days}d"
      true -> "#{hours}h"
    end
  end
end
