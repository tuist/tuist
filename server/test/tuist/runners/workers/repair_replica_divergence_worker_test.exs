defmodule Tuist.Runners.Workers.RepairReplicaDivergenceWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.RepairReplicaDivergenceWorker

  test "repairs everything since enqueued_after that settled before the window" do
    now = DateTime.utc_now()

    expect(Jobs, :repair_replica_divergence, fn settled_before, enqueued_floor, _limit ->
      assert_in_delta DateTime.diff(now, settled_before, :minute), 5, 1
      assert enqueued_floor == ~U[2026-01-01 00:00:00Z]

      %{republished: 2078, closed: 6, scanned: 2084}
    end)

    assert :ok = perform_job(RepairReplicaDivergenceWorker, %{"enqueued_after" => "2026-01-01T00:00:00Z"})
  end

  test "a capped scan snoozes so the next pass sees the flushed repairs" do
    expect(Jobs, :repair_replica_divergence, fn _settled_before, _enqueued_floor, limit ->
      %{republished: limit, closed: 0, scanned: limit}
    end)

    assert {:snooze, _seconds} =
             perform_job(RepairReplicaDivergenceWorker, %{"enqueued_after" => "2026-01-01T00:00:00Z"})
  end
end
