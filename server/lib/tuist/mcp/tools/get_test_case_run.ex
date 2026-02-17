defmodule Tuist.MCP.Tools.GetTestCaseRun do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Content
  alias Tuist.MCP.Errors
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  def name, do: "get_test_case_run"

  def definition do
    %{
      name: name(),
      description: "Get detailed information about a specific test case run including failures and repetitions.",
      inputSchema: %{
        type: "object",
        properties: %{
          test_case_run_id: %{type: "string", description: "The UUID of the test case run."}
        },
        required: ["test_case_run_id"]
      }
    }
  end

  def call(%{"test_case_run_id" => test_case_run_id}, subject) do
    with {:ok, run} <- Tests.get_test_case_run_by_id(test_case_run_id, preload: [:failures, :repetitions]),
         :ok <- Authorization.authorize_project_id(:test_read, run.project_id, subject) do
      data = %{
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
          Enum.map(run.failures, fn f ->
            %{
              message: f.message,
              path: f.path,
              line_number: f.line_number,
              issue_type: f.issue_type
            }
          end),
        repetitions:
          Enum.map(run.repetitions, fn r ->
            %{
              repetition_number: r.repetition_number,
              status: to_string(r.status),
              duration: r.duration
            }
          end)
      }

      Content.ok_json(data)
    else
      {:error, :not_found} -> Errors.invalid_params("Test case run not found: #{test_case_run_id}")
      {:error, code, message} -> {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    Errors.invalid_params("Missing required parameter: test_case_run_id.")
  end
end
