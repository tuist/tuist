defmodule Tuist.MCP.Components.Tools.ListTestRuns do
  @moduledoc """
  List test runs for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_test_runs",
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
        "git_branch" => %{
          "type" => "string",
          "description" => "Filter by git branch."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter by status: success, failure, or skipped."
        },
        "scheme" => %{
          "type" => "string",
          "description" => "Filter by scheme name."
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
      "List test runs for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(project.id, args)

    {runs, meta} =
      Tests.list_test_runs(%{
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    metrics_map =
      project.id
      |> Tests.Analytics.test_runs_metrics(runs)
      |> Map.new(&{&1.test_run_id, &1})

    {:ok,
     %{
       test_runs:
         Enum.map(runs, fn run ->
           metrics = Map.get(metrics_map, run.id, %{})

           %{
             id: run.id,
             duration: run.duration,
             status: to_string(run.status),
             is_ci: run.is_ci,
             is_flaky: run.is_flaky,
             scheme: run.scheme,
             git_branch: run.git_branch,
             git_commit_sha: run.git_commit_sha,
             ran_at: Formatter.iso8601(run.ran_at, naive: :utc),
             total_test_count: Map.get(metrics, :total_tests, 0),
             ran_tests: Map.get(metrics, :ran_tests, 0),
             skipped_tests: Map.get(metrics, :skipped_tests, 0),
             xcode_selective_testing_targets: Map.get(metrics, :xcode_selective_testing_targets, 0),
             selective_testing_local_hits: Map.get(metrics, :selective_testing_local_hits, 0),
             selective_testing_remote_hits: Map.get(metrics, :selective_testing_remote_hits, 0)
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(project_id, args) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    Enum.reduce(["git_branch", "status", "scheme"], base, fn key, filters ->
      case Map.get(args, key) do
        nil -> filters
        value -> filters ++ [%{field: String.to_existing_atom(key), op: :==, value: value}]
      end
    end)
  end
end
