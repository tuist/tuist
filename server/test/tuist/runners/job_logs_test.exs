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

  describe "step_line_ranges/2 + list_step_lines/3" do
    defp lines_for_step(ranges, job_id, step_number) do
      case Map.get(ranges, step_number) do
        {first, last} -> JobLogs.list_step_lines(job_id, first, last)
        _ -> []
      end
    end

    test "slices a 3-step job on `##[group]Run` markers" do
      job_id = 90_002

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "Current runner version: '2.334.0'"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "##[group]GITHUB_TOKEN Permissions"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 3,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "Metadata: read"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 4,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "##[endgroup]"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 5,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "##[group]Run echo hi"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 6,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "##[endgroup]"
          },
          %{workflow_job_id: job_id, account_id: 1, line_number: 7, ts: ~U[2026-05-28 12:00:01.000000Z], message: "hi"},
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 8,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "##[group]Run echo bye"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 9,
            ts: ~U[2026-05-28 12:00:02.000000Z],
            message: "##[endgroup]"
          },
          %{workflow_job_id: job_id, account_id: 1, line_number: 10, ts: ~U[2026-05-28 12:00:02.000000Z], message: "bye"},
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 11,
            ts: ~U[2026-05-28 12:00:05.000000Z],
            message: "Cleaning up orphan processes"
          }
        ])

      steps = [
        %{number: 1, name: "Set up job", started_at: ~U[2026-05-28 12:00:00.000000Z]},
        %{number: 2, name: "First step", started_at: ~U[2026-05-28 12:00:01.000000Z]},
        %{number: 3, name: "Second step", started_at: ~U[2026-05-28 12:00:01.000000Z]},
        %{number: 4, name: "Complete job", started_at: ~U[2026-05-28 12:00:05.000000Z]}
      ]

      ranges = JobLogs.step_line_ranges(job_id, steps)

      # "Set up job" gets lines 1-4 (everything before the first ##[group]Run)
      assert Enum.map(lines_for_step(ranges, job_id, 1), & &1.message) == [
               "Current runner version: '2.334.0'",
               "##[group]GITHUB_TOKEN Permissions",
               "Metadata: read",
               "##[endgroup]"
             ]

      # First user step: from first ##[group]Run to (second ##[group]Run - 1)
      assert Enum.map(lines_for_step(ranges, job_id, 2), & &1.message) == ["##[group]Run echo hi", "##[endgroup]", "hi"]

      # Second user step: from second ##[group]Run to (last_user_end derived from teardown timestamp - 1)
      assert Enum.map(lines_for_step(ranges, job_id, 3), & &1.message) == ["##[group]Run echo bye", "##[endgroup]", "bye"]

      # "Complete job" gets the cleanup tail
      assert Enum.map(lines_for_step(ranges, job_id, 4), & &1.message) == ["Cleaning up orphan processes"]
    end

    test "two adjacent sub-second steps with identical `started_at` each get their own marker block" do
      job_id = 90_004

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "Set up job line"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "##[group]Run a"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 3,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "a-out"
          },
          %{
            workflow_job_id: job_id,
            account_id: 1,
            line_number: 4,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "##[group]Run b"
          },
          %{workflow_job_id: job_id, account_id: 1, line_number: 5, ts: ~U[2026-05-28 12:00:01.000000Z], message: "b-out"}
        ])

      # `a` and `b` share the same second; the broken timestamp-window
      # slicing would have given `a` a zero-width window.
      steps = [
        %{number: 1, name: "Set up job", started_at: ~U[2026-05-28 12:00:00.000000Z]},
        %{number: 2, name: "a", started_at: ~U[2026-05-28 12:00:01.000000Z]},
        %{number: 3, name: "b", started_at: ~U[2026-05-28 12:00:01.000000Z]}
      ]

      ranges = JobLogs.step_line_ranges(job_id, steps)

      assert Enum.map(lines_for_step(ranges, job_id, 1), & &1.message) == ["Set up job line"]
      assert Enum.map(lines_for_step(ranges, job_id, 2), & &1.message) == ["##[group]Run a", "a-out"]
      assert Enum.map(lines_for_step(ranges, job_id, 3), & &1.message) == ["##[group]Run b", "b-out"]
    end

    test "no markers at all -> everything lumped under step 1" do
      job_id = 90_005

      :ok =
        JobLogs.append([
          %{workflow_job_id: job_id, account_id: 1, line_number: 1, ts: ~U[2026-05-28 12:00:00.000000Z], message: "one"},
          %{workflow_job_id: job_id, account_id: 1, line_number: 2, ts: ~U[2026-05-28 12:00:01.000000Z], message: "two"}
        ])

      steps = [
        %{number: 1, name: "Set up job", started_at: ~U[2026-05-28 12:00:00.000000Z]},
        %{number: 2, name: "Complete job", started_at: ~U[2026-05-28 12:00:01.000000Z]}
      ]

      ranges = JobLogs.step_line_ranges(job_id, steps)

      assert Enum.map(lines_for_step(ranges, job_id, 1), & &1.message) == ["one", "two"]
      assert Map.get(ranges, 2) == nil
    end

    test "empty log -> every step is unmapped" do
      steps = [%{number: 1, name: "Set up job", started_at: ~U[2026-05-28 12:00:00.000000Z]}]
      assert JobLogs.step_line_ranges(90_006, steps) == %{1 => nil}
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
