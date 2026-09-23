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

    expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{}} end)

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
    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, "exec running"} end)

    assert {:error, "exec running"} = perform_job(PauseSandboxWorker, %{sandbox_id: sandbox.id, residency_epoch: 1})
    assert %Sandbox{state: :running} = Repo.reload!(sandbox)
  end
end
