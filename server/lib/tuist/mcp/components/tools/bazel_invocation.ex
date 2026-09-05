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
        "bazel_version" => %{"type" => "string"},
        "cache_endpoint" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "exit_code" => %{"type" => "integer"},
        "started_at" => %{"type" => "string"},
        "finished_at" => %{"type" => "string"},
        "duration_ms" => %{"type" => "integer"},
        "build_metrics" => build_metrics_schema(),
        "build_timeline" => build_timeline_schema(),
        "critical_path" => critical_path_schema(),
        "cache" => cache_schema()
      },
      "required" => [
        "invocation_id",
        "command",
        "target_patterns",
        "git_branch",
        "git_commit_sha",
        "is_ci",
        "bazel_version",
        "cache_endpoint",
        "status",
        "exit_code",
        "started_at",
        "finished_at",
        "duration_ms",
        "build_metrics",
        "build_timeline",
        "critical_path",
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
      bazel_version: invocation.bazel_version,
      cache_endpoint: invocation.cache_endpoint,
      status: to_string(invocation.status),
      exit_code: invocation.exit_code,
      started_at: Formatter.iso8601(invocation.started_at, naive: :utc),
      finished_at: Formatter.iso8601(invocation.finished_at, naive: :utc),
      duration_ms: invocation.duration_ms,
      build_metrics: build_metrics_json(invocation),
      build_timeline: build_timeline_json(invocation),
      critical_path: critical_path_json(invocation),
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

  defp build_metrics_schema do
    %{
      "type" => "object",
      "description" => "Build metrics reported by Bazel.",
      "properties" => %{
        "cpu_time_ms" => %{
          "type" => "integer",
          "description" => "Total central processing unit time in milliseconds."
        },
        "actions_created" => %{
          "type" => "integer",
          "description" => "Actions Bazel created while analyzing the requested targets."
        },
        "actions_executed" => %{
          "type" => "integer",
          "description" => "Actions Bazel executed, including remote cache hits and excluding local action-cache hits."
        },
        "targets_configured" => %{"type" => "integer", "description" => "Targets Bazel configured."},
        "packages_loaded" => %{"type" => "integer", "description" => "Packages Bazel loaded."}
      },
      "required" => [
        "cpu_time_ms",
        "actions_created",
        "actions_executed",
        "targets_configured",
        "packages_loaded"
      ],
      "additionalProperties" => false
    }
  end

  defp build_timeline_schema do
    %{
      "type" => ["object", "null"],
      "description" => "A bounded timeline containing the analysis phase and up to the 32 longest published actions.",
      "properties" => %{
        "duration_ms" => %{"type" => "integer"},
        "lanes" => %{"type" => "array", "items" => %{"type" => "string"}},
        "spans" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "lane" => %{"type" => "integer"},
              "start_ms" => %{"type" => "integer"},
              "duration_ms" => %{"type" => "integer"},
              "category" => %{"type" => "string"},
              "description" => %{"type" => "string"}
            },
            "required" => ["lane", "start_ms", "duration_ms", "category", "description"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["duration_ms", "lanes", "spans"],
      "additionalProperties" => false
    }
  end

  defp critical_path_schema do
    %{
      "type" => ["object", "null"],
      "description" => "The critical path reported by Bazel, bounded to 32 actions.",
      "properties" => %{
        "duration_ms" => %{"type" => "integer"},
        "actions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "description" => %{"type" => "string"},
              "duration_ms" => %{"type" => "integer"}
            },
            "required" => ["description", "duration_ms"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["duration_ms", "actions"],
      "additionalProperties" => false
    }
  end

  defp build_metrics_json(invocation) do
    %{
      cpu_time_ms: invocation.cpu_time_ms,
      actions_created: invocation.actions_created,
      actions_executed: invocation.actions_executed,
      targets_configured: invocation.targets_configured,
      packages_loaded: invocation.packages_loaded
    }
  end

  defp build_timeline_json(invocation) do
    spans =
      [
        invocation.build_timeline_span_lanes,
        invocation.build_timeline_span_start_ms,
        invocation.build_timeline_span_durations_ms,
        invocation.build_timeline_span_categories,
        invocation.build_timeline_span_descriptions
      ]
      |> Enum.zip()
      |> Enum.map(fn {lane, start_ms, duration_ms, category, description} ->
        %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description}
      end)

    if spans == [] do
      nil
    else
      %{duration_ms: invocation.build_timeline_duration_ms, lanes: invocation.build_timeline_lanes, spans: spans}
    end
  end

  defp critical_path_json(invocation) do
    actions =
      invocation.critical_path_action_descriptions
      |> Enum.zip(invocation.critical_path_action_durations_ms)
      |> Enum.map(fn {description, duration_ms} -> %{description: description, duration_ms: duration_ms} end)

    if invocation.critical_path_duration_ms == 0 and actions == [] do
      nil
    else
      %{duration_ms: invocation.critical_path_duration_ms, actions: actions}
    end
  end
end
