defmodule Tuist.MCP.Components.Tools.ListXcodeBuildTargets do
  @moduledoc """
  List build targets for a specific Xcode build run. Only available for projects with build_system=xcode. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_targets",
    title: "List Xcode Build Targets",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter by target status: success or failure."
        },
        "page" => %{
          "type" => "integer",
          "description" => "Page number (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["build_run_id"]
    }

  alias Tuist.Builds
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List build targets for a specific Xcode build run. Only available for projects with build_system=xcode. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, _build, _project} <-
           MCPTool.load_and_authorize(
             Builds.get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Build not found: #{build_run_id}"
           ) do
      filters = [%{field: :build_run_id, op: :==, value: build_run_id}]

      filters =
        case Map.get(args, "status") do
          nil -> filters
          status -> filters ++ [%{field: :status, op: :==, value: status}]
        end

      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      {targets, meta} =
        Builds.list_build_targets(%{
          filters: filters,
          order_by: [:build_duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      {:ok,
       %{
         targets:
           Enum.map(targets, fn target ->
             %{
               name: target.name,
               project: target.project,
               build_duration: target.build_duration,
               compilation_duration: target.compilation_duration,
               status: to_string(target.status)
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end
end
