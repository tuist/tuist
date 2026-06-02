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
    test "returns lines inside the [from, until) window" do
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

    test "with `until = nil`, returns everything from `from` onwards (last step)" do
      job_id = 90_004

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "before"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:05.000000Z],
            message: "final-step"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 3,
            ts: ~U[2026-05-28 12:00:09.000000Z],
            message: "final-tail"
          }
        ])

      slice = JobLogs.list_for_step(job_id, ~U[2026-05-28 12:00:05.000000Z], nil)

      assert Enum.map(slice, & &1.message) == ["final-step", "final-tail"]
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

  describe "recent/2, older/3, has_older?/2 pagination" do
    setup do
      job_id = 90_500

      :ok =
        JobLogs.append(
          for n <- 1..10 do
            %{
              workflow_job_id: job_id,
              account_id: 1,
              line_number: n,
              ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :second),
              message: "line #{n}"
            }
          end
        )

      %{job_id: job_id}
    end

    test "recent/2 returns the last N lines in ascending order", %{job_id: job_id} do
      lines = JobLogs.recent(job_id, 3)
      assert Enum.map(lines, & &1.line_number) == [8, 9, 10]
      assert Enum.map(lines, & &1.message) == ["line 8", "line 9", "line 10"]
    end

    test "older/3 returns the page before the cursor, ascending", %{job_id: job_id} do
      older = JobLogs.older(job_id, 8, 3)
      assert Enum.map(older, & &1.line_number) == [5, 6, 7]
    end

    test "has_older?/2 reflects whether earlier lines exist", %{job_id: job_id} do
      assert JobLogs.has_older?(job_id, 8)
      refute JobLogs.has_older?(job_id, 1)
      refute JobLogs.has_older?(job_id, nil)
    end
  end

  describe "search/3" do
    test "case-insensitively matches a substring across all lines, scoped to the job" do
      job_id = 90_700
      other_job_id = 90_701

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "Compiling project"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "Running TESTS now"
          },
          %{
            workflow_job_id: other_job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "tests in another job"
          }
        ])

      assert Enum.map(JobLogs.search(job_id, "tests"), & &1.message) == ["Running TESTS now"]
    end

    test "an empty term returns no results" do
      assert JobLogs.search(90_710, "") == []
    end

    test "treats LIKE wildcards as literals" do
      job_id = 90_720

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "literal 50% off"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "no percent here"
          }
        ])

      assert Enum.map(JobLogs.search(job_id, "50%"), & &1.message) == ["literal 50% off"]
    end
  end

  describe "reduce/4" do
    test "folds every line forward in batches" do
      job_id = 90_600

      :ok =
        JobLogs.append(
          for n <- 1..25 do
            %{
              workflow_job_id: job_id,
              account_id: 1,
              line_number: n,
              ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :second),
              message: "m#{n}"
            }
          end
        )

      {batches, lines} =
        JobLogs.reduce(job_id, 10, {0, []}, fn batch, {count, acc} ->
          {count + 1, acc ++ batch}
        end)

      assert batches == 3
      assert Enum.map(lines, & &1.line_number) == Enum.to_list(1..25)
    end
  end
end
