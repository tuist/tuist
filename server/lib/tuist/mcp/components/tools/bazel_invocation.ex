defmodule Tuist.MCP.Components.Tools.BazelInvocation do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "invocation_id" => %{"type" => "string"},
        "command" => %{"type" => "string"},
        "target_patterns" => %{"type" => "array", "items" => %{"type" => "string"}},
        "git_branch" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "is_ci" => %{"type" => "boolean"},
        "cache_endpoint" => %{"type" => "string"},
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
        "target_patterns",
        "git_branch",
        "git_commit_sha",
        "is_ci",
        "cache_endpoint",
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
      target_patterns: invocation.target_patterns,
      git_branch: invocation.git_branch,
      git_commit_sha: invocation.git_commit_sha,
      is_ci: invocation.is_ci,
      cache_endpoint: invocation.cache_endpoint,
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
