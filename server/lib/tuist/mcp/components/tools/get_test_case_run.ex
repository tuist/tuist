defmodule Tuist.MCP.Components.Tools.GetTestCaseRun do
  @moduledoc """
  Get detailed information about a specific test case run including failures and repetitions. Use list_test_case_run_attachments to inspect attachments.
  """

  use Tuist.MCP.Tool,
    name: "get_test_case_run",
    title: "Get Test Case Run",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_case_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test case run."
        }
      },
      "required" => ["test_case_run_id"]
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific test case run including failures and repetitions. Use list_test_case_run_attachments to inspect attachments."

  def execute(conn, %{"test_case_run_id" => test_case_run_id}) do
    with {:ok, run, _project} <-
           MCPTool.load_and_authorize(
             Tests.get_test_case_run_by_id(test_case_run_id,
               preload: [:failures, :repetitions]
             ),
             conn.assigns,
             :read,
             :test,
             "Test case run not found: #{test_case_run_id}"
           ) do
      {:ok,
       %{
         id: run.id,
         test_case_id: run.test_case_id,
         test_run_id: run.test_run_id,
         name: run.name,
         module_name: run.module_name,
         suite_name: run.suite_name,
         status: to_string(run.status),
         duration: run.duration,
         is_ci: run.is_ci,
         is_flaky: run.is_flaky,
         is_new: run.is_new,
         scheme: run.scheme,
         git_branch: run.git_branch,
         git_commit_sha: run.git_commit_sha,
         ran_at: Formatter.iso8601(run.ran_at, naive: :utc),
         failures:
           Enum.map(run.failures, fn failure ->
             %{
               message: failure.message,
               path: failure.path,
               line_number: failure.line_number,
               issue_type: failure.issue_type
             }
           end),
         repetitions:
           Enum.map(run.repetitions, fn repetition ->
             %{
               repetition_number: repetition.repetition_number,
               status: to_string(repetition.status),
               duration: repetition.duration
             }
           end)
       }}
    end
  end
end
