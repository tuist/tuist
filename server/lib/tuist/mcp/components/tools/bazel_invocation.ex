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
        "bazel_version" => %{"type" => "string"},
        "client_platform" => %{"type" => "string"},
        "configurations" => %{"type" => "array", "items" => %{"type" => "string"}},
        "compilation_mode" => %{"type" => "string"},
        "remote_cache_enabled" => %{"type" => "boolean"},
        "remote_execution_enabled" => %{"type" => "boolean"},
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
        "bazel_version",
        "client_platform",
        "configurations",
        "compilation_mode",
        "remote_cache_enabled",
        "remote_execution_enabled",
        "status",
        "exit_code",
        "started_at",
        "finished_at",
        "duration_ms",
        "build_metrics",
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
      bazel_version: invocation.bazel_version,
      client_platform: invocation.client_platform,
      configurations: invocation.configurations,
      compilation_mode: invocation.compilation_mode,
      remote_cache_enabled: invocation.remote_cache_enabled,
      remote_execution_enabled: invocation.remote_execution_enabled,
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
        "writes" => %{"type" => "integer"},
        "download_bytes" => %{"type" => "integer"},
        "upload_bytes" => %{"type" => "integer"},
        "hit_rate" => %{"type" => ["number", "null"]}
      },
      "required" => ["hits", "misses", "writes", "download_bytes", "upload_bytes", "hit_rate"],
      "additionalProperties" => false
    }
  end

  defp build_metrics_schema do
    %{
      "type" => "object",
      "properties" => %{
        "cpu_time_ms" => %{"type" => "integer"},
        "actions_executed" => %{"type" => "integer"},
        "targets_loaded" => %{"type" => "integer"},
        "targets_configured" => %{"type" => "integer"},
        "packages_loaded" => %{"type" => "integer"}
      },
      "required" => ["cpu_time_ms", "actions_executed", "targets_loaded", "targets_configured", "packages_loaded"],
      "additionalProperties" => false
    }
  end

  defp critical_path_schema do
    %{
      "type" => ["object", "null"],
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

  defp build_timeline_schema do
    %{
      "type" => ["object", "null"],
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

  defp critical_path_json(invocation) do
    actions =
      invocation
      |> Map.get(:critical_path_action_descriptions, [])
      |> Enum.zip(Map.get(invocation, :critical_path_action_durations_ms, []))
      |> Enum.map(fn {description, duration_ms} -> %{description: description, duration_ms: duration_ms} end)

    case actions do
      [] -> nil
      actions -> %{duration_ms: Map.get(invocation, :critical_path_duration_ms, 0), actions: actions}
    end
  end

  defp build_metrics_json(invocation) do
    %{
      cpu_time_ms: invocation.cpu_time_ms,
      actions_executed: invocation.actions_executed,
      targets_loaded: invocation.targets_loaded,
      targets_configured: invocation.targets_configured,
      packages_loaded: invocation.packages_loaded
    }
  end

  defp build_timeline_json(invocation) do
    spans =
      [
        Map.get(invocation, :build_timeline_span_lanes, []),
        Map.get(invocation, :build_timeline_span_start_ms, []),
        Map.get(invocation, :build_timeline_span_durations_ms, []),
        Map.get(invocation, :build_timeline_span_categories, []),
        Map.get(invocation, :build_timeline_span_descriptions, [])
      ]
      |> Enum.zip()
      |> Enum.map(fn {lane, start_ms, duration_ms, category, description} ->
        %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description}
      end)

    case spans do
      [] ->
        nil

      spans ->
        %{
          duration_ms: Map.get(invocation, :build_timeline_duration_ms, 0),
          lanes: Map.get(invocation, :build_timeline_lanes, []),
          spans: spans
        }
    end
  end
end
