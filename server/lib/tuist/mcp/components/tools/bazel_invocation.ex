defmodule Tuist.MCP.Components.Tools.BazelInvocation do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "invocation_id" => %{"type" => "string"},
        "command" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "exit_code" => %{"type" => "integer"},
        "started_at" => %{"type" => "string"},
        "finished_at" => %{"type" => "string"},
        "duration_ms" => %{"type" => "integer"},
        "cache" => cache_schema()
      },
      "required" => [
        "invocation_id",
        "command",
        "status",
        "exit_code",
        "started_at",
        "finished_at",
        "duration_ms",
        "cache"
      ],
      "additionalProperties" => false
    }
  end

  def json(invocation) do
    %{
      invocation_id: invocation.invocation_id,
      command: invocation.command,
      status: to_string(invocation.status),
      exit_code: invocation.exit_code,
      started_at: Formatter.iso8601(invocation.started_at, naive: :utc),
      finished_at: Formatter.iso8601(invocation.finished_at, naive: :utc),
      duration_ms: invocation.duration_ms,
      cache: invocation.cache
    }
  end

  defp cache_schema do
    %{
      "type" => "object",
      "properties" => %{
        "hits" => %{"type" => "integer"},
        "misses" => %{"type" => "integer"},
        "download_bytes" => %{"type" => "integer"},
        "upload_bytes" => %{"type" => "integer"},
        "hit_rate" => %{"type" => ["number", "null"]}
      },
      "required" => ["hits", "misses", "download_bytes", "upload_bytes", "hit_rate"],
      "additionalProperties" => false
    }
  end
end
