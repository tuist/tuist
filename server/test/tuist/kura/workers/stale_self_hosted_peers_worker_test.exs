defmodule Tuist.Kura.Workers.StaleSelfHostedPeersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Workers.StaleSelfHostedPeersWorker

  test "sweeps stale self-hosted peers once the app has been up for a staleness window" do
    stub(StaleSelfHostedPeersWorker, :uptime_ms, fn ->
      Mesh.stale_peer_after_minutes() * 60_000 + 1
    end)

    expect(Mesh, :sweep_stale_self_hosted_peers, fn -> %{deactivated: [], purged: []} end)

    assert :ok = StaleSelfHostedPeersWorker.perform(%Oban.Job{})
  end

  test "skips the sweep while the app is younger than the staleness window" do
    # After a control-plane outage or deploy, nodes need a heartbeat cycle to
    # refresh their markers before silence is meaningful.
    stub(StaleSelfHostedPeersWorker, :uptime_ms, fn -> 0 end)

    reject(&Mesh.sweep_stale_self_hosted_peers/0)

    assert :ok = StaleSelfHostedPeersWorker.perform(%Oban.Job{})
  end
end
