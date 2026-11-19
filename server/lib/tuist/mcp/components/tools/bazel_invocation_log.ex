defmodule Tuist.MCP.Components.Tools.BazelInvocationLog do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "invocation_id" => %{"type" => "string"},
        "sequence_number" => %{"type" => "integer"},
        "stream" => %{"type" => "string"},
        "message" => %{"type" => "string"},
        "target_label" => %{
          "type" => "string",
          "description" => "The test target a test log belongs to; empty for progress output and older logs."
        },
        "status" => %{
          "type" => "string",
          "description" =>
            "The test attempt's status (`success`, `failure`, `flaky` or `skipped`); empty for progress output and older logs."
        },
        "observed_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "invocation_id",
        "sequence_number",
        "stream",
        "message",
        "target_label",
        "status",
        "observed_at"
      ],
      "additionalProperties" => false
    }
  end

  def json(log) do
    %{
      id: log.id,
      invocation_id: log.invocation_id,
      sequence_number: log.sequence_number,
      stream: log.stream,
      message: log.message,
      target_label: log.target_label,
      status: log.status,
      observed_at: Formatter.iso8601(log.observed_at, naive: :utc)
    }
  end
end
