defmodule Tuist.Sandboxes.Workers.PauseSandboxWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker

  test "pauses a running sandbox with no residency when the epoch matches" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 3)
    sandbox_id = sandbox.id

    expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^sandbox_id, sync_disks: true}, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 3})
    assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
  end

  test "does nothing when a newer residency bumped the epoch" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 4)
    reject(&Nodes.call/4)

    assert :ok = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 3})
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)
  end

  test "does nothing while a worker is resident" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 3, residency_work_id: "work_1")
    reject(&Nodes.call/4)

    assert :ok = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 3})
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)
  end

  test "does nothing when the sandbox is no longer running or is gone" do
    sandbox = sandbox_fixture(state: :paused, node_name: "node-a", residency_epoch: 3)
    reject(&Nodes.call/4)

    assert :ok = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 3})
    assert :ok = perform_job(PauseSandboxWorker, %{sandbox_id: Ecto.UUID.generate(), residency_epoch: 3})
  end

  test "returns the node error so the job retries" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 1)
    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, "snapshot failed"} end)

    assert {:error, "snapshot failed"} = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 1})
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)
  end

  test "snoozes while the node still runs an exec, then pauses once it ended" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 5)
    args = %{sandbox_id: sandbox.id, residency_epoch: 5}

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts ->
      {:error, "sandbox has a worker or exec running: #{sandbox.id}"}
    end)

    assert {:snooze, 15} = perform_job(PauseSandboxWorker, args)
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(PauseSandboxWorker, args)
    assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
  end

  test "snoozes while a restore's disks still load, then pauses once they are whole" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 2)
    args = %{sandbox_id: sandbox.id, residency_epoch: 2}

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts ->
      {:error, "sandbox disks are still loading from its archive: #{sandbox.id}"}
    end)

    assert {:snooze, 60} = perform_job(PauseSandboxWorker, args)
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(PauseSandboxWorker, args)
    assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
  end
end
