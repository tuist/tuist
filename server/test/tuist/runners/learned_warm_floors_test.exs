defmodule Tuist.Runners.LearnedWarmFloorsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Runners.Job
  alias Tuist.Runners.LearnedWarmFloors

  defp unique_fleet, do: "fleet-learned-#{System.unique_integer([:positive])}"

  defp job!(fleet, enqueued_at, opts \\ []) do
    row = %{
      workflow_job_id: Keyword.get(opts, :workflow_job_id, System.unique_integer([:positive])),
      account_id: 1,
      fleet_name: fleet,
      repository: "acme/app",
      status: Keyword.get(opts, :status, "queued"),
      conclusion: Keyword.get(opts, :conclusion, ""),
      enqueued_at: enqueued_at,
      updated_at: Keyword.get(opts, :updated_at, enqueued_at)
    }

    {1, _} = IngestRepo.insert_all(Job, [row])
    row.workflow_job_id
  end

  # `count` jobs enqueued one second apart, starting at `start`.
  defp burst!(fleet, start, count) do
    for i <- 0..(count - 1), do: job!(fleet, DateTime.add(start, i, :second))
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  test "is the size of the bursts a pool's jobs arrive in" do
    fleet = unique_fleet()

    # Three fan-outs of three and one single job: nine of the ten jobs
    # arrive with at most two others in the 30 s before them.
    burst!(fleet, ago(3 * 3600), 3)
    burst!(fleet, ago(2 * 3600), 3)
    burst!(fleet, ago(3600), 3)
    job!(fleet, ago(600))

    assert LearnedWarmFloors.for_fleet(fleet) == 3
  end

  test "is zero for a pool with no job in the last day" do
    fleet = unique_fleet()

    burst!(fleet, ago(2 * 86_400), 3)
    burst!(fleet, ago(3 * 86_400), 3)

    assert LearnedWarmFloors.for_fleet(fleet) == 0
  end

  test "counts older jobs within the two-week history once the pool is active" do
    fleet = unique_fleet()

    burst!(fleet, ago(5 * 86_400), 4)
    burst!(fleet, ago(4 * 86_400), 4)
    burst!(fleet, ago(3 * 86_400), 4)
    burst!(fleet, ago(2 * 86_400), 4)
    job!(fleet, ago(60))

    assert LearnedWarmFloors.for_fleet(fleet) == 4
  end

  test "ignores jobs older than two weeks" do
    fleet = unique_fleet()

    burst!(fleet, ago(20 * 86_400), 6)
    job!(fleet, ago(60))

    assert LearnedWarmFloors.for_fleet(fleet) == 1
  end

  test "counts a job once however many state transitions it has" do
    fleet = unique_fleet()
    enqueued_at = ago(120)

    workflow_job_id = job!(fleet, enqueued_at)
    job!(fleet, enqueued_at, workflow_job_id: workflow_job_id, status: "claimed", updated_at: ago(110))
    job!(fleet, enqueued_at, workflow_job_id: workflow_job_id, status: "completed", updated_at: ago(30))

    assert LearnedWarmFloors.for_fleet(fleet) == 1
  end

  test "leaves out skipped jobs, which never ask for a runner" do
    fleet = unique_fleet()
    start = ago(600)

    # One fan-out of six, three of them skipped by an `if:` condition.
    burst!(fleet, start, 3)

    for i <- 3..5 do
      job!(fleet, DateTime.add(start, i, :second), status: "completed", conclusion: "skipped")
    end

    assert LearnedWarmFloors.for_fleet(fleet) == 3
  end

  test "is zero for a pool without jobs" do
    fleet = unique_fleet()

    assert LearnedWarmFloors.for_fleet(fleet) == 0
    assert LearnedWarmFloors.hours_with_jobs(fleet) == 0
  end

  test "counts the hours a pool had jobs in, not its jobs" do
    used_all_day = unique_fleet()
    nightly = unique_fleet()

    # One job in each of five hours, against one 20-job nightly fan-out
    # (spread over a minute, so it stays within one clock hour) that also
    # ran last.
    for hour <- 2..6, do: job!(used_all_day, DateTime.add(ago(hour * 3600), -1800, :second))
    an_hour_ago = ago(3600)
    nightly_start = %{an_hour_ago | minute: 0, second: 0}
    for i <- 0..19, do: job!(nightly, DateTime.add(nightly_start, i * 3, :second))

    assert LearnedWarmFloors.hours_with_jobs(used_all_day) == 5
    assert LearnedWarmFloors.hours_with_jobs(nightly) == 1
  end

  test "leaves skipped jobs out of the hours with jobs" do
    fleet = unique_fleet()

    job!(fleet, ago(60))
    job!(fleet, ago(3 * 3600), status: "completed", conclusion: "skipped")

    assert LearnedWarmFloors.hours_with_jobs(fleet) == 1
  end
end
