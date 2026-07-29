defmodule Tuist.Runners.JobStepsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners.JobSteps

  defp step(workflow_job_id, account_id, number, attrs \\ %{}) do
    Map.merge(
      %{
        workflow_job_id: workflow_job_id,
        account_id: account_id,
        number: number,
        name: "Step #{number}",
        status: "completed",
        conclusion: "success",
        started_at: ~U[2026-05-28 10:00:00.000000Z],
        completed_at: ~U[2026-05-28 10:00:05.000000Z]
      },
      attrs
    )
  end

  describe "record/1" do
    test "is a no-op on an empty list" do
      assert :ok = JobSteps.record([])
      assert JobSteps.list_for_job(900_000) == []
    end

    test "persists each step with its timestamps and display order" do
      :ok =
        JobSteps.record([
          step(900_001, 42, 2, %{name: "Build"}),
          step(900_001, 42, 1, %{name: "Checkout"})
        ])

      assert [
               %{number: 1, name: "Checkout"},
               %{number: 2, name: "Build"}
             ] = JobSteps.list_for_job(900_001)
    end

    test "collapses a redelivered batch on the (workflow_job_id, number) RMT key" do
      first = step(900_002, 42, 1, %{conclusion: "failure"})
      :ok = JobSteps.record([first])
      # GitHub redelivers `workflow_job.completed` with the final
      # conclusion; the second write should replace the first per
      # ReplacingMergeTree dedup.
      :ok = JobSteps.record([%{first | conclusion: "success"}])

      assert [%{number: 1, conclusion: "success"}] = JobSteps.list_for_job(900_002)
    end

    test "tolerates nil timestamps for skipped steps" do
      :ok =
        JobSteps.record([
          step(900_003, 42, 1, %{
            name: "Skipped",
            status: "completed",
            conclusion: "skipped",
            started_at: nil,
            completed_at: nil
          })
        ])

      assert [%{number: 1, name: "Skipped", started_at: nil, completed_at: nil}] =
               JobSteps.list_for_job(900_003)
    end
  end

  describe "list_for_job/1" do
    test "returns an empty list when no steps have been recorded" do
      assert JobSteps.list_for_job(900_004) == []
    end

    test "scopes to the requested workflow_job_id" do
      :ok = JobSteps.record([step(900_005, 42, 1)])
      :ok = JobSteps.record([step(900_006, 42, 1)])

      assert [%{number: 1}] = JobSteps.list_for_job(900_005)
      assert [%{number: 1}] = JobSteps.list_for_job(900_006)
    end
  end
end
