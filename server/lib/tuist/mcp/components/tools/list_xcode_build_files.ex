defmodule Tuist.MCP.Components.Tools.ListXcodeBuildFiles do
  @moduledoc """
  List compiled files for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :build

  @impl EMCP.Tool
  def name, do: "list_xcode_build_files"

  @impl EMCP.Tool
  def description,
    do:
      "List compiled files for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
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

      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)

      {files, meta} =
        Builds.list_build_files(%{
          filters: filters,
          order_by: order_by,
          order_directions: order_directions,
          page: page,
          page_size: page_size
        })

      data = %{
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
