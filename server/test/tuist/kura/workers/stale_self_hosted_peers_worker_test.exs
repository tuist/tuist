defmodule Tuist.Kura.Workers.StaleSelfHostedPeersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Workers.StaleSelfHostedPeersWorker

  test "prunes stale self-hosted peers and completes" do
    expect(Mesh, :prune_stale_self_hosted_peers, fn -> [] end)

    assert :ok = StaleSelfHostedPeersWorker.perform(%Oban.Job{})
  end
end
