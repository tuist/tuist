defmodule Tuist.MCP.Components.Tools.ListXcodeBuilds do
  @moduledoc """
  List Xcode build runs for a project. Only available for projects with build_system=xcode. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :build

  schema do
    field :account_handle, :string,
      required: true,
      description: "The account handle (organization or user)."

    field :project_handle, :string,
      required: true,
      description: "The project handle."

    field :git_branch, :string, description: "Filter by git branch."
    field :status, :string, description: "Filter by status: success or failure."
    field :scheme, :string, description: "Filter by scheme name."
    field :configuration, :string, description: "Filter by configuration name."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(arguments, frame) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             arguments,
             frame,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)
      filters = build_filters(project.id, arguments)

      {builds, meta} =
        Builds.list_build_runs(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
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
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp build_filters(project_id, arguments) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    Enum.reduce([:git_branch, :status, :scheme, :configuration], base, fn field, filters ->
      case Map.get(arguments, field) do
        nil -> filters
        value -> filters ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
