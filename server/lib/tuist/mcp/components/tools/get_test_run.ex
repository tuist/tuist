defmodule Tuist.MCP.Components.Tools.GetTestRun do
  @moduledoc """
  Get detailed metrics for a specific test run.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter
  alias Tuist.Tests
  alias Tuist.Tests.Analytics

  @authorization_action :read
  @authorization_category :test

  schema do
    field :test_run_id, :string, required: true, description: "The UUID of the test run."
  end

  @impl true
  def execute(%{test_run_id: test_run_id}, frame) do
    with {:ok, run} <-
           ToolSupport.load_resource(Tests.get_test(test_run_id), "Test run not found: #{test_run_id}", frame),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             run.project_id,
             @authorization_action,
             @authorization_category
           ) do
      metrics = Analytics.get_test_run_metrics(run.id)

      data = %{
        id: run.id,
        status: to_string(run.status),
        duration: run.duration,
        is_ci: run.is_ci,
        is_flaky: run.is_flaky,
        scheme: run.scheme,
        git_branch: run.git_branch,
        git_commit_sha: run.git_commit_sha,
        ran_at: Formatter.iso8601(run.ran_at, naive: :utc),
        total_test_count: metrics.total_count,
        failed_test_count: metrics.failed_count,
        flaky_test_count: metrics.flaky_count,
        avg_test_duration: metrics.avg_duration
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end
end
