defmodule Tuist.MCP.Components.Tools.ListCacheRuns do
  @moduledoc """
  List cache runs for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_cache_runs",
    title: "List Cache Runs",
    authorize: [action: :read, category: :run],
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
        "git_commit_sha" => %{
          "type" => "string",
          "description" => "Filter by git commit SHA."
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

  alias Tuist.CommandEvents
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List cache runs for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {events, meta} =
      CommandEvents.list_command_events(%{
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    {:ok,
     %{
       cache_runs:
         Enum.map(events, fn event ->
           %{
             id: event.id,
             duration: event.duration,
             status: status_to_string(event.status),
             tuist_version: event.tuist_version,
             swift_version: event.swift_version,
             macos_version: event.macos_version,
             is_ci: event.is_ci,
             git_branch: event.git_branch,
             git_commit_sha: event.git_commit_sha,
             git_ref: event.git_ref,
             command_arguments: event.command_arguments,
             cacheable_targets: event.cacheable_targets,
             local_cache_target_hits: event.local_cache_target_hits,
             remote_cache_target_hits: event.remote_cache_target_hits,
             ran_at: Formatter.iso8601(event.created_at, naive: :utc)
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(project_id, args) do
    base = [
      %{field: :project_id, op: :==, value: project_id},
      %{field: :name, op: :==, value: "cache"}
    ]

    Enum.reduce(["git_branch", "git_commit_sha"], base, fn key, filters ->
      case Map.get(args, key) do
        nil -> filters
        value -> filters ++ [%{field: String.to_existing_atom(key), op: :==, value: value}]
      end
    end)
  end

  defp status_to_string(0), do: "success"
  defp status_to_string(1), do: "failure"
  defp status_to_string(nil), do: "success"
  defp status_to_string(status) when is_atom(status), do: Atom.to_string(status)
  defp status_to_string(status), do: to_string(status)
end
