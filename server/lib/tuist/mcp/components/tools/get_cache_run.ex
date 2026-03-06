defmodule Tuist.MCP.Components.Tools.GetCacheRun do
  @moduledoc """
  Get detailed information about a specific cache run. The cache_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/runs/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.CommandEvents
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :run

  schema do
    field :cache_run_id, :string,
      required: true,
      description: "The ID of the cache run."
  end

  @impl true
  def execute(%{cache_run_id: cache_run_id}, frame) do
    with {:ok, event} <-
           ToolSupport.load_resource(
             get_cache_run(cache_run_id),
             "Cache run not found: #{cache_run_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             event.project_id,
             @authorization_action,
             @authorization_category
           ) do
      data = %{
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

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_cache_run(id) do
    case CommandEvents.get_command_event_by_id(id) do
      {:ok, event} when event.name == "cache" -> {:ok, event}
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
