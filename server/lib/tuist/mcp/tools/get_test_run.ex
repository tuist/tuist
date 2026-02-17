defmodule Tuist.MCP.Tools.GetTestRun do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Content
  alias Tuist.MCP.Errors
  alias Tuist.MCP.Formatter
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.CrashReport
  alias Tuist.Tests.TestCaseRun

  def name, do: "get_test_run"

  def definition do
    %{
      name: name(),
      description: "Get details and aggregate metrics for a specific test run, including crash summaries.",
      inputSchema: %{
        type: "object",
        properties: %{
          test_run_id: %{type: "string", description: "The UUID of the test run."}
        },
        required: ["test_run_id"]
      }
    }
  end

  def call(%{"test_run_id" => test_run_id}, subject) do
    with {:ok, run} <- Tests.get_test(test_run_id),
         :ok <- Authorization.authorize_project_id(:test_read, run.project_id, subject) do
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

      Content.ok_json(data)
    else
      {:error, :not_found} -> Errors.invalid_params("Test run not found: #{test_run_id}")
      {:error, code, message} -> {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    Errors.invalid_params("Missing required parameter: test_run_id.")
  end

  defp get_crash_summaries(test_run_id) do
    crash_base_query =
      from(tcr in TestCaseRun,
        where: tcr.test_run_id == ^test_run_id,
        join: crash_report in CrashReport,
        on: crash_report.test_case_run_id == tcr.id
      )

    crash_count_query =
      from([_tcr, crash_report] in crash_base_query,
        select: count(crash_report.id)
      )

    crashes_query =
      from([tcr, crash_report] in crash_base_query,
        order_by: [desc: crash_report.inserted_at],
        limit: 20,
        select: %{
          test_case_run_id: tcr.id,
          test_case_id: tcr.test_case_id,
          name: tcr.name,
          module_name: tcr.module_name,
          suite_name: tcr.suite_name,
          signal: crash_report.signal,
          exception_type: crash_report.exception_type,
          exception_subtype: crash_report.exception_subtype,
          crashed_at: crash_report.inserted_at
        }
      )

    {ClickHouseRepo.one(crash_count_query) || 0, ClickHouseRepo.all(crashes_query)}
  end
end
