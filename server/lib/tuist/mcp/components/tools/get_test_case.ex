defmodule Tuist.MCP.Components.Tools.GetTestCase do
  @moduledoc """
  Get detailed information about a test case including reliability and flakiness metrics.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  @authorization_action :read
  @authorization_category :test

  schema do
    field :test_case_id, :string, description: "The UUID of the test case. Required when not using identifier lookup."

    field :account_handle, :string,
      description: "The account handle (organization or user). Required when looking up by identifier."

    field :project_handle, :string, description: "The project handle. Required when looking up by identifier."

    field :identifier, :string,
      description:
        "Test case identifier in Module/Suite/TestCase or Module/TestCase format. " <>
          "Required when not using test_case_id. Must be combined with account_handle and project_handle."
  end

  @impl true
  def execute(%{test_case_id: test_case_id}, frame) when is_binary(test_case_id) do
    with {:ok, test_case} <-
           ToolSupport.load_resource(
             Tests.get_test_case_by_id(test_case_id),
             "Test case not found: #{test_case_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             test_case.project_id,
             @authorization_action,
             @authorization_category
           ) do
      reply_with_test_case(test_case, frame)
    end
  end

  def execute(%{account_handle: account_handle, project_handle: project_handle, identifier: identifier}, frame)
      when is_binary(account_handle) and is_binary(project_handle) and is_binary(identifier) do
    with {:ok, {module_name, suite_name, name}} <- parse_identifier(identifier, frame),
         {:ok, project} <-
           ToolSupport.load_and_authorize_project_by_handle(
             account_handle,
             project_handle,
             frame,
             @authorization_action,
             @authorization_category,
             "You do not have access to project: #{account_handle}/#{project_handle}"
           ),
         {:ok, test_case} <- find_test_case_by_name(project.id, module_name, suite_name, name, frame) do
      reply_with_test_case(test_case, frame)
    end
  end

  def execute(_arguments, frame) do
    ToolSupport.invalid_params(
      "Provide either test_case_id or identifier with account_handle and project_handle.",
      frame
    )
  end

  defp parse_identifier(identifier, frame) do
    case String.split(identifier, "/") do
      [module_name, suite_name, name] -> {:ok, {module_name, suite_name, name}}
      [module_name, name] -> {:ok, {module_name, nil, name}}
      _ -> ToolSupport.invalid_params("Invalid identifier format. Use Module/Suite/TestCase or Module/TestCase.", frame)
    end
  end

  defp find_test_case_by_name(project_id, module_name, suite_name, name, frame) do
    filters =
      [
        %{field: :module_name, op: :==, value: module_name},
        %{field: :name, op: :==, value: name}
      ] ++ if(suite_name, do: [%{field: :suite_name, op: :==, value: suite_name}], else: [])

    {test_cases, _meta} =
      Tests.list_test_cases(project_id, %{
        filters: filters,
        page: 1,
        page_size: 1
      })

    case test_cases do
      [test_case | _] -> {:ok, test_case}
      [] -> ToolSupport.invalid_params("Test case not found: #{module_name}/#{suite_name || name}", frame)
    end
  end

  defp reply_with_test_case(test_case, frame) do
    analytics = Analytics.test_case_analytics_by_id(test_case.id)
    reliability_rate = Analytics.test_case_reliability_by_id(test_case.id, "main")
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
