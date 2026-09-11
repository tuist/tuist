defmodule Tuist.MCP.Components.Tools.ListXcodeBuildSteps do
  @moduledoc "List recorded Xcode build steps without logs. Page size defaults to 20 (max 100). Times are milliseconds from build start; time filters select overlaps with an exclusive end_ms. Steps expire after 90 days; unavailable means not recorded or expired. Use get_xcode_build_step to inspect a log."
  use Tuist.MCP.Tool,
    name: "list_xcode_build_steps",
    title: "List Xcode Build Steps",
    read_only_hint: true,
    schema: Tuist.MCP.Components.Tools.BuildStep.input(:xcode, false),
    output_schema: Tuist.MCP.Components.Tools.BuildStep.list(:xcode)

  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(conn, args) do
    id = MCPTool.resource_id(Map.get(args, "build_run_id"))

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(Builds.get_build(id), conn.assigns, :read, :build, "Build not found: #{id}"),
         {:ok, result} <- Steps.list(build, args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
      error -> error
    end
  end
end
