defmodule Tuist.MCP.Components.Tools.ListXcodeBuildFiles do
  @moduledoc """
  List compiled files for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_files",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        },
        "target" => %{
          "type" => "string",
          "description" => "Filter by target name."
        },
        "type" => %{
          "type" => "string",
          "description" => "Filter by file type: swift or c."
        },
        "sort_by" => %{
          "type" => "string",
          "description" => "Sort by field: compilation_duration (default, descending) or path."
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
      "List compiled files for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

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
        Enum.reduce([:target, :type], filters, fn field, acc ->
          case Map.get(args, to_string(field)) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      {order_by, order_directions} =
        case Map.get(args, "sort_by") do
          "path" -> {[:path], [:asc]}
          _ -> {[:compilation_duration], [:desc]}
        end

      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      {files, meta} =
        Builds.list_build_files(%{
          filters: filters,
          order_by: order_by,
          order_directions: order_directions,
          page: page,
          page_size: page_size
        })

      {:ok,
       %{
         files:
           Enum.map(files, fn file ->
             %{
               type: to_string(file.type),
               target: file.target,
               project: file.project,
               path: file.path,
               compilation_duration: file.compilation_duration
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end
end
