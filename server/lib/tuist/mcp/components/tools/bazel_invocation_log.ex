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
        "observed_at" => %{"type" => "string"}
      },
      "required" => ["id", "invocation_id", "sequence_number", "stream", "message", "observed_at"],
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
      observed_at: Formatter.iso8601(log.observed_at, naive: :utc)
    }
  end
end
