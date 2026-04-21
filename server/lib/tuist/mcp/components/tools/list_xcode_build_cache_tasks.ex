defmodule Tuist.MCP.Components.Tools.ListXcodeBuildCacheTasks do
  @moduledoc """
  List cacheable tasks (cache hits/misses) for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_cache_tasks",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter by cache status: hit_local, hit_remote, or miss."
        },
        "type" => %{
          "type" => "string",
          "description" => "Filter by task type: clang or swift."
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
      "List cacheable tasks (cache hits/misses) for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

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
        Enum.reduce([:status, :type], filters, fn field, acc ->
          case Map.get(args, to_string(field)) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      {tasks, meta} =
        Builds.list_cacheable_tasks(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      {:ok,
       %{
         tasks:
           Enum.map(tasks, fn task ->
             %{
               type: to_string(task.type),
               status: to_string(task.status),
               key: task.key,
               read_duration: task.read_duration,
               write_duration: task.write_duration,
               description: task.description,
               cas_output_node_ids: task.cas_output_node_ids
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end
end
