defmodule Tuist.Sandboxes.AllocationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.SandboxNode

  @gib 1024 * 1024 * 1024

  setup do
    name = "allocation-#{TuistTestSupport.Utilities.unique_integer()}"

    node = %{
      name: name,
      capacity: %{memory_bytes: 12 * @gib},
      elastic: %{pod_name: "sandboxd-#{name}", memory_floor_bytes: @gib, memory_ceiling_bytes: 40 * @gib}
    }

    stub(Nodes, :lookup, fn ^name -> {:ok, self(), Map.delete(node, :name)} end)

    row =
      Repo.insert!(%SandboxNode{
        name: name,
        pod_name: node.elastic.pod_name,
        memory_limit_bytes: 12 * @gib,
        grown_at: DateTime.utc_now(:second)
      })

    {:ok, node: node, row: row}
  end

  defp grant(node, attrs \\ %{}) do
    Map.merge(
      %{
        "node" => node.name,
        "pod" => node.elastic.pod_name,
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "memory_bytes" => 40 * @gib,
        "free_bytes" => 20 * @gib,
        "reclaim" => false
      },
      attrs
    )
  end

  test "missing, expired, revoked and wrong-Pod grants refuse new turns", %{node: node, row: row} do
    sandbox = sandbox_fixture(node_name: node.name, state: :running)
    reject(&KubernetesClient.resize_sandbox_daemon_memory/3)
    assert {:error, :no_capacity} = Sandboxes.begin_residency(sandbox, "missing")
    assert {:error, :no_capacity} = Capacity.grow(node, @gib, 0)
    assert :ok = Capacity.update_allocation(grant(node))
    assert {:ok, _} = Sandboxes.begin_residency(sandbox, "allowed")

    row
    |> Repo.reload!()
    |> Ecto.Changeset.change(allocation_observed_at: DateTime.add(DateTime.utc_now(), -16))
    |> Repo.update!()

    assert {:error, :no_capacity} = Sandboxes.begin_residency(sandbox, "expired")
    assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "memory_bytes" => 0}))
    assert {:error, :no_capacity} = Sandboxes.begin_residency(sandbox, "revoked")
    assert Repo.reload!(sandbox).residency_work_id == "allowed"
    assert :ok = Capacity.update_allocation(grant(node, %{"pod" => "replacement"}))
    assert {:error, :no_capacity} = Capacity.grow(node, @gib, 0)
  end

  test "older observations cannot undo a reclaim, including after a publisher restart", %{node: node} do
    old = grant(node)
    assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "memory_bytes" => 0}))
    assert {:error, :stale_allocation} = Capacity.update_allocation(old)
    assert Repo.get!(SandboxNode, node.name).allocation_reclaim

    assert {:error, :invalid_allocation} =
             Capacity.update_allocation(
               grant(node, %{"observed_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -30))})
             )
  end

  test "pressure pauses idle VMs immediately, preserves active turns and bypasses growth hold", %{node: node} do
    idle = sandbox_fixture(node_name: node.name, state: :running, memory_mb: 4096)
    active = sandbox_fixture(node_name: node.name, state: :running, memory_mb: 4096, residency_work_id: "active")
    assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "memory_bytes" => 0}))

    expect(Nodes, :call, fn name, "pause", %{sandbox_id: id}, _ ->
      assert name == node.name and id == idle.id
      {:ok, %{}}
    end)

    expect(Nodes, :call, fn name, "reclaim", %{target_bytes: target}, _ ->
      assert name == node.name and target < 5 * @gib
      {:ok, %{}}
    end)

    expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _, pod, limit ->
      assert pod == node.elastic.pod_name and limit == 5 * @gib
      {:ok, %{}}
    end)

    assert :ok = Capacity.reconcile_allocation(node.name)
    assert Repo.reload!(idle).state == :paused
    assert Repo.reload!(active).residency_work_id == "active"
    assert Repo.get!(SandboxNode, node.name).memory_limit_bytes == 5 * @gib
  end

  test "a busy exec refusing pause stays charged and a failed shrink is retried", %{node: node} do
    idle = sandbox_fixture(node_name: node.name, state: :running, memory_mb: 4096)
    assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "memory_bytes" => 0}))

    stub(Nodes, :call, fn _, op, _, _ ->
      if op == "pause", do: {:error, :busy}, else: {:ok, %{}}
    end)

    expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _, _, limit ->
      assert limit == 5 * @gib
      {:error, :unavailable}
    end)

    assert {:error, :resize_failed} = Capacity.reconcile_allocation(node.name)
    assert Repo.reload!(idle).state == :running

    expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _, _, limit ->
      assert limit == 5 * @gib
      {:ok, %{}}
    end)

    assert :ok = Capacity.reconcile_allocation(node.name)
  end

  test "a newer allocation between desired-state growth and resize cancels the API write", %{node: node} do
    assert :ok = Capacity.update_allocation(grant(node))
    # Reclaim sends a command after lowering desired state but before resizing.
    # Simulate a different replica publishing/reconciling a newer desired size.
    expect(Nodes, :call, fn _, "reclaim", _, _ ->
      SandboxNode |> Repo.get!(node.name) |> Ecto.Changeset.change(memory_limit_bytes: 8 * @gib) |> Repo.update!()
      {:ok, %{}}
    end)

    reject(&KubernetesClient.resize_sandbox_daemon_memory/3)
    assert {:error, :superseded} = Capacity.shrink(node, true)
    assert Repo.get!(SandboxNode, node.name).memory_limit_bytes == 8 * @gib
  end

  test "shared fleet idle pauses have no extra warm grace", %{node: node} do
    sandbox = sandbox_fixture(node_name: node.name, state: :running, residency_work_id: "work")
    assert {:ok, _} = Sandboxes.end_residency(sandbox)
    [job] = all_enqueued(worker: Tuist.Sandboxes.Workers.PauseSandboxWorker)
    assert DateTime.diff(job.scheduled_at, job.inserted_at, :second) == 0
  end
end
