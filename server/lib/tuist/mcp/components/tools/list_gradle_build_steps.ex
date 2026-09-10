defmodule Tuist.MCP.Components.Tools.ListGradleBuildSteps do
  @moduledoc "List recorded Gradle build steps. IDs are opaque and scoped to the build. Logs are not collected. Gradle includes timed tasks, configuration and transforms; legacy reports use the first recorded timestamp as origin. Times are milliseconds; time filters select overlaps and end_ms is exclusive. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "list_gradle_build_steps",
    title: "List Gradle Build Steps",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{"type" => "string", "description" => "Build UUID or Tuist build dashboard URL."},
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
      "required" => ["build_run_id"]
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

  alias Tuist.Builds.RecordedSteps, as: Steps
  alias Tuist.Gradle
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(conn, args) do
    id = MCPTool.resource_id(Map.get(args, "build_run_id"))

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(Gradle.get_build(id), conn.assigns, :read, :build, "Build not found: #{id}"),
         {:ok, result} <- Steps.list(build, args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
      error -> error
    end
  end
end
