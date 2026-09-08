defmodule Tuist.MCP.Components.Tools.ListXcodeBuildCASOutputs do
  @moduledoc """
  List content-addressable storage outputs for a specific Xcode build run, along with the aggregate transfer totals for the whole run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_cas_outputs",
    title: "List Xcode Build Content-Addressable Storage Outputs",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run, or a Tuist dashboard URL."
        },
        "operation" => %{
          "type" => "string",
          "description" => "Filter by operation: download or upload."
        },
        "type" => %{
          "type" => "string",
          "description" => "Filter by content-addressable storage output type (e.g. swift, object, dSYM)."
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
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "outputs" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "node_id" => %{"type" => "string"},
              "checksum" => %{"type" => "string"},
              "size" => %{"type" => "integer"},
              "compressed_size" => %{"type" => "integer"},
              "duration" => %{"type" => "integer"},
              "operation" => %{"type" => "string", "enum" => ["download", "upload"]},
              "type" => %{"type" => "string"}
            },
            "required" => [
              "node_id",
              "checksum",
              "size",
              "compressed_size",
              "duration",
              "operation",
              "type"
            ],
            "additionalProperties" => false
          }
        },
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema(),
        "totals" => %{
          "type" => "object",
          "description" =>
            "Aggregate transfer totals for the whole build run. Not narrowed by the operation or type filters, and not scoped to the current page.",
          "properties" => %{
            "download_count" => %{"type" => "integer"},
            "upload_count" => %{"type" => "integer"},
            "download_bytes" => %{"type" => "integer"},
            "upload_bytes" => %{"type" => "integer"}
          },
          "required" => ["download_count", "upload_count", "download_bytes", "upload_bytes"],
          "additionalProperties" => false
        }
      },
      "required" => ["outputs", "pagination_metadata", "totals"],
      "additionalProperties" => false
    }

  alias Tuist.Builds
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List content-addressable storage outputs for a specific Xcode build run, along with the aggregate transfer totals for the whole run. The totals cover every output regardless of the operation and type filters, so a single call yields both the download and upload counts and bytes. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  def execute(conn, args) do
    build_run_id = MCPTool.resource_id(Map.get(args, "build_run_id"))

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

      totals = Builds.cas_output_metrics(build_run_id)

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
         pagination_metadata: MCPTool.pagination_metadata(meta),
         totals: %{
           download_count: totals.download_count,
           upload_count: totals.upload_count,
           download_bytes: totals.download_bytes,
           upload_bytes: totals.upload_bytes
         }
       }}
    end
  end
end
