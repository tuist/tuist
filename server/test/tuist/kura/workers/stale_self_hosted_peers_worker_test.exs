defmodule Tuist.Kura.Workers.StaleSelfHostedPeersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Workers.StaleSelfHostedPeersWorker

  test "sweeps stale self-hosted peers and completes" do
    expect(Mesh, :sweep_stale_self_hosted_peers, fn -> %{deactivated: [], purged: []} end)

    assert :ok = StaleSelfHostedPeersWorker.perform(%Oban.Job{})
  end
end
