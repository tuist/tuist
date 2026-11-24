defmodule Tuist.Sandboxes.AllocationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.SandboxNode
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker

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

    # Pre-migration rows have NULL allocation fields and must also fail closed.
    row |> Ecto.Changeset.change(allocation_reclaim: nil) |> Repo.update!()
    assert {:error, :no_capacity} = Sandboxes.begin_residency(sandbox, "uninitialized")
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

    stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
    assert :ok = Capacity.reconcile_allocation(node.name)
    assert Repo.reload!(idle).state == :paused
    assert Repo.reload!(active).residency_work_id == "active"
    assert Repo.get!(SandboxNode, node.name).memory_limit_bytes == 5 * @gib

    # CI is taking the node, so the sandbox it just paused moves to storage.
    node_name = node.name

    assert [%{args: %{"node_names" => [^node_name], "ci" => true}}] =
             all_enqueued(worker: ArchiveSandboxesWorker)
  end

  test "an expired grant reclaims without moving paused sandboxes off the node", %{node: node, row: row} do
    sandbox_fixture(node_name: node.name, state: :paused, paused_at: DateTime.utc_now(:second))
    stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)

    row
    |> Ecto.Changeset.change(allocation_reclaim: false, allocation_observed_at: DateTime.add(DateTime.utc_now(), -60))
    |> Repo.update!()

    stub(Nodes, :call, fn _, "reclaim", _, _ -> {:ok, %{}} end)
    stub(KubernetesClient, :resize_sandbox_daemon_memory, fn _, _, _ -> {:ok, %{}} end)

    assert :ok = Capacity.reconcile_allocation(node.name)
    assert [] = all_enqueued(worker: ArchiveSandboxesWorker)
  end

  test "a pause keeps a fresh growth that another placement has not reserved yet", %{node: node} do
    assert :ok = Capacity.update_allocation(grant(node))
    sandbox = sandbox_fixture(node_name: node.name, state: :running, memory_mb: 4096)
    stub(Nodes, :call, fn _name, "pause", _args, _opts -> {:ok, %{}} end)
    reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

    assert {:ok, %{state: :paused}} = Sandboxes.pause(sandbox)
    assert :ok = Capacity.reconcile_allocation(node.name)
    assert Repo.get!(SandboxNode, node.name).memory_limit_bytes == 12 * @gib
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
    assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "memory_bytes" => 0}))
    # Reclaim sends a command after lowering desired state but before resizing.
    # Simulate a different replica publishing/reconciling a newer desired size.
    expect(Nodes, :call, fn _, "reclaim", _, _ ->
      SandboxNode |> Repo.get!(node.name) |> Ecto.Changeset.change(memory_limit_bytes: 8 * @gib) |> Repo.update!()
      {:ok, %{}}
    end)

    reject(&KubernetesClient.resize_sandbox_daemon_memory/3)
    # The newer size's writer resizes the Pod, so the reclaim job succeeds.
    assert :ok = Capacity.reconcile_allocation(node.name)
    assert Repo.get!(SandboxNode, node.name).memory_limit_bytes == 8 * @gib
  end

  test "shared fleet idle pauses have no extra warm grace", %{node: node} do
    sandbox = sandbox_fixture(node_name: node.name, state: :running, residency_work_id: "work")
    assert {:ok, _} = Sandboxes.end_residency(sandbox)
    [job] = all_enqueued(worker: Tuist.Sandboxes.Workers.PauseSandboxWorker)
    assert DateTime.diff(job.scheduled_at, job.inserted_at, :second) == 0
  end

  describe "daemon CPU requests" do
    setup %{node: node} do
      cpu_node = put_in(node, [:elastic, :cpu_floor_milli], 250)
      cpu_node = put_in(cpu_node, [:elastic, :cpu_ceiling_milli], 8000)

      # The Pod's CPU request, what the kubelet allocated (it applies a
      # request at the next read unless `defer` holds it) and how often it
      # was read, as the stubbed resize reads and writes them.
      pod = start_supervised!({Agent, fn -> %{milli: 250, allocated: 250, defer: false, reads: 0} end})

      stub(KubernetesClient, :resize_sandbox_daemon_cpu, fn _namespace, pod_name, target ->
        assert pod_name == cpu_node.elastic.pod_name

        Agent.get_and_update(pod, fn %{milli: requested, defer: defer, reads: reads} = state ->
          allocated = if defer, do: state.allocated, else: requested
          milli = target.(allocated)

          {{:ok, milli, milli == allocated and milli == requested},
           %{state | milli: milli, allocated: allocated, reads: reads + 1}}
        end)
      end)

      {:ok, cpu_node: cpu_node, pod: pod}
    end

    test "grow into the grant's free CPU with the node's agent sandboxes and shrink as they pause", %{
      cpu_node: node,
      pod: pod
    } do
      running = sandbox_fixture(node_name: node.name, state: :running, vcpus: 1, memory_mb: 2048)
      sandbox_fixture(node_name: node.name, state: :creating, vcpus: 4, memory_mb: 8192)
      sandbox_fixture(node_name: node.name, state: :paused, vcpus: 8, memory_mb: 16_384)
      sandbox_fixture(node_name: node.name, state: :running, vcpus: 16, purpose: :remote_execution)

      # A controller without CPU grants gives the daemon no room to grow.
      assert :ok = Capacity.update_allocation(grant(node))
      assert {:ok, 250} = Capacity.sync_cpu(node)

      # 250m floor + the charged agent sandboxes' quarter vCPU per GiB
      # (500m + 2000m) is 2750m; the grant has room for 250m more.
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 250}))
      assert {:ok, 500} = Capacity.sync_cpu(node)

      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 5000}))
      assert {:ok, 2750} = Capacity.sync_cpu(node)

      # Once the kubelet has applied it, unchanged guarantees read nothing
      # from Kubernetes.
      assert {:ok, 2750} = Capacity.sync_cpu(node)
      reads = Agent.get(pod, & &1.reads)
      assert :unchanged = Capacity.sync_cpu(node)
      assert Agent.get(pod, & &1.reads) == reads

      # A revoked grant blocks growth, never a shrink.
      running |> Ecto.Changeset.change(state: :paused) |> Repo.update!()
      assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "cpu_free_milli" => 0}))
      assert {:ok, 2250} = Capacity.sync_cpu(node)
    end

    test "a sandbox that paused a moment ago keeps its guarantee until CI reclaims the node", %{cpu_node: node} do
      ago = fn seconds -> DateTime.add(DateTime.utc_now(:second), -seconds, :second) end
      sandbox_fixture(node_name: node.name, state: :running, vcpus: 1, memory_mb: 2048)
      sandbox_fixture(node_name: node.name, state: :paused, paused_at: ago.(60), memory_mb: 8192)
      sandbox_fixture(node_name: node.name, state: :paused, paused_at: ago.(600), memory_mb: 16_384)

      # 250m floor + 500m running + 2000m for the one paused a minute ago; the
      # one paused ten minutes ago has given its 4000m back.
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 8000}))
      assert {:ok, 2750} = Capacity.sync_cpu(node)

      assert :ok = Capacity.update_allocation(grant(node, %{"reclaim" => true, "cpu_free_milli" => 0}))
      assert {:ok, 750} = Capacity.sync_cpu(node)
    end

    test "grows into idle warm runners' CPU, and lowers a deferred growth the grant stops funding", %{
      cpu_node: node,
      pod: pod
    } do
      # 250m floor + 2000m (8 GiB) + 500m (2 GiB) is 2750m.
      sandbox_fixture(node_name: node.name, state: :running, vcpus: 4, memory_mb: 8192)
      sandbox_fixture(node_name: node.name, state: :running, vcpus: 1, memory_mb: 2048)

      # No CPU is free, but an idle warm runner holds 4250m: the growth is
      # asked for, and the kubelet defers it until the runner is retired.
      Agent.update(pod, &%{&1 | defer: true})
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 0, "cpu_reclaimable_milli" => 4250}))
      assert {:ok, 2750} = Capacity.sync_cpu(node)

      # A pending growth is not cached: every sync reads it again.
      reads = Agent.get(pod, & &1.reads)
      assert {:ok, 2750} = Capacity.sync_cpu(node)
      assert Agent.get(pod, & &1.reads) == reads + 1

      # The runner claimed a job before it was retired: the request goes
      # back to what the kubelet allocated, so it stops holding up the
      # daemon's memory growths.
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 0, "cpu_reclaimable_milli" => 0}))
      assert {:ok, 250} = Capacity.sync_cpu(node)

      # Some CPU frees up: it grows by that much.
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 1000, "cpu_reclaimable_milli" => 0}))
      assert {:ok, 1250} = Capacity.sync_cpu(node)
    end

    test "stays within the ceiling, and a node not shared with CI grows freely", %{cpu_node: node} do
      Repo.delete!(Repo.get!(SandboxNode, node.name))
      node = put_in(node, [:elastic, :cpu_ceiling_milli], 3000)
      sandbox_fixture(node_name: node.name, state: :running)
      assert {:ok, 1250} = Capacity.sync_cpu(node)

      for _ <- 1..3, do: sandbox_fixture(node_name: node.name, state: :resuming)
      assert {:ok, 3000} = Capacity.sync_cpu(node)
    end

    test "the server's ceiling wins over the daemon's", %{cpu_node: node} do
      Repo.delete!(Repo.get!(SandboxNode, node.name))
      # 250m floor + four 4 GiB sandboxes' 1000m each is 4250m.
      for _ <- 1..4, do: sandbox_fixture(node_name: node.name, state: :running)

      # A daemon whose reported ceiling is its floor holds its request...
      fixed = put_in(node, [:elastic, :cpu_ceiling_milli], 250)
      refute Capacity.cpu_elastic?(fixed)
      assert :unchanged = Capacity.sync_cpu(fixed)

      # ...until the server's ceiling raises it, with no daemon restart.
      stub(Environment, :sandbox_cpu_ceiling_milli, fn -> 3000 end)
      assert Capacity.cpu_elastic?(fixed)
      assert {:ok, 3000} = Capacity.sync_cpu(fixed)

      # It caps a daemon reporting a higher one too.
      assert {:ok, 3000} = Capacity.sync_cpu(node)
    end

    test "a guarantee goes only where the node holds it and has the CPU for it", %{cpu_node: node} do
      # 4096 MB is guaranteed a quarter vCPU per GiB, 1000m.
      default = sandbox_fixture(node_name: nil, state: :creating)
      picked = sandbox_fixture(node_name: nil, state: :creating, guaranteed_cpu_milli: 2000)
      guarded = Map.put(node, :cpu_guarantees, true)

      # Without per-VM cgroups the node's VMs share one weight: it takes
      # memory guarantees, as before guarantees were held, but not a picked
      # one, which would not be the sandbox's own.
      assert Capacity.cpu_room?(node, default)
      refute Capacity.cpu_room?(node, picked)

      # Nor does a node whose controller reports no free CPU.
      assert :ok = Capacity.update_allocation(grant(node))
      assert Capacity.cpu_room?(guarded, default)
      refute Capacity.cpu_room?(guarded, picked)

      # 250m floor + 4000m already guaranteed + 2000m fits the 8000m
      # ceiling, but only into CPU the grant reports free, and a memory
      # guarantee needs that room too.
      sandbox_fixture(node_name: node.name, state: :running, guaranteed_cpu_milli: 4000)
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 999}))
      refute Capacity.cpu_room?(guarded, default)
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 1999}))
      assert Capacity.cpu_room?(guarded, default)
      refute Capacity.cpu_room?(guarded, picked)
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 2000}))
      assert Capacity.cpu_room?(guarded, picked)

      # CPU idle warm runners hold counts too: they give it up.
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 500, "cpu_reclaimable_milli" => 1500}))
      assert Capacity.cpu_room?(guarded, picked)

      # Past the ceiling no grant helps: 6250m + 2000m is over 8000m, while
      # 6250m + 1000m still fits.
      sandbox_fixture(node_name: node.name, state: :running, guaranteed_cpu_milli: 2000)
      assert :ok = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 8000}))
      refute Capacity.cpu_room?(guarded, picked)
      assert Capacity.cpu_room?(guarded, default)

      # The daemon's request follows the guarantees, up to the ceiling.
      assert {:ok, 6250} = Capacity.sync_cpu(node)
    end

    test "rejects a negative reclaimable CPU grant", %{cpu_node: node} do
      assert {:error, :invalid_allocation} =
               Capacity.update_allocation(grant(node, %{"cpu_free_milli" => 0, "cpu_reclaimable_milli" => -1}))
    end

    test "rejects a negative free CPU grant", %{cpu_node: node} do
      assert {:error, :invalid_allocation} = Capacity.update_allocation(grant(node, %{"cpu_free_milli" => -1}))
    end
  end
end
