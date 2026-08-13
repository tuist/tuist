defmodule Tuist.MCP.Components.Tools.GetTestRunArtifacts do
  @moduledoc """
  Get temporary download URLs for a test run's stored artifacts: the result
  bundle (`.xcresult`) and the session archive.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_artifacts",
    title: "Get Test Run Artifacts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test run."
        }
      },
      "required" => ["test_run_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string"},
        "result_bundle" => Tuist.MCP.ArtifactDownload.schema(true),
        "session" => Tuist.MCP.ArtifactDownload.schema(true)
      },
      "required" => ["test_run_id", "result_bundle", "session"],
      "additionalProperties" => false
    }

  alias Tuist.CommandEvents
  alias Tuist.MCP.ArtifactDownload
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @impl EMCP.Tool
  def description,
    do:
      "Get temporary download URLs (valid for 1 hour) for a test run's stored artifacts: the result bundle (.xcresult, " <>
        "which holds the failure details, attachments and timings Xcode recorded) and the session archive. " <>
        "Either is null when it was never uploaded or has since been pruned. The URLs are presigned — download them " <>
        "with curl or an equivalent."

  def execute(conn, %{"test_run_id" => test_run_id}) when is_binary(test_run_id) do
    with {:ok, project} <- authorized_project(conn, test_run_id),
         {:ok, result_bundle} <-
           ArtifactDownload.presign_optional(
             CommandEvents.get_result_bundle_key(test_run_id, project),
             project.account
           ),
         {:ok, session} <-
           ArtifactDownload.presign_optional(
             CommandEvents.get_session_key(test_run_id, project),
             project.account
           ) do
      {:ok, %{test_run_id: test_run_id, result_bundle: result_bundle, session: session}}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "Could not reach artifact storage."}
    end
  end

  def execute(_conn, _args), do: {:error, "test_run_id is required and must be a string."}

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

  # A remote-processed run (`tuist inspect test`) has a row in `test_runs`; an
  # older `tuist test` run has only its command event. Both store the artifact
  # under `<account>/<project>/runs/<id>/`, so the id is all that differs, and
  # the same key builders serve both once the project is known. Resolving the
  # record here rather than authorizing twice keeps one authorization decision
  # and one "not found" message for the caller.
  defp lookup(test_run_id) do
    case Tests.get_test(test_run_id) do
      {:ok, test} -> {:ok, test}
      {:error, :not_found} -> CommandEvents.get_command_event_by_id(test_run_id)
    end
  end
end
