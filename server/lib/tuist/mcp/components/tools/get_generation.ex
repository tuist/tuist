defmodule Tuist.MCP.Components.Tools.GetGeneration do
  @moduledoc """
  Get detailed information about a specific generation run. The generation_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_generation",
    title: "Get Project Generation",
    schema: %{
      "type" => "object",
      "properties" => %{
        "generation_id" => %{
          "type" => "string",
          "description" => "The ID of the generation."
        }
      },
      "required" => ["generation_id"]
    }

  alias Tuist.CommandEvents
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific generation run. The generation_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/runs/{id}."

  def execute(conn, %{"generation_id" => generation_id}) do
    with {:ok, event, _project} <-
           MCPTool.load_and_authorize(
             get_generation(generation_id),
             conn.assigns,
             :read,
             :run,
             "Generation not found: #{generation_id}"
           ) do
      {:ok,
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
       }}
    end
  end

  defp get_generation(id) do
    case CommandEvents.get_command_event_by_id(id) do
      {:ok, event} when event.name == "generate" -> {:ok, event}
      {:ok, _event} -> {:error, :not_found}
      error -> error
    end
  end

  defp status_to_string(0), do: "success"
  defp status_to_string(1), do: "failure"
  defp status_to_string(nil), do: "success"
  defp status_to_string(status) when is_atom(status), do: Atom.to_string(status)
  defp status_to_string(status), do: to_string(status)
end
