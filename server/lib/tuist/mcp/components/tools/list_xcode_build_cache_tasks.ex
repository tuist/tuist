defmodule Tuist.MCP.Components.Tools.ListXcodeBuildCacheTasks do
  @moduledoc """
  List cacheable tasks (cache hits/misses) for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :build

  @impl EMCP.Tool
  def name, do: "list_xcode_build_cache_tasks"

  @impl EMCP.Tool
  def description,
    do:
      "List cacheable tasks (cache hits/misses) for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
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
  end

  @impl EMCP.Tool
  def call(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, build} <-
           ToolSupport.load_resource(
             get_build(build_run_id),
             "Build not found: #{build_run_id}"
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             conn.assigns,
             build.project_id,
             @authorization_action,
             @authorization_category
           ) do
      filters = [%{field: :build_run_id, op: :==, value: build_run_id}]

      filters =
        Enum.reduce([:status, :type], filters, fn field, acc ->
          case Map.get(args, to_string(field)) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)

      {tasks, meta} =
        Builds.list_cacheable_tasks(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
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
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp get_build(id) do
    case Builds.get_build(id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end
end
