defmodule Tuist.MCP.Components.Tools.GetXcodeBuild do
  @moduledoc """
  Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_xcode_build",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        }
      },
      "required" => ["build_run_id"]
    }

  alias Tuist.Builds
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(
             Builds.get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Build not found: #{build_run_id}"
           ) do
      {:ok,
       %{
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
       }}
    end
  end
end
