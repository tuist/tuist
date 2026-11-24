defmodule Tuist.MCP.Components.Tools.GetTestRun do
  @moduledoc """
  Get detailed metrics for a specific test run.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run",
    title: "Get Test Run",
    read_only_hint: true,
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
        "actor" => Tuist.MCP.Tool.report_actor_schema(),
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
        "shard_result_bundles" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "shard_index" => %{"type" => "integer"},
              "status" => %{"type" => "string"},
              "reported_at" => %{"type" => "string"},
              "result_bundle_url" => %{"type" => "string"}
            },
            "required" => ["shard_index", "status", "reported_at", "result_bundle_url"],
            "additionalProperties" => false
          }
        },
        "session_url" => %{"type" => ["string", "null"]},
        "coverage" => Tuist.MCP.Tool.json_schema(Tuist.Tests.Coverage.Schemas.run_coverage()),
        "selective_testing" => Tuist.MCP.Tool.json_schema(Tuist.Tests.Selections.Schemas.test_run()),
        "side_quests" => Tuist.MCP.SideQuests.schema()
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
        "shard_result_bundles",
        "session_url",
        "coverage",
        "selective_testing"
      ],
      "additionalProperties" => false
    }

  alias Tuist.CommandEvents
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.SideQuests
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.Coverage.Query, as: CoverageQuery
  alias Tuist.Tests.Selections.Query, as: SelectionQuery

  # Shorter than the hour `list_test_case_run_attachments` hands out: these URLs
  # ride along with metadata the caller may only have wanted the numbers from,
  # so they land in transcripts unasked-for and should stop working sooner.
  @artifact_url_expires_in 900

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed metrics for a specific test run, including its own code coverage, its selective testing " <>
        "summary (strategy, baseline, and requested, selected, skipped and estimated test counts, the ones test selection effectiveness is computed from), and temporary download URLs (valid for 15 minutes) for its " <>
        "result bundle — the .xcresult holding the failure details, attachments and timings Xcode recorded — and " <>
        "the session archive (CLI logs) of the command that ran it, or null when no command is linked to the run. " <>
        "A sharded run's result_bundle_url is its first reporting shard's bundle; shard_result_bundles lists one bundle " <>
        "per shard report, retries included, with that report's status, so a shard that failed without a failing test " <>
        "(such as a test runner that never launched) can be inspected. It is empty for unsharded runs and for shards " <>
        "reported before the server recorded their upload. " <>
        "Those URLs are presigned and not checked for existence: a run whose artifacts were never uploaded, or " <>
        "have since been pruned, answers 404 on download."

  def execute(conn, %{"test_run_id" => test_run_id}) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      metrics = Analytics.get_test_run_metrics(run)

      {:ok,
       SideQuests.put_for_test_run(
         %{
           id: run.id,
           actor: Tuist.ReportActor.actor(run),
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
           shard_result_bundles: shard_result_bundles(run, project),
           session_url: session_url(run, project),
           coverage: CoverageQuery.test_run(run),
           selective_testing: SelectionQuery.test_run(run)
         },
         conn.assigns,
         project,
         run,
         metrics.flaky_count
       )}
    end
  end

  # Each shard uploads its bundle under the ID it reported with, not the merged run's.
  defp shard_result_bundles(run, project) do
    run
    |> Tests.shard_reports()
    |> Enum.map(fn report ->
      %{
        shard_index: report.shard_index,
        status: report.status,
        reported_at: Formatter.iso8601(report.reported_at, naive: :utc),
        result_bundle_url:
          artifact_url(CommandEvents.get_result_bundle_key(report.source_test_run_id, project), project.account)
      }
    end)
  end

  # The CLI uploads the session archive under the ID of the command event that
  # ran the tests, not the test run's, the same lookup the dashboard makes.
  defp session_url(run, project) do
    case CommandEvents.get_command_event_by_test_run_id(run.id, project_id: run.project_id) do
      {:ok, command_event} -> artifact_url(CommandEvents.get_session_key(command_event.id, project), project.account)
      {:error, :not_found} -> nil
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
