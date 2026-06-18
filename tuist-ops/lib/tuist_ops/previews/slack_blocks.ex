defmodule TuistOps.Previews.SlackBlocks do
  @moduledoc """
  Slack Block Kit cards for preview environments.
  """

  alias TuistOps.Previews.Preview

  def provisioning(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview requested*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *URL:* https://#{preview.host}
          *Ref:* #{format_ref(preview)}
          *TTL:* #{format_seconds(preview.ttl_seconds)}
          *Reason:* #{preview.reason}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text:
              "GitHub Actions is provisioning it. It expires <!date^#{DateTime.to_unix(preview.expires_at)}^{date_short_pretty} at {time}|soon>."
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
            value: preview.slug
          }
        ]
      }
    ]
  end

  def deleting(%Preview{} = preview) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview deletion requested*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *Reason:* #{preview.reason}
          """
        }
      }
    ]
  end

  def failed(%Preview{} = preview, reason) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Preview request failed*
          *Requester:* <@#{preview.requester_slack_id}>
          *Preview:* `#{preview.slug}`
          *Reason:* #{preview.reason}
          *Error:* #{inspect(reason)}
          """
        }
      }
    ]
  end

  defp format_ref(%Preview{ref_kind: nil}), do: "`workflow default`"
  defp format_ref(%Preview{ref_kind: kind, ref_value: value}), do: "`#{kind}:#{value}`"

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
