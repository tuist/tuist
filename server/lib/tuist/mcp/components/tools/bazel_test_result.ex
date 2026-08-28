defmodule Tuist.MCP.Components.Tools.BazelTestResult do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "invocation_id" => %{"type" => "string"},
        "target_label" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "duration_ms" => %{"type" => "integer"},
        "attempt_count" => %{"type" => "integer"},
        "finished_at" => %{"type" => "string"}
      },
      "required" => ["id", "invocation_id", "target_label", "status", "duration_ms", "attempt_count", "finished_at"],
      "additionalProperties" => false
    }
  end

  def json(test_result) do
    %{
      id: test_result.id,
      invocation_id: test_result.invocation_id,
      target_label: test_result.target_label,
      status: to_string(test_result.status),
      duration_ms: test_result.duration_ms,
      attempt_count: test_result.attempt_count,
      finished_at: Formatter.iso8601(test_result.finished_at, naive: :utc)
    }
  end
end
