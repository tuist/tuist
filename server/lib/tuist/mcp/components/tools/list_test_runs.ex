defmodule Tuist.MCP.Components.Tools.ListTestRuns do
  @moduledoc """
  List test runs for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  schema do
    field :account_handle, :string,
      required: true,
      description: "The account handle (organization or user)."

    field :project_handle, :string,
      required: true,
      description: "The project handle."

    field :git_branch, :string, description: "Filter by git branch."
    field :status, :string, description: "Filter by status: success, failure, or skipped."
    field :scheme, :string, description: "Filter by scheme name."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(arguments, frame) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             arguments,
             frame,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)
      filters = build_filters(project.id, arguments)

      {runs, meta} =
        Tests.list_test_runs(%{
          filters: filters,
          order_by: [:ran_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      metrics_map =
        runs
        |> Tests.Analytics.test_runs_metrics()
        |> Map.new(&{&1.test_run_id, &1})

      data = %{
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
              skipped_tests: Map.get(metrics, :skipped_tests, 0)
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp build_filters(project_id, arguments) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    Enum.reduce([:git_branch, :status, :scheme], base, fn field, filters ->
      case Map.get(arguments, field) do
        nil -> filters
        value -> filters ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
