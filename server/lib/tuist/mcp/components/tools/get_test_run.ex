defmodule Tuist.MCP.Components.Tools.GetTestRun do
  @moduledoc """
  Get details and aggregate metrics for a specific test run, including crash summaries.
  """

  use Hermes.Server.Component, type: :tool
  use Tuist.MCP.Components.ToolPlug, action: :read, category: :test

  import Ecto.Query

  alias Hermes.Server.Response
  alias Tuist.ClickHouseRepo
  alias Tuist.MCP.Formatter
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.CrashReport
  alias Tuist.Tests.TestCaseRun

  schema do
    field :test_run_id, :string, required: true, description: "The UUID of the test run."
  end

  @impl true
  def execute(%{test_run_id: test_run_id}, frame) do
    with {:ok, run} <- load_resource(Tests.get_test(test_run_id), "Test run not found: #{test_run_id}", frame),
         {:ok, _project} <- authorize_project_by_id(frame, run.project_id) do
      metrics = Analytics.get_test_run_metrics(run.id)
      {crashed_test_count, crashes} = get_crash_summaries(run.id)

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
        avg_test_duration: metrics.avg_duration,
        crashed_test_count: crashed_test_count,
        crashes:
          Enum.map(crashes, fn crash ->
            %{
              test_case_run_id: crash.test_case_run_id,
              test_case_id: crash.test_case_id,
              name: crash.name,
              module_name: crash.module_name,
              suite_name: crash.suite_name,
              signal: crash.signal,
              exception_type: crash.exception_type,
              exception_subtype: crash.exception_subtype,
              crashed_at: Formatter.iso8601(crash.crashed_at, naive: :utc)
            }
          end)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_crash_summaries(test_run_id) do
    crash_base_query =
      from(test_case_run in TestCaseRun,
        where: test_case_run.test_run_id == ^test_run_id,
        join: crash_report in CrashReport,
        on: crash_report.test_case_run_id == test_case_run.id
      )

    crash_count_query =
      from([_test_case_run, crash_report] in crash_base_query,
        select: count(crash_report.id)
      )

    crashes_query =
      from([test_case_run, crash_report] in crash_base_query,
        order_by: [desc: crash_report.inserted_at],
        limit: 20,
        select: %{
          test_case_run_id: test_case_run.id,
          test_case_id: test_case_run.test_case_id,
          name: test_case_run.name,
          module_name: test_case_run.module_name,
          suite_name: test_case_run.suite_name,
          signal: crash_report.signal,
          exception_type: crash_report.exception_type,
          exception_subtype: crash_report.exception_subtype,
          crashed_at: crash_report.inserted_at
        }
      )

    {ClickHouseRepo.one(crash_count_query) || 0, ClickHouseRepo.all(crashes_query)}
  end
end
