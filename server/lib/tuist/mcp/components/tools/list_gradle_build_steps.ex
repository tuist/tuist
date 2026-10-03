defmodule Tuist.MCP.Components.Tools.ListGradleBuildSteps do
  @moduledoc "List recorded Gradle build steps. IDs are opaque and scoped to the build. Logs are not collected. Gradle includes timed tasks, configuration and transforms; legacy reports use the first recorded timestamp as origin. Times are milliseconds; time filters select overlaps and end_ms is exclusive. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "list_gradle_build_steps",
    title: "List Gradle Build Steps",
    read_only_hint: true,
    schema: Tuist.MCP.Components.Tools.BuildStep.input(:gradle, false),
    output_schema: Tuist.MCP.Components.Tools.BuildStep.list(:gradle)

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
