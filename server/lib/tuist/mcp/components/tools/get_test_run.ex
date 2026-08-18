defmodule Tuist.MCP.Components.Tools.GetTestRun do
  @moduledoc """
  Get detailed metrics for a specific test run.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run",
    title: "Get Test Run",
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
        "id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "duration" => %{"type" => "integer"},
        "is_ci" => %{"type" => "boolean"},
        "is_flaky" => %{"type" => "boolean"},
        "scheme" => %{"type" => "string"},
        "git_branch" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "ran_at" => %{"type" => "string"},
        "total_test_count" => %{"type" => "integer"},
        "failed_test_count" => %{"type" => "integer"},
        "flaky_test_count" => %{"type" => "integer"},
        "avg_test_duration" => %{"type" => "number"},
        "result_bundle_url" => %{"type" => "string"},
        "session_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "status",
        "duration",
        "is_ci",
        "is_flaky",
        "scheme",
        "git_branch",
        "git_commit_sha",
        "ran_at",
        "total_test_count",
        "failed_test_count",
        "flaky_test_count",
        "avg_test_duration",
        "result_bundle_url",
        "session_url"
      ],
      "additionalProperties" => false
    }

  alias Tuist.CommandEvents
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  # Shorter than the hour `list_test_case_run_attachments` hands out: these URLs
  # ride along with metadata the caller may only have wanted the numbers from,
  # so they land in transcripts unasked-for and should stop working sooner.
  @artifact_url_expires_in 900

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed metrics for a specific test run, including temporary download URLs (valid for 15 minutes) for its " <>
        "result bundle — the .xcresult holding the failure details, attachments and timings Xcode recorded — and " <>
        "its session archive. Those URLs are presigned and not checked for existence: a run whose artifacts were " <>
        "never uploaded, or have since been pruned, answers 404 on download."

  def execute(conn, %{"test_run_id" => test_run_id}) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      metrics = Analytics.get_test_run_metrics(run.id)

      {:ok,
       %{
         id: run.id,
         status: to_string(run.status),
         duration: run.duration,
         is_ci: run.is_ci,
         is_flaky: run.is_flaky,
         scheme: run.scheme,
         git_branch: run.git_branch,
         git_commit_sha: run.git_commit_sha,
         ran_at: Formatter.iso8601(run.ran_at, naive: :utc),
         total_test_count: metrics.total_count,
         failed_test_count: metrics.failed_count,
         flaky_test_count: metrics.flaky_count,
         avg_test_duration: metrics.avg_duration,
         result_bundle_url: artifact_url(CommandEvents.get_result_bundle_key(run.id, project), project.account),
         session_url: artifact_url(CommandEvents.get_session_key(run.id, project), project.account)
       }}
    end
  end

  # Signing is a local HMAC, so carrying the URLs costs the caller nothing over
  # the metrics they already asked for. Checking whether the object is really
  # there would cost a storage round trip on every call, which is why the
  # description says a missing artifact surfaces as a 404 on download instead.
  defp artifact_url(object_key, account) do
    Storage.generate_download_url(object_key, account,
      expires_in: @artifact_url_expires_in,
      content_disposition: ~s(attachment; filename="#{Path.basename(object_key)}")
    )
  end
end
