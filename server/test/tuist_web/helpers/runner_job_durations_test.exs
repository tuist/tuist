defmodule TuistWeb.Helpers.RunnerJobDurationsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.RunnerJobDurations

  @three_days_ms 3 * 24 * 60 * 60 * 1000

  defp job(attrs) do
    Map.merge(
      %{
        status: "queued",
        conclusion: nil,
        enqueued_at: nil,
        claimed_at: nil,
        started_at: nil,
        completed_at: nil
      },
      Map.new(attrs)
    )
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  describe "queued_ms/1" do
    test "counts live time since enqueue while the job is queued" do
      assert RunnerJobDurations.queued_ms(job(status: "queued", enqueued_at: days_ago(3))) >= @three_days_ms
    end

    test "measures enqueue to claim once the job is claimed" do
      for status <- ["claimed", "running", "completed", "cancelled"] do
        job =
          job(
            status: status,
            enqueued_at: ~U[2026-10-20 10:00:00Z],
            claimed_at: ~U[2026-10-20 10:00:42Z]
          )

        assert RunnerJobDurations.queued_ms(job) == 42_000
      end
    end

    test "is 0 for a completed job that was never claimed" do
      job =
        job(
          status: "completed",
          conclusion: "skipped",
          enqueued_at: days_ago(3),
          completed_at: days_ago(3)
        )

      assert RunnerJobDurations.queued_ms(job) == 0
    end

    test "is 0 for a cancelled job that was never claimed" do
      for status <- ["cancelled", "completed"] do
        job =
          job(
            status: status,
            conclusion: "cancelled",
            enqueued_at: days_ago(3),
            completed_at: days_ago(2)
          )

        assert RunnerJobDurations.queued_ms(job) == 0
      end
    end

    test "is 0 without an enqueue timestamp" do
      assert RunnerJobDurations.queued_ms(job(status: "queued")) == 0
      assert RunnerJobDurations.queued_ms(job(status: "claimed", claimed_at: days_ago(1))) == 0
    end
  end

  describe "run_ms/1" do
    test "counts live time since start while the job is running" do
      assert RunnerJobDurations.run_ms(job(status: "running", started_at: days_ago(3))) >= @three_days_ms
    end

    test "measures start to completion once the job finished" do
      job =
        job(
          status: "completed",
          started_at: ~U[2026-10-20 10:00:00Z],
          completed_at: ~U[2026-10-20 10:05:00Z]
        )

      assert RunnerJobDurations.run_ms(job) == 300_000
    end

    test "is 0 for a terminal job that never started" do
      for {status, conclusion} <- [{"completed", "skipped"}, {"cancelled", "cancelled"}] do
        job =
          job(
            status: status,
            conclusion: conclusion,
            enqueued_at: days_ago(3),
            completed_at: days_ago(3)
          )

        assert RunnerJobDurations.run_ms(job) == 0
      end
    end

    test "is 0 for a terminal job missing its completion timestamp" do
      assert RunnerJobDurations.run_ms(job(status: "completed", started_at: days_ago(3))) == 0
    end
  end

  describe "list_ms/1" do
    test "shows the live queue wait while queued" do
      assert RunnerJobDurations.list_ms(job(status: "queued", enqueued_at: days_ago(3))) >= @three_days_ms
    end

    test "shows the live time since the claim while claimed" do
      job = job(status: "claimed", enqueued_at: days_ago(4), claimed_at: days_ago(3))

      assert RunnerJobDurations.list_ms(job) in @three_days_ms..(@three_days_ms + 60_000)
    end

    test "shows the run time once running or finished" do
      assert RunnerJobDurations.list_ms(job(status: "running", started_at: days_ago(3))) >= @three_days_ms

      for status <- ["completed", "cancelled"] do
        job =
          job(
            status: status,
            started_at: ~U[2026-10-20 10:00:00Z],
            completed_at: ~U[2026-10-20 10:05:00Z]
          )

        assert RunnerJobDurations.list_ms(job) == 300_000
      end
    end

    test "is 0 for a terminal job that never started" do
      job =
        job(
          status: "completed",
          conclusion: "skipped",
          enqueued_at: days_ago(3),
          completed_at: days_ago(3)
        )

      assert RunnerJobDurations.list_ms(job) == 0
    end
  end
end
