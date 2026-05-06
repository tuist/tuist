defmodule Tuist.MCP.Components.Tools.ListXcodeBuilds do
  @moduledoc """
  List Xcode build runs for a project. Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_builds",
    title: "List Xcode Builds",
    authorize: [action: :read, category: :build],
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
        "status" => %{
          "type" => "string",
          "description" => "Filter by status: success or failure."
        },
        "scheme" => %{
          "type" => "string",
          "description" => "Filter by scheme name."
        },
        "configuration" => %{
          "type" => "string",
          "description" => "Filter by configuration name."
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

  alias Tuist.Builds
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List Xcode build runs for a project. Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {builds, meta} =
      Builds.list_build_runs(%{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    {:ok,
     %{
       builds:
         Enum.map(builds, fn build ->
           %{
             id: build.id,
             duration: build.duration,
             status: to_string(build.status),
             category: if(build.category != "", do: build.category),
             scheme: build.scheme,
             configuration: build.configuration,
             is_ci: build.is_ci,
             git_branch: build.git_branch,
             git_commit_sha: build.git_commit_sha,
             cacheable_tasks_count: build.cacheable_tasks_count,
             cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
             cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
             inserted_at: Formatter.iso8601(build.inserted_at, naive: :utc)
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    Enum.reduce([:git_branch, :status, :scheme, :configuration], base, fn field, filters ->
      case Map.get(args, to_string(field)) do
        nil -> filters
        value -> filters ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
