defmodule Tuist.MCP.Components.Tools.GetTestCase do
  @moduledoc """
  Get detailed information about a test case including reliability and flakiness metrics.
  """

  use Hermes.Server.Component, type: :tool
  use Tuist.MCP.Components.ToolPlug, action: :read, category: :test

  alias Hermes.Server.Response
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  schema do
    field :test_case_id, :string, required: true, description: "The UUID of the test case."
  end

  @impl true
  def execute(%{test_case_id: test_case_id}, frame) do
    with {:ok, test_case} <-
           load_resource(Tests.get_test_case_by_id(test_case_id), "Test case not found: #{test_case_id}", frame),
         {:ok, _project} <- authorize_project_by_id(frame, test_case.project_id) do
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

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end
end
