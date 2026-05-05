defmodule Tuist.MCP.Components.Tools.ListGradleBuilds do
  @moduledoc """
  List Gradle build runs for a project. Only available for projects with build_system=gradle. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_gradle_builds",
    title: "List Gradle Builds",
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
          "description" => "Filter by status: success, failure, or cancelled."
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

  alias Tuist.Gradle
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List Gradle build runs for a project. Only available for projects with build_system=gradle. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {builds, meta} =
      Gradle.list_builds(project.id, %{
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
             duration_ms: build.duration_ms,
             status: to_string(build.status),
             gradle_version: build.gradle_version,
             java_version: build.java_version,
             is_ci: build.is_ci,
             git_branch: build.git_branch,
             git_commit_sha: build.git_commit_sha,
             root_project_name: build.root_project_name,
             requested_tasks: build.requested_tasks,
             tasks_local_hit_count: build.tasks_local_hit_count,
             tasks_remote_hit_count: build.tasks_remote_hit_count,
             tasks_executed_count: build.tasks_executed_count,
             cacheable_tasks_count: build.cacheable_tasks_count,
             cache_hit_rate: Gradle.cache_hit_rate(build),
             inserted_at: Formatter.iso8601(build.inserted_at, naive: :utc)
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    Enum.reduce([:git_branch, :status], base, fn field, filters ->
      case Map.get(args, to_string(field)) do
        nil -> filters
        value -> filters ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
