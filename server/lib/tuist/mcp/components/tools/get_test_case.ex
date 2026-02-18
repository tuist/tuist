defmodule Tuist.MCP.Components.Tools.GetTestCase do
  @moduledoc """
  Get detailed information about a test case including reliability and flakiness metrics.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.MCP.Error
  alias Hermes.Server.Response
  alias Tuist.MCP.Authorization
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  schema do
    field :test_case_id, :string, required: true, description: "The UUID of the test case."
  end

  @impl true
  def execute(%{test_case_id: test_case_id}, frame) do
    subject = Authorization.authenticated_subject(frame.assigns)

    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         project when not is_nil(project) <- Projects.get_project_by_id(test_case.project_id),
         true <- Authorization.authorize(subject, :read, project, :test) do
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
    else
      {:error, :not_found} ->
        invalid_params("Test case not found: #{test_case_id}", frame)

      nil ->
        invalid_params("Project not found.", frame)

      false ->
        invalid_params("You do not have access to this resource.", frame)
    end
  end

  defp invalid_params(message, frame) do
    {:error, Error.protocol(:invalid_params, %{message: message}), frame}
  end
end
