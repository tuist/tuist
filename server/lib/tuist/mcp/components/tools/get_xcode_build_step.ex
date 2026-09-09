defmodule Tuist.MCP.Components.Tools.GetXcodeBuildStep do
  @moduledoc "Get a recorded Xcode build step and its log. Logs retain up to 64 KiB per step; log_truncated indicates omitted output. Steps and logs expire after 90 days. An empty log means no output was recorded."
  use Tuist.MCP.Tool,
    name: "get_xcode_build_step",
    title: "Get Xcode Build Step",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{"type" => "string", "description" => "Build UUID or Tuist build dashboard URL."},
        "step_id" => %{
          "type" => "string",
          "pattern" => "^[0-9]{1,20}$",
          "description" => "Decimal string step ID from list_xcode_build_steps; preserve its full precision."
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
        "log" => %{"type" => "string"},
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

  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(conn, args) do
    id = MCPTool.resource_id(Map.get(args, "build_run_id"))

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(Builds.get_build(id), conn.assigns, :read, :build, "Build not found: #{id}"),
         {:ok, result} <- Steps.get(build.id, Map.get(args, "step_id")) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
      error -> error
    end
  end
end
