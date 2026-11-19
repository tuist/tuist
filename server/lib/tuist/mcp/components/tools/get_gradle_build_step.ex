defmodule Tuist.MCP.Components.Tools.GetGradleBuildStep do
  @moduledoc "Get a recorded Gradle build step. IDs are opaque and scoped to the build. For a failed task or configuration operation, log holds the failure message the plugin reported (exception message and cause chain, sanitized, at most 16 KiB); otherwise log is null. Task output is not collected. Gradle includes timed tasks, configuration and transforms; legacy reports use the first recorded timestamp as origin. Times are milliseconds. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "get_gradle_build_step",
    title: "Get Gradle Build Step",
    read_only_hint: true,
    schema: Tuist.MCP.Components.Tools.BuildStep.input(:gradle, true),
    output_schema: Tuist.MCP.Components.Tools.BuildStep.detail(:gradle)

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
