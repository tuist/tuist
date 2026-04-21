defmodule Tuist.MCP.Components.Tools.ListXcodeBuildCASOutputs do
  @moduledoc """
  List CAS (Content Addressable Storage) outputs for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_cas_outputs",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        },
        "operation" => %{
          "type" => "string",
          "description" => "Filter by operation: download or upload."
        },
        "type" => %{
          "type" => "string",
          "description" => "Filter by CAS output type (e.g. swift, object, dSYM)."
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
      "List CAS (Content Addressable Storage) outputs for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

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
        Enum.reduce([:operation, :type], filters, fn field, acc ->
          case Map.get(args, to_string(field)) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      {outputs, meta} =
        Builds.list_cas_outputs(%{
          filters: filters,
          order_by: [:size],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      {:ok,
       %{
         outputs:
           Enum.map(outputs, fn output ->
             %{
               node_id: output.node_id,
               checksum: output.checksum,
               size: output.size,
               compressed_size: output.compressed_size,
               duration: output.duration,
               operation: to_string(output.operation),
               type: to_string(output.type)
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end
end
