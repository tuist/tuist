defmodule Tuist.MCP.Components.Tools.GetGradleBuild do
  @moduledoc """
  Get detailed information about a specific Gradle build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/gradle/builds/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_gradle_build",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the Gradle build run."
        }
      },
      "required" => ["build_run_id"]
    }

  alias Tuist.Gradle
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific Gradle build run. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/gradle/builds/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(
             get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Gradle build not found: #{build_run_id}"
           ) do
      {:ok,
       %{
         id: build.id,
         duration_ms: build.duration_ms,
         status: to_string(build.status),
         gradle_version: build.gradle_version,
         java_version: build.java_version,
         is_ci: build.is_ci,
         git_branch: build.git_branch,
         git_commit_sha: build.git_commit_sha,
         git_ref: build.git_ref,
         root_project_name: build.root_project_name,
         requested_tasks: build.requested_tasks,
         tasks_local_hit_count: build.tasks_local_hit_count,
         tasks_remote_hit_count: build.tasks_remote_hit_count,
         tasks_up_to_date_count: build.tasks_up_to_date_count,
         tasks_executed_count: build.tasks_executed_count,
         tasks_failed_count: build.tasks_failed_count,
         tasks_skipped_count: build.tasks_skipped_count,
         tasks_no_source_count: build.tasks_no_source_count,
         cacheable_tasks_count: build.cacheable_tasks_count,
         cache_hit_rate: Gradle.cache_hit_rate(build),
         inserted_at: Formatter.iso8601(build.inserted_at, naive: :utc)
       }}
    end
  end

  defp get_build(id) do
    case Gradle.get_build(id) do
      {:ok, build} -> {:ok, build}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
end
