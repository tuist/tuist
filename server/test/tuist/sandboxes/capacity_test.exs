defmodule Tuist.Sandboxes.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  @mib 1024 * 1024
  @gib 1024 * @mib

  # Presence is cluster-wide and tests run concurrently, so every test
  # gets its own template name and node names; only nodes advertising the
  # test's template take part in its placements.
  setup do
    template = "t#{TuistTestSupport.Utilities.unique_integer()}"
    {:ok, template: template}
  end

  # Tracks the test process as the node's socket. Presence converges
  # asynchronously, so the lookup is polled.
  defp connect(node_name, template, overrides \\ %{}) do
    info =
      Map.merge(
        %{
          capacity: %{memory_bytes: 20 * @gib, cpus: 16},
          memory: %{},
          disk: %{},
          templates: [%{name: template, tag: "sha-1", ready: true}],
          sandboxes: [],
          daemon_version: "test",
          firecracker_version: "test"
        },
        overrides
      )

    :ok = Nodes.track(node_name, info)
    assert eventually(fn -> Nodes.connected?(node_name) end)
    node_name
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end

  defp node_name, do: "node-#{TuistTestSupport.Utilities.unique_integer()}"

  defp new_sandbox(template, opts \\ []) do
    sandbox_fixture(Keyword.merge([template: template, state: :creating, node_name: nil, memory_mb: 4096], opts))
  end

  describe "charge and budget arithmetic" do
    test "charges guest memory plus the VMM overhead and keeps a daemon reserve" do
      assert Capacity.charge_bytes(%{memory_mb: 4096}) == 4096 * @mib + 64 * @mib
      assert Capacity.pause_bytes(%{memory_mb: 4096}) == 4096 * @mib
      assert Capacity.memory_budget_bytes(%{capacity: %{memory_bytes: 20 * @gib}}) == 20 * @gib - 512 * @mib
      assert Capacity.memory_budget_bytes(%{capacity: %{}}) == :unbounded
    end

    test "reserved_bytes/1 counts creating, resuming and running sandboxes on the node only", %{template: template} do
      node = node_name()
      sandbox_fixture(template: template, state: :creating, node_name: node, memory_mb: 1024)
      sandbox_fixture(template: template, state: :resuming, node_name: node, memory_mb: 2048)
      sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096)
      sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 8192)
      sandbox_fixture(template: template, state: :error, node_name: node, memory_mb: 8192)
      sandbox_fixture(template: template, state: :running, node_name: node_name(), memory_mb: 8192)

      assert Capacity.reserved_bytes(node) == (1024 + 2048 + 4096) * @mib + 3 * 64 * @mib
    end
  end

  describe "place/1" do
    test "reserves the ready node with the most free memory", %{template: template} do
      busy = connect(node_name(), template)
      free = connect(node_name(), template)
      sandbox_fixture(template: template, state: :running, node_name: busy, memory_mb: 8192)
      sandbox = new_sandbox(template)

      assert {:ok, ^free} = Capacity.place(sandbox)
      assert %Sandbox{node_name: ^free, state: :creating} = Repo.reload!(sandbox)
    end

    test "answers no_node when no connected node has the template ready", %{template: template} do
      connect(node_name(), template, %{templates: [%{name: template, tag: "sha-1", ready: false}]})
      connect(node_name(), "other-#{template}")

      assert {:error, :no_node} = Capacity.place(new_sandbox(template))
    end

    test "refuses a node the charge would overflow when nothing is reclaimable", %{template: template} do
      node = connect(node_name(), template)
      # 4 x (4096 + 64) MiB = 16.25 GiB on a 19.5 GiB budget: a fifth does not fit.
      for _ <- 1..4,
          do:
            sandbox_fixture(
              template: template,
              state: :running,
              node_name: node,
              residency_work_id: "work",
              memory_mb: 4096
            )

      reject(&Nodes.call/4)
      sandbox = new_sandbox(template)

      assert {:error, :no_capacity} = Capacity.place(sandbox)
      assert %Sandbox{node_name: nil} = Repo.reload!(sandbox)
    end

    test "pauses the longest idle sandboxes without a residency until the newcomer fits", %{template: template} do
      node = connect(node_name(), template)

      resident =
        sandbox_fixture(template: template, state: :running, node_name: node, residency_work_id: "work", memory_mb: 4096)

      recent =
        sandbox_fixture(
          template: template,
          state: :running,
          node_name: node,
          memory_mb: 4096,
          last_active_at: DateTime.utc_now()
        )

      old =
        sandbox_fixture(
          template: template,
          state: :running,
          node_name: node,
          memory_mb: 4096,
          last_active_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        )

      sandbox_fixture(template: template, state: :running, node_name: node, residency_work_id: "work2", memory_mb: 4096)
      old_id = old.id

      expect(Nodes, :call, fn ^node, "pause", %{sandbox_id: ^old_id}, _opts -> {:ok, %{}} end)
      sandbox = new_sandbox(template)

      assert {:ok, ^node} = Capacity.place(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(old)
      assert %Sandbox{state: :running} = Repo.reload!(recent)
      assert %Sandbox{state: :running} = Repo.reload!(resident)
    end

    test "does not budget a node that reports no capacity", %{template: template} do
      node = connect(node_name(), template, %{capacity: %{}})
      for _ <- 1..8, do: sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 16_384)

      assert {:ok, ^node} = Capacity.place(new_sandbox(template))
    end

    test "skips nodes whose disk cannot take another memory image or exceeds the sandbox budget", %{template: template} do
      full_fs =
        connect(node_name(), template, %{disk: %{available_bytes: 4 * @gib, sandboxes_bytes: 0, budget_bytes: 0}})

      over_budget =
        connect(node_name(), template, %{
          disk: %{available_bytes: 500 * @gib, sandboxes_bytes: 98 * @gib, budget_bytes: 100 * @gib}
        })

      roomy =
        connect(node_name(), template, %{
          disk: %{available_bytes: 500 * @gib, sandboxes_bytes: 1 * @gib, budget_bytes: 100 * @gib}
        })

      sandbox_fixture(template: template, state: :running, node_name: roomy, memory_mb: 4096)

      assert {:ok, ^roomy} = Capacity.place(new_sandbox(template))
      refute full_fs == roomy
      refute over_budget == roomy
    end

    test "answers no_capacity when every ready node is out of disk", %{template: template} do
      connect(node_name(), template, %{disk: %{available_bytes: 1 * @gib, sandboxes_bytes: 0, budget_bytes: 0}})

      assert {:error, :no_capacity} = Capacity.place(new_sandbox(template))
    end
  end

  describe "admit/1" do
    test "marks the sandbox resuming when it fits its node", %{template: template} do
      node = connect(node_name(), template)
      sandbox = sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 4096)

      assert {:ok, %Sandbox{state: :resuming}} = Capacity.admit(sandbox)
      assert Capacity.reserved_bytes(node) == Capacity.charge_bytes(sandbox)
    end

    test "pauses an idle sandbox on the node to make room", %{template: template} do
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 9 * @gib, cpus: 4}})
      idle = sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096)
      sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096, residency_work_id: "work")
      sandbox = sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 4096)
      idle_id = idle.id

      expect(Nodes, :call, fn ^node, "pause", %{sandbox_id: ^idle_id}, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :resuming}} = Capacity.admit(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(idle)
    end

    test "refuses when the node is full of resident sandboxes", %{template: template} do
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 9 * @gib, cpus: 4}})

      for work <- ["w1", "w2"],
          do:
            sandbox_fixture(
              template: template,
              state: :running,
              node_name: node,
              memory_mb: 4096,
              residency_work_id: work
            )

      sandbox = sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 4096)
      reject(&Nodes.call/4)

      assert {:error, :no_capacity} = Capacity.admit(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
    end

    test "marks the sandbox resuming without budgeting when its node is not connected", %{template: template} do
      sandbox = sandbox_fixture(template: template, state: :paused, node_name: node_name(), memory_mb: 4096)

      assert {:ok, %Sandbox{state: :resuming}} = Capacity.admit(sandbox)
    end
  end

  describe "admissible?/2" do
    test "is true for a session whose sandbox already holds memory", %{template: template} do
      agent_environment = agent_environment_fixture(template: template)
      sandbox_fixture(agent_environment_id: agent_environment.id, anthropic_session_id: "sesn_running", state: :running)

      assert Capacity.admissible?(agent_environment, "sesn_running")
    end

    test "is false for a new session when the only ready node is full of resident sandboxes", %{template: template} do
      agent_environment = agent_environment_fixture(template: template, memory_mb: 4096)
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 9 * @gib, cpus: 4}})

      for work <- ["w1", "w2"],
          do:
            sandbox_fixture(
              template: template,
              state: :running,
              node_name: node,
              memory_mb: 4096,
              residency_work_id: work
            )

      refute Capacity.admissible?(agent_environment, "sesn_new")
    end

    test "is true when idle sandboxes could be paused for room", %{template: template} do
      agent_environment = agent_environment_fixture(template: template, memory_mb: 4096)
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 9 * @gib, cpus: 4}})
      sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096)
      sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096, residency_work_id: "work")

      assert Capacity.admissible?(agent_environment, "sesn_new")
    end

    test "is true for a paused sandbox whose node has room and false when it has none", %{template: template} do
      agent_environment = agent_environment_fixture(template: template, memory_mb: 4096)
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 9 * @gib, cpus: 4}})

      sandbox_fixture(
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "sesn_paused",
        state: :paused,
        node_name: node
      )

      assert Capacity.admissible?(agent_environment, "sesn_paused")

      for work <- ["w1", "w2"],
          do:
            sandbox_fixture(
              template: template,
              state: :running,
              node_name: node,
              memory_mb: 4096,
              residency_work_id: work
            )

      refute Capacity.admissible?(agent_environment, "sesn_paused")
    end

    test "is true when no node is ready at all, so dispatch reports the missing node", %{template: template} do
      agent_environment = agent_environment_fixture(template: template)

      assert Capacity.admissible?(agent_environment, "sesn_new")
    end
  end
end
