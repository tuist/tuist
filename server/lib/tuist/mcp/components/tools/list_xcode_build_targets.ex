defmodule Tuist.MCP.Components.Tools.ListXcodeBuildTargets do
  @moduledoc """
  List build targets for a specific Xcode build run. Only available for projects with build_system=xcode. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :build

  @impl EMCP.Tool
  def name, do: "list_xcode_build_targets"

  @impl EMCP.Tool
  def description,
    do:
      "List build targets for a specific Xcode build run. Only available for projects with build_system=xcode. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}."

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
        case Map.get(args, "status") do
          nil -> filters
          status -> filters ++ [%{field: :status, op: :==, value: status}]
        end

      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)

      {targets, meta} =
        Builds.list_build_targets(%{
          filters: filters,
          order_by: [:build_duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
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
