defmodule Tuist.MCP.Components.Tools.GetBazelBuildStep do
  @moduledoc "Recorded Bazel profile intervals with action outcomes and separately fetched sanitized logs when published by Bazel. IDs are opaque and scoped to the invocation. Profile times are milliseconds relative to the profile start; time filters select overlaps. Older builds fall back to bounded BEP summaries. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "get_bazel_build_step",
    title: "Get Bazel Build Step",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string"},
        "project_handle" => %{"type" => "string"},
        "invocation_id" => %{"type" => "string", "description" => "Bazel invocation identifier."},
        "step_id" => %{
          "type" => "string",
          "maxLength" => 128,
          "description" => "Opaque step ID from list_bazel_build_steps."
        }
      },
      "required" => ["account_handle", "project_handle", "invocation_id", "step_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "project" => %{"type" => "string"},
        "target" => %{"type" => "string"},
        "category" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "start_ms" => %{"type" => "number"},
        "duration_ms" => %{"type" => "number"},
        "log" => %{"type" => ["string", "null"]},
        "log_truncated" => %{"type" => "boolean"}
      },
      "required" => [
        "id",
        "title",
        "project",
        "target",
        "category",
        "status",
        "start_ms",
        "duration_ms",
        "log",
        "log_truncated"
      ],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.Builds.RecordedSteps, as: Steps

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, args, project) do
    id = Map.get(args, "invocation_id")

    with {:ok, build} <- Bazel.get_invocation(project.id, id, include_cache_summary: false),
         {:ok, result} <- Steps.get(build, Map.get(args, "step_id")) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
    end
  end
end
