defmodule Tuist.MCP.Components.Tools.ListBazelBuildSteps do
  @moduledoc "Recorded Bazel profile intervals with action outcomes and separately fetched sanitized logs when published by Bazel. IDs are opaque and scoped to the invocation. Profile times are milliseconds relative to the profile start; time filters select overlaps. Older builds fall back to bounded BEP summaries. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "list_bazel_build_steps",
    title: "List Bazel Build Steps",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string"},
        "project_handle" => %{"type" => "string"},
        "invocation_id" => %{"type" => "string", "description" => "Bazel invocation identifier."},
        "page" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
        "search" => %{
          "type" => "string",
          "maxLength" => 512,
          "description" => "Case-insensitive title, project, or target search."
        },
        "project" => %{"type" => "string", "maxLength" => 512},
        "target" => %{"type" => "string", "maxLength" => 512},
        "category" => %{
          "type" => "string",
          "maxLength" => 128,
          "description" => "Exact recorded category, as returned by a recorded step."
        },
        "status" => %{
          "type" => "string",
          "enum" => ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)
        },
        "start_ms" => %{"type" => "number", "minimum" => 0},
        "end_ms" => %{"type" => "number", "minimum" => 0},
        "sort_by" => %{
          "type" => "string",
          "enum" => ["duration_ms", "start_ms"],
          "description" => "Duration descending (default) or start ascending, with step-ID tie breaking."
        }
      },
      "required" => ["account_handle", "project_handle", "invocation_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "steps" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "project" => %{"type" => "string"},
              "target" => %{"type" => "string"},
              "category" => %{"type" => "string"},
              "status" => %{"type" => "string"},
              "start_ms" => %{"type" => "number"},
              "duration_ms" => %{"type" => "number"}
            },
            "required" => ["id", "title", "project", "target", "category", "status", "start_ms", "duration_ms"],
            "additionalProperties" => false
          }
        },
        "availability" => %{"type" => "string", "enum" => ["available", "processing", "unavailable"]},
        "time_origin" => %{"type" => "string"},
        "coverage" => %{"type" => "string"},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["steps", "availability", "pagination_metadata", "time_origin", "coverage"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.Builds.RecordedSteps, as: Steps

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, args, project) do
    id = Map.get(args, "invocation_id")

    with {:ok, build} <- Bazel.get_invocation(project.id, id, include_cache_summary: false),
         {:ok, result} <- Steps.list(build, args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
    end
  end
end
