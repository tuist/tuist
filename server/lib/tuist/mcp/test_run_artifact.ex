defmodule Tuist.MCP.TestRunArtifact do
  @moduledoc """
  Shared resolution for the artifacts a test run stores.

  A remote-processed run (`tuist inspect test`) has a row in `test_runs`; an
  older `tuist test` run has only its command event. Both store under
  `<account>/<project>/runs/<id>/`, so the id is the only thing that differs and
  the same key builders serve both once the project is known. Resolving the
  record before authorizing keeps one authorization decision and one "not found"
  message per call, whichever generation the id belongs to.
  """

  alias Tuist.CommandEvents
  alias Tuist.MCP.ArtifactDownload
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @doc """
  Presigns one of a test run's artifacts, after checking the caller may read the
  run. Returns `{:ok, artifact | nil}` — `nil` when the object was never stored —
  or `{:error, message}`.
  """
  def presign(conn, test_run_id, artifact) when artifact in [:result_bundle, :session] do
    with {:ok, project} <- authorized_project(conn, test_run_id),
         {:ok, presigned} <-
           ArtifactDownload.presign_optional(object_key(artifact, test_run_id, project), project.account) do
      {:ok, presigned}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "Could not reach artifact storage."}
    end
  end

  defp object_key(:result_bundle, test_run_id, project), do: CommandEvents.get_result_bundle_key(test_run_id, project)
  defp object_key(:session, test_run_id, project), do: CommandEvents.get_session_key(test_run_id, project)

  defp authorized_project(conn, test_run_id) do
    with {:ok, _run, project} <-
           MCPTool.load_and_authorize(
             lookup(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      {:ok, project}
    end
  end

  defp lookup(test_run_id) do
    case Tests.get_test(test_run_id) do
      {:ok, test} -> {:ok, test}
      {:error, :not_found} -> CommandEvents.get_command_event_by_id(test_run_id)
    end
  end
end
