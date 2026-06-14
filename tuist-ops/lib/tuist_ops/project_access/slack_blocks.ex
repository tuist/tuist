defmodule TuistOps.ProjectAccess.SlackBlocks do
  @moduledoc """
  Block Kit message builders for the admin-tier operator access flow.
  Only the admin tier reaches Slack (read access is self-serve and
  never posts a card). Three states: pending (Approve / Deny),
  approved (granted, with the live expiry), and closed (denied /
  expired).

  The requester is identified by their `@tuist.dev` email (they came
  through Pomerium, not Slack), so the card shows the email rather
  than a Slack mention. The Approve/Deny buttons carry the request id
  in their `value`; the `action_id`s are prefixed `pa_` so the shared
  interactive controller routes them to this flow and not the JIT one.
  """

  alias TuistOps.ProjectAccess.Grant
  alias TuistOps.ProjectAccess.Request

  @approve_action "pa_approve"
  @deny_action "pa_deny"

  def approve_action, do: @approve_action
  def deny_action, do: @deny_action

  @doc """
  Pending-approval card. Visible at request time for the admin tier.
  """
  def pending(%Request{} = req) do
    expiry_unix = DateTime.to_unix(req.expires_at)

    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Operator admin access request*
          *Operator:* `#{req.requester_email}`
          *Customer account:* `#{req.account_handle}`
          *Duration:* #{format_seconds(req.ttl_seconds)}
          *Reason:* #{req.reason}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text:
              "Admin access to a customer org needs a second human. Approval expires <!date^#{expiry_unix}^{date_short_pretty} at {time}|soon>. The requester cannot approve their own request, and only Owners/Admins may approve."
          }
        ]
      },
      %{
        type: "actions",
        block_id: "project_access_decision",
        elements: [
          %{
            type: "button",
            style: "primary",
            text: %{type: "plain_text", text: "Approve"},
            action_id: @approve_action,
            value: encode_value(req)
          },
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Deny"},
            action_id: @deny_action,
            value: encode_value(req)
          }
        ]
      }
    ]
  end

  @doc """
  Card shown after Approve: the operator now holds admin access until
  the grant expires.
  """
  def active(%Request{} = req, %Grant{} = grant) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Operator admin access: granted* :unlock:
          *Operator:* `#{req.requester_email}`
          *Approver:* <@#{req.approver_slack_id}>
          *Customer account:* `#{req.account_handle}`
          *Reason:* #{req.reason}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text:
              "Active until <!date^#{DateTime.to_unix(grant.expires_at)}^{date_short_pretty} at {time}|soon>."
          }
        ]
      }
    ]
  end

  @doc """
  Terminal state: no buttons. `status_label` is the human-readable
  outcome; `detail` is an optional extra line.
  """
  def closed(%Request{} = req, status_label, detail \\ nil) do
    text =
      [
        "*Operator admin access: #{status_label}*",
        "*Operator:* `#{req.requester_email}`",
        "*Customer account:* `#{req.account_handle}`",
        "*Reason:* #{req.reason}"
      ] ++ if(detail, do: ["#{detail}"], else: [])

    [
      %{
        type: "section",
        text: %{type: "mrkdwn", text: Enum.join(text, "\n")}
      }
    ]
  end

  @doc """
  Encodes the request id into the button `value`.
  """
  def encode_value(%Request{} = req), do: Integer.to_string(req.id)

  @doc """
  Inverse of `encode_value/1`. Returns `{:ok, request_id}` or `:error`.
  """
  def decode_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp format_seconds(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_seconds(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  defp format_seconds(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    if m == 0, do: "#{h}h", else: "#{h}h #{m}m"
  end
end
