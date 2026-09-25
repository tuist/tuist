defmodule Atlas.MCP.Serializers.Nudges do
  @moduledoc "Serializes nudges for MCP tool responses."

  alias Atlas.MCP.Tool

  def list_response(nudges), do: %{nudges: nudges, count: length(nudges)}

  def list_response_schema do
    %{
      "type" => "object",
      "properties" => %{
        "nudges" => %{"type" => "array", "items" => nudge_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["nudges", "count"],
      "additionalProperties" => false
    }
  end

  def nudge(nudge) do
    %{
      id: nudge.id,
      account_id: nudge.account_id,
      contact_id: nudge.contact_id,
      signal: nudge.signal,
      state: nudge.state,
      severity: nudge.severity,
      title: nudge.title,
      rationale: nudge.rationale,
      evidence: nudge.evidence,
      draft_subject: nudge.draft_subject,
      draft_body: nudge.draft_body,
      claimed_by_user_id: nudge.claimed_by_user_id,
      claimed_at: Tool.iso8601(nudge.claimed_at),
      dismissed_at: Tool.iso8601(nudge.dismissed_at),
      dismissed_reason: nudge.dismissed_reason,
      dismissed_until: Tool.iso8601(nudge.dismissed_until),
      expired_at: Tool.iso8601(nudge.expired_at),
      slack_channel_id: nudge.slack_channel_id,
      slack_message_ts: nudge.slack_message_ts,
      expires_at: Tool.iso8601(nudge.expires_at),
      inserted_at: Tool.iso8601(nudge.inserted_at)
    }
  end

  def nudge_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "contact_id" => nullable_string,
        "signal" => %{"type" => "string"},
        "state" => %{"type" => "string"},
        "severity" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "rationale" => %{"type" => "string"},
        "evidence" => %{"type" => "object"},
        "draft_subject" => %{"type" => "string"},
        "draft_body" => %{"type" => "string"},
        "claimed_by_user_id" => nullable_string,
        "claimed_at" => nullable_string,
        "dismissed_at" => nullable_string,
        "dismissed_reason" => nullable_string,
        "dismissed_until" => nullable_string,
        "expired_at" => nullable_string,
        "slack_channel_id" => nullable_string,
        "slack_message_ts" => nullable_string,
        "expires_at" => %{"type" => "string"},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "account_id",
        "signal",
        "state",
        "severity",
        "title",
        "rationale",
        "evidence",
        "draft_subject",
        "draft_body",
        "expires_at",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end
end
