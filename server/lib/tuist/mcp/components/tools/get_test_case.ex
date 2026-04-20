defmodule Tuist.MCP.Components.Tools.GetTestCase do
  @moduledoc """
  Get detailed information about a test case including reliability and flakiness metrics. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "get_test_case",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_case_id" => %{
          "type" => "string",
          "description" => "The ID of the test case. Required when not using identifier lookup."
        },
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user). Required for identifier lookup."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle. Required for identifier lookup."
        },
        "identifier" => %{
          "type" => "string",
          "description" =>
            "Test case identifier in Module/Suite/TestCase or Module/TestCase format. " <>
              "Required when not using test_case_id. Must be combined with account_handle and project_handle."
        }
      }
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a test case including reliability and flakiness metrics. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  @impl EMCP.Tool
  def call(conn, %{"test_case_id" => test_case_id}) when is_binary(test_case_id) do
    case MCPTool.load_and_authorize(
           Tests.get_test_case_by_id(test_case_id),
           conn.assigns,
           @authorization_action,
           @authorization_category,
           "Test case not found: #{test_case_id}"
         ) do
      {:ok, test_case, _project} -> reply_with_test_case(test_case)
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(conn, %{"identifier" => identifier} = args) when is_binary(identifier) do
    with {:ok, {module_name, suite_name, name}} <- parse_identifier(identifier),
         {:ok, project} <-
           MCPTool.resolve_and_authorize_project(
             args,
             conn.assigns,
             @authorization_action,
             @authorization_category
           ),
         {:ok, test_case} <- find_test_case_by_name(project.id, module_name, suite_name, name) do
      reply_with_test_case(test_case)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _args) do
    EMCP.Tool.error("Provide either test_case_id, or identifier with account_handle and project_handle.")
  end

  defp parse_identifier(identifier) do
    case String.split(identifier, "/") do
      [module_name, suite_name, name] -> {:ok, {module_name, suite_name, name}}
      [module_name, name] -> {:ok, {module_name, nil, name}}
      _ -> {:error, "Invalid identifier format. Use Module/Suite/TestCase or Module/TestCase."}
    end
  end

  defp find_test_case_by_name(project_id, module_name, suite_name, name) do
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
      [] -> {:error, "Test case not found: #{module_name}/#{suite_name || name}"}
    end
  end

  defp reply_with_test_case(test_case) do
    analytics = Analytics.test_case_analytics_by_id(test_case.id)
    reliability_rate = Analytics.test_case_reliability_by_id(test_case.id, "main")
    flakiness_rate = Analytics.get_test_case_flakiness_rate(test_case)

    data = %{
      id: test_case.id,
      name: test_case.name,
      module_name: test_case.module_name,
      suite_name: test_case.suite_name,
      is_flaky: test_case.is_flaky,
      state: test_case.state || "enabled",
      last_status: to_string(test_case.last_status),
      last_duration: test_case.last_duration,
      avg_duration: test_case.avg_duration,
      reliability_rate: reliability_rate,
      flakiness_rate: flakiness_rate,
      total_runs: analytics.total_count,
      failed_runs: analytics.failed_count
    }

    MCPTool.json_response(data)
  end
end
