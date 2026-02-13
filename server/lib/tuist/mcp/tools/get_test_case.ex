defmodule Tuist.MCP.Tools.GetTestCase do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  def name, do: "get_test_case"

  def definition do
    %{
      name: name(),
      description: "Get detailed information about a test case including reliability and flakiness metrics.",
      inputSchema: %{
        type: "object",
        properties: %{
          test_case_id: %{type: "string", description: "The UUID of the test case."}
        },
        required: ["test_case_id"]
      }
    }
  end

  def call(%{"test_case_id" => test_case_id}, subject) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         :ok <- Authorization.authorize_project_id(test_case.project_id, subject) do
      analytics = Analytics.test_case_analytics_by_id(test_case_id)
      reliability_rate = Analytics.test_case_reliability_by_id(test_case_id, "main")
      flakiness_rate = Analytics.get_test_case_flakiness_rate(test_case)

      data = %{
        id: test_case.id,
        name: test_case.name,
        module_name: test_case.module_name,
        suite_name: test_case.suite_name,
        is_flaky: test_case.is_flaky,
        is_quarantined: test_case.is_quarantined,
        last_status: to_string(test_case.last_status),
        last_duration: test_case.last_duration,
        avg_duration: test_case.avg_duration,
        reliability_rate: reliability_rate,
        flakiness_rate: flakiness_rate,
        total_runs: analytics.total_count,
        failed_runs: analytics.failed_count
      }

      {:ok, %{content: [%{type: "text", text: Jason.encode!(data)}]}}
    else
      {:error, :not_found} -> {:error, -32_602, "Test case not found: #{test_case_id}"}
      {:error, code, message} -> {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    {:error, -32_602, "Missing required parameter: test_case_id."}
  end
end
