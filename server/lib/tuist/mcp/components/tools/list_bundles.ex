defmodule Tuist.MCP.Components.Tools.ListBundles do
  @moduledoc """
  List bundles (app binaries) for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Bundles
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :bundle

  @impl EMCP.Tool
  def name, do: "list_bundles"

  @impl EMCP.Tool
  def description,
    do:
      "List bundles (app binaries) for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}."

  @impl EMCP.Tool
  def input_schema do
    %{
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
    }
  end

  @impl EMCP.Tool
  def call(conn, args) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             args,
             conn.assigns,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)
      filters = build_filters(project.id, args)

      {bundles, meta} =
        Bundles.list_bundles(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
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
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    case Map.get(args, "git_branch") do
      nil -> base
      value -> base ++ [%{field: :git_branch, op: :==, value: value}]
    end
  end
end
