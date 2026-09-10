defmodule Tuist.MCP.Components.Tools.GetGradleBuildStep do
  @moduledoc "Get recorded Gradle build steps. IDs are opaque and scoped to the build. Logs are not collected. Gradle includes timed tasks, configuration and transforms; legacy reports use the first recorded timestamp as origin. Times are milliseconds; time filters select overlaps and end_ms is exclusive. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "get_gradle_build_step",
    title: "Get Gradle Build Step",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{"type" => "string", "description" => "Build UUID or Tuist build dashboard URL."},
        "step_id" => %{
          "type" => "string",
          "maxLength" => 128,
          "description" => "Opaque step ID from list_gradle_build_steps."
        }
      },
      "required" => ["build_run_id", "step_id"]
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

  alias Tuist.Builds.RecordedSteps, as: Steps
  alias Tuist.Gradle
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(conn, args) do
    id = MCPTool.resource_id(Map.get(args, "build_run_id"))

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(Gradle.get_build(id), conn.assigns, :read, :build, "Build not found: #{id}"),
         {:ok, result} <- Steps.get(build, Map.get(args, "step_id")) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
      error -> error
    end
  end
end
