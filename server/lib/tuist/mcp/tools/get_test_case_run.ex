defmodule Tuist.MCP.Tools.GetTestCaseRun do
  @moduledoc false

  alias Tuist.MCP.Authorization
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
         :ok <- Authorization.authorize_project_id(run.project_id, subject) do
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
        ran_at: format_ran_at(run.ran_at),
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

      {:ok, %{content: [%{type: "text", text: Jason.encode!(data)}]}}
    else
      {:error, :not_found} -> {:error, -32_602, "Test case run not found: #{test_case_run_id}"}
      {:error, code, message} -> {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    {:error, -32_602, "Missing required parameter: test_case_run_id."}
  end

  defp format_ran_at(nil), do: nil

  defp format_ran_at(%NaiveDateTime{} = ran_at) do
    ran_at |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp format_ran_at(%DateTime{} = ran_at), do: DateTime.to_iso8601(ran_at)
end
