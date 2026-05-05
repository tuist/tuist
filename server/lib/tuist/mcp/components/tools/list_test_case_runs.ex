defmodule Tuist.MCP.Components.Tools.ListTestCaseRuns do
  @moduledoc """
  List test case runs, optionally filtered by test case or test run. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_test_case_runs",
    title: "List Test Case Runs",
    authorize: [action: :read, category: :test],
    schema: %{
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

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @impl EMCP.Tool
  def description,
    do:
      "List test case runs, optionally filtered by test case or test run. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {runs, meta} =
      Tests.list_test_case_runs(%{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    {:ok,
     %{
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
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
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
