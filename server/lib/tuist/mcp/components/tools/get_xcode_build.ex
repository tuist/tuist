defmodule Tuist.MCP.Components.Tools.GetXcodeBuild do
  @moduledoc """
  Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :build

  schema do
    field :build_run_id, :string,
      required: true,
      description: "The ID of the build run."
  end

  @impl true
  def execute(%{build_run_id: build_run_id}, frame) do
    with {:ok, build} <-
           ToolSupport.load_resource(
             get_build(build_run_id),
             "Build not found: #{build_run_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             build.project_id,
             @authorization_action,
             @authorization_category
           ) do
      data = %{
        id: build.id,
        duration: build.duration,
        status: to_string(build.status),
        category: if(build.category != "", do: build.category),
        scheme: build.scheme,
        configuration: build.configuration,
        xcode_version: build.xcode_version,
        macos_version: build.macos_version,
        model_identifier: build.model_identifier,
        is_ci: build.is_ci,
        git_branch: build.git_branch,
        git_commit_sha: build.git_commit_sha,
        git_ref: build.git_ref,
        cacheable_tasks_count: build.cacheable_tasks_count,
        cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
        cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
        inserted_at: Formatter.iso8601(build.inserted_at, naive: :utc)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_build(id) do
    case Builds.get_build(id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end
end
