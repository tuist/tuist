defmodule Tuist.MCP.Components.Tools.GetTestRunSession do
  @moduledoc """
  Get a temporary download URL for a test run's session archive.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_session",
    title: "Get Test Run Session",
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
        "session" => Tuist.MCP.ArtifactDownload.schema(true)
      },
      "required" => ["test_run_id", "session"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.TestRunArtifact

  @impl EMCP.Tool
  def description,
    do:
      "Get a temporary download URL (valid for 1 hour) for a test run's session archive, the recording of the " <>
        "run itself rather than its results. Null when it was never uploaded or has since been pruned. The URL " <>
        "is presigned — download it with curl or an equivalent."

  def execute(conn, %{"test_run_id" => test_run_id}) when is_binary(test_run_id) do
    with {:ok, session} <- TestRunArtifact.presign(conn, test_run_id, :session) do
      {:ok, %{test_run_id: test_run_id, session: session}}
    end
  end

  def execute(_conn, _args), do: {:error, "test_run_id is required and must be a string."}
end
