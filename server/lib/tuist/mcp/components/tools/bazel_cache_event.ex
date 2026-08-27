defmodule Tuist.MCP.Components.Tools.BazelCacheEvent do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "invocation_id" => %{"type" => "string"},
        "outcome" => %{"type" => "string"},
        "action_digest" => %{"type" => "string"},
        "action_mnemonic" => %{"type" => "string"},
        "target_label" => %{"type" => "string"},
        "configuration_id" => %{"type" => "string"},
        "size" => %{"type" => "integer"},
        "duration_ms" => %{"type" => "integer"},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "invocation_id",
        "outcome",
        "action_digest",
        "action_mnemonic",
        "target_label",
        "configuration_id",
        "size",
        "duration_ms",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end

  def json(event) do
    %{
      id: event.id,
      invocation_id: event.invocation_id,
      outcome: to_string(event.outcome),
      action_digest: event.action_digest,
      action_mnemonic: event.action_mnemonic,
      target_label: event.target_label,
      configuration_id: event.configuration_id,
      size: event.size,
      duration_ms: event.duration_ms,
      inserted_at: Formatter.iso8601(event.inserted_at, naive: :utc)
    }
  end
end
