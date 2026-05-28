defmodule Tuist.Runners.JobLogsTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Runners.JobLogs

  describe "append/1 + list_for_job/2" do
    test "returns a job's lines in line_number order" do
      job_id = 90_001

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:02.000000Z],
            message: "second"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "first"
          }
        ])

      lines = JobLogs.list_for_job(job_id)

      assert Enum.map(lines, & &1.line_number) == [1, 2]
      assert Enum.map(lines, & &1.message) == ["first", "second"]
    end

    test "scopes to the requested job" do
      :ok =
        JobLogs.append([
          %{workflow_job_id: 90_010, account_id: 1, line_number: 1, ts: ~U[2026-05-28 12:00:00.000000Z], message: "mine"},
          %{
            workflow_job_id: 90_011,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "theirs"
          }
        ])

      assert Enum.map(JobLogs.list_for_job(90_010), & &1.message) == ["mine"]
    end

    test "empty batch is a no-op" do
      assert :ok = JobLogs.append([])
    end
  end

  describe "list_for_step/3" do
    test "returns only the lines inside the step's [start, end) window" do
      job_id = 90_002

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "setup"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:05.000000Z],
            message: "build start"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 3,
            ts: ~U[2026-05-28 12:00:09.000000Z],
            message: "build end"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 4,
            ts: ~U[2026-05-28 12:00:12.000000Z],
            message: "teardown"
          }
        ])

      slice = JobLogs.list_for_step(job_id, ~U[2026-05-28 12:00:05.000000Z], ~U[2026-05-28 12:00:10.000000Z])

      assert Enum.map(slice, & &1.message) == ["build start", "build end"]
    end
  end

  describe "count_for_job/1 + idempotency" do
    test "a retried (duplicate) line collapses via the ReplacingMergeTree" do
      job_id = 90_003

      line = %{
        workflow_job_id: job_id,
        account_id: 1,
        line_number: 1,
        ts: ~U[2026-05-28 12:00:00.000000Z],
        message: "x"
      }

      :ok = JobLogs.append([line])
      :ok = JobLogs.append([line])

      assert JobLogs.count_for_job(job_id) == 1
      assert length(JobLogs.list_for_job(job_id)) == 1
    end

    test "returns 0 for a job with no captured logs" do
      assert JobLogs.count_for_job(90_999) == 0
    end
  end
end
