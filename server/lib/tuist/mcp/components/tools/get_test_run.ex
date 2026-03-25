defmodule Tuist.MCP.Components.Tools.GetTestRun do
  @moduledoc """
  Get detailed metrics for a specific test run.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test run."
        }
      },
      "required" => ["test_run_id"]
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  @impl EMCP.Tool
  def description, do: "Get detailed metrics for a specific test run."

  def execute(conn, %{"test_run_id" => test_run_id}) do
    with {:ok, run, _project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      metrics = Analytics.get_test_run_metrics(run.id)
      selective_testing = Analytics.get_test_run_selective_testing_metrics(run.id)

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
         xcode_selective_testing_targets: selective_testing.xcode_selective_testing_targets,
         selective_testing_local_hits: selective_testing.selective_testing_local_hits,
         selective_testing_remote_hits: selective_testing.selective_testing_remote_hits
       }}
    end
  end
end
