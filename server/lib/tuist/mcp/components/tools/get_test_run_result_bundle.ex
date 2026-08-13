defmodule Tuist.MCP.Components.Tools.GetTestRunResultBundle do
  @moduledoc """
  Get a temporary download URL for a test run's result bundle (`.xcresult`).
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_result_bundle",
    title: "Get Test Run Result Bundle",
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
        "result_bundle" => Tuist.MCP.ArtifactDownload.schema(true)
      },
      "required" => ["test_run_id", "result_bundle"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.TestRunArtifact

  @impl EMCP.Tool
  def description,
    do:
      "Get a temporary download URL (valid for 1 hour) for a test run's result bundle — the .xcresult holding the " <>
        "failure details, attachments and timings Xcode recorded. Null when it was never uploaded or has since " <>
        "been pruned. The URL is presigned — download it with curl or an equivalent."

  def execute(conn, %{"test_run_id" => test_run_id}) when is_binary(test_run_id) do
    with {:ok, result_bundle} <- TestRunArtifact.presign(conn, test_run_id, :result_bundle) do
      {:ok, %{test_run_id: test_run_id, result_bundle: result_bundle}}
    end
  end

  def execute(_conn, _args), do: {:error, "test_run_id is required and must be a string."}
end
