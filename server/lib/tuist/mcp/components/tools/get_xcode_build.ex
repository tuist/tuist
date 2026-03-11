defmodule Tuist.MCP.Components.Tools.GetXcodeBuild do
  @moduledoc """
  Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :build

  @impl EMCP.Tool
  def name, do: "get_xcode_build"

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
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
