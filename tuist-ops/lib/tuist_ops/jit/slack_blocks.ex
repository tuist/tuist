defmodule TuistOps.JIT.SlackBlocks do
  @moduledoc """
  Block Kit message builders for the JIT elevation flow. Three
  states the approval card moves through: pending (Approve / Deny
  buttons), approved (active until expiry + Revoke button), and
  closed (denied / expired / reverted / failed). The Approve button
  carries the request id AND the requester's Slack id in its
  `action_id` so the controller can reject self-approvals before
  any state transition.
  """

  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Request

  @doc """
  Pending-approval card. Visible at request time.

  `opts[:self_approval_allowed?]` controls the wording of the
  expiry hint: when self-approval is allowed for this requester +
  env combination (per `TuistOps.JIT.Policy`), the "second
  human" hint is suppressed so the card doesn't lie. Default
  `false` keeps the strictest hint when the caller doesn't pass
  the flag.
  """
  def pending(%Request{} = req, opts \\ []) do
    expiry_unix = DateTime.to_unix(req.expires_at)

    hint =
      if Keyword.get(opts, :self_approval_allowed?, false) do
        "Approval expires <!date^#{expiry_unix}^{date_short_pretty} at {time}|soon>."
      else
        "Approval expires <!date^#{expiry_unix}^{date_short_pretty} at {time}|soon>. The requester cannot approve their own request."
      end

    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Tailscale elevation request*
          *Requester:* <@#{req.requester_slack_id}>
          *Group:* `#{req.target_group}`
          *Duration:* #{format_seconds(req.ttl_seconds)}
          *Intent:* #{req.intent}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text: hint
          }
        ]
      },
      %{
        type: "actions",
        block_id: "tailscale_jit_decision",
        elements: [
          %{
            type: "button",
            style: "primary",
            text: %{type: "plain_text", text: "Approve"},
            action_id: "approve",
            value: encode_value(req)
          },
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Deny"},
            action_id: "deny",
            value: encode_value(req)
          }
        ]
      }
    ]
  end

  @doc """
  Card shown after Approve: shows approver and live expiry, with a
  Revoke button that immediately schedules the revert.
  """
  def active(%Request{} = req, %Elevation{} = elev) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: """
          *Tailscale elevation: active* :unlock:
          *Requester:* <@#{req.requester_slack_id}>
          *Approver:* <@#{req.approver_slack_id}>
          *Group:* `#{req.target_group}`
          *Intent:* #{req.intent}
          """
        }
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text: "Active until <!date^#{DateTime.to_unix(elev.expires_at)}^{date_short_pretty} at {time}|soon>."
          }
        ]
      },
      %{
        type: "actions",
        block_id: "tailscale_jit_revoke",
        elements: [
          %{
            type: "button",
            style: "danger",
            text: %{type: "plain_text", text: "Revoke now"},
            action_id: "revoke",
            value: Integer.to_string(elev.id)
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
        "*Tailscale elevation: #{status_label}*",
        "*Requester:* <@#{req.requester_slack_id}>",
        "*Group:* `#{req.target_group}`",
        "*Intent:* #{req.intent}"
      ] ++ if(detail, do: ["#{detail}"], else: [])

    [
      %{
        type: "section",
        text: %{type: "mrkdwn", text: Enum.join(text, "\n")}
      }
    ]
  end

  @doc """
  Encodes (request_id, requester_slack_id) into the button `value`
  so the controller can do the approver≠requester check before
  any database transition.
  """
  def encode_value(%Request{} = req) do
    "#{req.id}:#{req.requester_slack_id}"
  end

  @doc """
  Inverse of `encode_value/1`. Returns `{:ok, request_id,
  requester_slack_id}` or `:error`.
  """
  def decode_value(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [id_str, slack_id] ->
        case Integer.parse(id_str) do
          {id, ""} -> {:ok, id, slack_id}
          _ -> :error
        end

      _ ->
        :error
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
