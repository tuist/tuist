defmodule Tuist.Runners.Workers.RepairReplicaDivergenceWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.RepairReplicaDivergenceWorker

  test "the cron pass repairs the last seven days past the settle window, without closing untracked rows" do
    now = DateTime.utc_now()

    expect(Jobs, :repair_replica_divergence, fn settled_before, enqueued_floor, opts ->
      assert_in_delta DateTime.diff(now, settled_before, :minute), 5, 1
      assert_in_delta DateTime.diff(now, enqueued_floor, :day), 7, 1
      refute Keyword.get(opts, :close_untracked)

      %{republished: 0, closed: 0, scanned: 0}
    end)

    assert :ok = perform_job(RepairReplicaDivergenceWorker, %{})
  end

  test "the backfill pass covers everything since enqueued_after and closes untracked rows" do
    expect(Jobs, :repair_replica_divergence, fn _settled_before, enqueued_floor, opts ->
      assert enqueued_floor == ~U[2026-05-01 00:00:00Z]
      assert Keyword.fetch!(opts, :close_untracked)

      %{republished: 2078, closed: 6, scanned: 2084}
    end)

    assert :ok = perform_job(RepairReplicaDivergenceWorker, %{"enqueued_after" => "2026-05-01T00:00:00Z"})
  end

  test "a capped backfill scan snoozes so the next pass sees the flushed repairs" do
    expect(Jobs, :repair_replica_divergence, fn _settled_before, _enqueued_floor, opts ->
      %{republished: Keyword.fetch!(opts, :limit), closed: 0, scanned: Keyword.fetch!(opts, :limit)}
    end)

    assert {:snooze, _seconds} =
             perform_job(RepairReplicaDivergenceWorker, %{"enqueued_after" => "2026-05-01T00:00:00Z"})
  end
end
