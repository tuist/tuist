defmodule Tuist.MCP.Components.Tools.ListTestCaseRuns do
  @moduledoc """
  List test case runs, optionally filtered by test case or test run. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  @behaviour EMCP.Tool

  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def name, do: "list_test_case_runs"

  @impl EMCP.Tool
  def description,
    do:
      "List test case runs, optionally filtered by test case or test run. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "test_case_id" => %{
          "type" => "string",
          "description" => "Filter by test case ID."
        },
        "test_run_id" => %{
          "type" => "string",
          "description" => "Filter by test run ID."
        },
        "flaky" => %{
          "type" => "boolean",
          "description" => "When true, returns only flaky runs."
        },
        "page" => %{
          "type" => "integer",
          "description" => "Page number (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["account_handle", "project_handle"]
    }
  end

  @impl EMCP.Tool
  def call(conn, args) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             args,
             conn.assigns,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)
      filters = build_filters(project.id, args)

      {runs, meta} =
        Tests.list_test_case_runs(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        test_case_runs:
          Enum.map(runs, fn run ->
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
              git_branch: run.git_branch,
              git_commit_sha: run.git_commit_sha,
              ran_at: Formatter.iso8601(run.ran_at, naive: :utc)
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    base =
      case Map.get(args, "test_case_id") do
        nil -> base
        value -> base ++ [%{field: :test_case_id, op: :==, value: value}]
      end

    base =
      case Map.get(args, "test_run_id") do
        nil -> base
        value -> base ++ [%{field: :test_run_id, op: :==, value: value}]
      end

    if Map.get(args, "flaky") do
      base ++ [%{field: :is_flaky, op: :==, value: true}]
    else
      base
    end
  end
end
