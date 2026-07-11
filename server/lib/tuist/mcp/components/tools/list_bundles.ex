defmodule Tuist.MCP.Components.Tools.ListBundles do
  @moduledoc """
  List bundles (app binaries) for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_bundles",
    title: "List App Bundles",
    authorize: [action: :read, category: :bundle],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "git_branch" => %{
          "type" => "string",
          "description" => "Filter by git branch."
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
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "bundles" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "app_bundle_id" => %{"type" => "string"},
              "version" => %{"type" => "string"},
              "type" => %{"type" => "string"},
              "supported_platforms" => %{"type" => "array", "items" => %{"type" => "string"}},
              "install_size" => %{"type" => "integer"},
              "download_size" => %{"type" => ["integer", "null"]},
              "git_branch" => %{"type" => ["string", "null"]},
              "git_commit_sha" => %{"type" => ["string", "null"]},
              "inserted_at" => %{"type" => "string"}
            },
            "required" => [
              "id",
              "name",
              "app_bundle_id",
              "version",
              "type",
              "supported_platforms",
              "install_size",
              "download_size",
              "git_branch",
              "git_commit_sha",
              "inserted_at"
            ],
            "additionalProperties" => false
          }
        },
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["bundles", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bundles
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List bundles (app binaries) for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {bundles, meta} =
      Bundles.list_bundles(%{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    {:ok,
     %{
       bundles:
         Enum.map(bundles, fn bundle ->
           %{
             id: bundle.id,
             name: bundle.name,
             app_bundle_id: bundle.app_bundle_id,
             version: bundle.version,
             type: to_string(bundle.type),
             supported_platforms: bundle.supported_platforms || [],
             install_size: bundle.install_size,
             download_size: bundle.download_size,
             git_branch: bundle.git_branch,
             git_commit_sha: bundle.git_commit_sha,
             inserted_at: Formatter.iso8601(bundle.inserted_at)
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    case Map.get(args, "git_branch") do
      nil -> base
      value -> base ++ [%{field: :git_branch, op: :==, value: value}]
    end
  end
end
