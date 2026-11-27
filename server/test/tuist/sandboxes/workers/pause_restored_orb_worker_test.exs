defmodule Tuist.Sandboxes.Workers.PauseRestoredOrbWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Workers.PauseRestoredOrbWorker

  setup do
    sandbox =
      sandbox_fixture(
        amp_orb_id: "amp-thread",
        node_name: "node-a",
        residency_work_id: "amp:amp-thread",
        residency_epoch: 3
      )

    %{sandbox: sandbox, args: %{sandbox_id: sandbox.id, residency_epoch: 3}}
  end

  # Every Orb pause reads the guest's setup log first, then pauses.
  defp stub_pause(result) do
    stub(Nodes, :call, fn
      "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}}
      "node-a", "pause", _args, _opts -> result
    end)
  end

  test "pauses the Orb Amp asked to pause once its disks have loaded", %{sandbox: sandbox, args: args} do
    stub_pause({:ok, %{}})

    assert :ok = perform_job(PauseRestoredOrbWorker, args)
    assert %{state: :paused, residency_work_id: nil} = Repo.reload!(sandbox)
  end

  test "waits while the disks still load", %{sandbox: sandbox, args: args} do
    stub_pause({:error, "sandbox disks are still loading from its archive: #{sandbox.id}"})

    assert {:snooze, 60} = perform_job(PauseRestoredOrbWorker, args)
    assert Repo.reload!(sandbox).state == :running
  end

  test "leaves an Orb Amp spawned again since alone", %{sandbox: sandbox, args: args} do
    reject(&Nodes.call/4)

    assert :ok = perform_job(PauseRestoredOrbWorker, %{args | residency_epoch: 2})
    assert Repo.reload!(sandbox).state == :running
  end
end
