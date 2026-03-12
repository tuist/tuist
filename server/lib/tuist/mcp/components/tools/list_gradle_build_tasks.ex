defmodule Tuist.MCP.Components.Tools.ListGradleBuildTasks do
  @moduledoc """
  List tasks for a specific Gradle build run. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/gradle/builds/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_gradle_build_tasks",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the Gradle build run."
        },
        "outcome" => %{
          "type" => "string",
          "description" =>
            "Filter by task outcome: local_hit, remote_hit, up_to_date, executed, failed, skipped, or no_source."
        },
        "cacheable" => %{
          "type" => "boolean",
          "description" => "Filter by whether the task is cacheable."
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
    }

  alias Tuist.Gradle
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List tasks for a specific Gradle build run. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/gradle/builds/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, _build, _project} <-
           MCPTool.load_and_authorize(
             get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Gradle build not found: #{build_run_id}"
           ) do
      filters = build_filters(build_run_id, args)
      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      {tasks, meta} =
        Gradle.list_tasks(build_run_id, %{
          filters: filters,
          order_by: [:duration_ms],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      {:ok,
       %{
         tasks:
           Enum.map(tasks, fn task ->
             %{
               id: task.id,
               task_path: task.task_path,
               task_type: task.task_type,
               outcome: task.outcome,
               cacheable: task.cacheable,
               duration_ms: task.duration_ms,
               cache_key: if(task.cache_key != "", do: task.cache_key),
               cache_artifact_size: task.cache_artifact_size,
               started_at: Formatter.iso8601(task.started_at)
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end

  defp build_filters(build_run_id, args) do
    base = [%{field: :gradle_build_id, op: :==, value: build_run_id}]

    base
    |> maybe_add_filter(args, "outcome", :outcome)
    |> maybe_add_filter(args, "cacheable", :cacheable)
  end

  defp maybe_add_filter(filters, args, key, field) do
    case Map.get(args, key) do
      nil -> filters
      value -> filters ++ [%{field: field, op: :==, value: value}]
    end
  end

  defp get_build(id) do
    case Gradle.get_build(id) do
      {:ok, build} -> {:ok, build}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
end
