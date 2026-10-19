defmodule Tuist.Sandboxes.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxNode

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

    test "skips nodes whose filesystem cannot take another memory image or whose budget cannot take the ceiling",
         %{template: template} do
      templates = [%{name: template, tag: "sha-1", ready: true, rootfs_bytes: 8 * @gib}]

      full_fs =
        connect(node_name(), template, %{templates: templates, disk: %{available_bytes: 4 * @gib, budget_bytes: 0}})

      # One paused sandbox of 8 + 10 + 4 GiB leaves no room for a second
      # under a 30 GiB budget, however little either has written.
      over_budget =
        connect(node_name(), template, %{
          templates: templates,
          disk: %{available_bytes: 500 * @gib, budget_bytes: 30 * @gib, sandboxes_bytes: 0}
        })

      sandbox_fixture(template: template, state: :paused, node_name: over_budget, memory_mb: 4096, workspace_gb: 10)

      roomy =
        connect(node_name(), template, %{
          templates: templates,
          disk: %{available_bytes: 500 * @gib, budget_bytes: 100 * @gib}
        })

      sandbox_fixture(template: template, state: :running, node_name: roomy, memory_mb: 4096)

      assert {:ok, ^roomy} = Capacity.place(new_sandbox(template))
      refute full_fs == roomy
      refute over_budget == roomy
    end

    test "reserves the ceilings of placed sandboxes and of errored ones the node still reports, not of deleted ones",
         %{template: template} do
      templates = [%{name: template, tag: "sha-1", ready: true, rootfs_bytes: 8 * @gib}]

      node =
        connect(node_name(), template, %{
          templates: templates,
          disk: %{available_bytes: 500 * @gib, budget_bytes: 50 * @gib}
        })

      for state <- [:creating, :paused] do
        sandbox_fixture(template: template, state: state, node_name: node, memory_mb: 4096, workspace_gb: 10)
      end

      errored_on_disk =
        sandbox_fixture(template: template, state: :error, node_name: node, memory_mb: 4096, workspace_gb: 10)

      sandbox_fixture(template: template, state: :error, node_name: node, memory_mb: 4096, workspace_gb: 10)

      {:ok, _pid, info} = Nodes.lookup(node)

      # The report still lists a sandbox deleted a moment ago, and the
      # errored sandbox whose jail is on disk; only the latter counts.
      info =
        info
        |> Map.put(:name, node)
        |> Map.put(:sandboxes, [
          %{id: Ecto.UUID.generate(), template: template, memory_mb: 4096, workspace_gb: 10},
          %{id: errored_on_disk.id, template: template, memory_mb: 4096, workspace_gb: 10}
        ])

      ceiling = 8 * @gib + 10 * @gib + 4 * @gib + 64 * @mib
      assert Capacity.reserved_disk_bytes(info) == 3 * ceiling

      assert {:error, :no_capacity} = Capacity.place(new_sandbox(template))
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

    test "resumes a paused sandbox on a node whose disk budget is fully reserved, since its disk already is",
         %{template: template} do
      templates = [%{name: template, tag: "sha-1", ready: true, rootfs_bytes: 8 * @gib}]

      node =
        connect(node_name(), template, %{
          templates: templates,
          disk: %{available_bytes: 500 * @gib, budget_bytes: 20 * @gib}
        })

      sandbox = sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 4096, workspace_gb: 10)

      assert {:ok, %Sandbox{state: :resuming}} = Capacity.admit(sandbox)
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

  describe "elastic carve-outs" do
    setup do
      # The Pod status reads as a resize still in flight unless a test says
      # the kubelet applied or deferred it.
      stub(KubernetesClient, :get_pod, fn _namespace, _pod -> {:ok, %{"status" => %{}}} end)
      :ok
    end

    # Floor 8 GiB, ceiling 16 GiB; the daemon reports the floor until the
    # stubbed resize applies a new limit, as the kubelet would.
    defp connect_elastic(template, overrides \\ %{}) do
      name = node_name()

      elastic =
        Map.merge(
          %{pod_name: "sandboxd-#{name}", memory_floor_bytes: 8 * @gib, memory_ceiling_bytes: 16 * @gib},
          Map.get(overrides, :elastic, %{})
        )

      connect(
        name,
        template,
        Map.merge(%{capacity: %{memory_bytes: 8 * @gib, cpus: 16}}, Map.put(overrides, :elastic, elastic))
      )
    end

    defp resident(template, node, memory_mb \\ 4096) do
      sandbox_fixture(
        template: template,
        state: :running,
        node_name: node,
        residency_work_id: "w#{TuistTestSupport.Utilities.unique_integer()}",
        memory_mb: memory_mb
      )
    end

    # The kubelet applying the resize: the daemon reports the new limit.
    defp apply_resizes(node) do
      stub(KubernetesClient, :resize_sandbox_daemon_memory, fn "tuist-sandboxes", "sandboxd-" <> ^node, bytes ->
        :ok = Nodes.update(node, %{capacity: %{memory_bytes: bytes, cpus: 16}})
        {:ok, %{}}
      end)
    end

    defp node_info(node) do
      {:ok, _pid, info} = Nodes.lookup(node)
      Map.put(info, :name, node)
    end

    test "grows the carve-out in whole GiB when nothing fits and places into it", %{template: template} do
      node = connect_elastic(template)
      resident(template, node)
      apply_resizes(node)
      sandbox = new_sandbox(template)

      # Two 4160 MiB guests plus the 512 MiB reserve need 8.63 GiB.
      assert {:ok, ^node} = Capacity.place(sandbox)
      assert %Sandbox{node_name: ^node} = Repo.reload!(sandbox)
      assert %SandboxNode{memory_limit_bytes: limit, pod_name: "sandboxd-" <> ^node} = Repo.get(SandboxNode, node)
      assert limit == 9 * @gib
      assert Capacity.memory_limit_bytes(node_info(node)) == 9 * @gib
    end

    test "pauses idle sandboxes before it grows", %{template: template} do
      node = connect_elastic(template)
      idle = sandbox_fixture(template: template, state: :running, node_name: node, memory_mb: 4096)
      idle_id = idle.id
      expect(Nodes, :call, fn ^node, "pause", %{sandbox_id: ^idle_id}, _opts -> {:ok, %{}} end)
      reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

      assert {:ok, ^node} = Capacity.place(new_sandbox(template))
      assert %Sandbox{state: :paused} = Repo.reload!(idle)
    end

    test "refuses without resizing when the ceiling cannot hold the newcomer", %{template: template} do
      node = connect_elastic(template)
      for _ <- 1..3, do: resident(template, node)
      reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

      # 4 x 4160 MiB + 512 MiB is past the 16 GiB ceiling.
      assert {:error, :no_capacity} = Capacity.place(new_sandbox(template))
      refute Repo.get(SandboxNode, node)
    end

    test "leaves a growth the kubelet defers asked for and refuses the placement meanwhile", %{template: template} do
      node = connect_elastic(template)
      resident(template, node)
      expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _namespace, _pod, _bytes -> {:ok, %{}} end)
      stub(KubernetesClient, :get_pod, fn _namespace, _pod -> {:ok, %{"status" => deferred_status()}} end)
      sandbox = new_sandbox(template)

      assert {:error, :no_capacity} = Capacity.place(sandbox)
      assert %Sandbox{node_name: nil} = Repo.reload!(sandbox)
      assert %SandboxNode{memory_limit_bytes: limit} = Repo.get(SandboxNode, node)
      assert limit == 9 * @gib
      # Budgeted against what the node reports until the growth lands.
      assert Capacity.memory_limit_bytes(node_info(node)) == 8 * @gib
    end

    test "does not grow a node whose daemon reports no ceiling above its floor", %{template: template} do
      node = connect(node_name(), template, %{capacity: %{memory_bytes: 8 * @gib, cpus: 16}})
      resident(template, node)
      reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

      assert {:error, :no_capacity} = Capacity.place(new_sandbox(template))
    end

    test "grows the node a paused sandbox resumes on", %{template: template} do
      node = connect_elastic(template)
      resident(template, node)
      apply_resizes(node)
      paused = sandbox_fixture(template: template, state: :paused, node_name: node, memory_mb: 4096)

      assert {:ok, %Sandbox{state: :resuming}} = Capacity.admit(paused)
      assert Capacity.memory_limit_bytes(node_info(node)) == 9 * @gib
    end

    test "admits a work item once a growth for it is reported, and not before", %{template: template} do
      node = connect_elastic(template)
      resident(template, node)
      agent_environment = agent_environment_fixture(template: template)
      expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _namespace, _pod, _bytes -> {:ok, %{}} end)

      refute Capacity.admissible?(agent_environment, "sesn_new")

      apply_resizes(node)
      assert Capacity.admissible?(agent_environment, "sesn_new")
    end

    test "budgets against the size asked for while a shrink is pending, and ignores a row of an earlier Pod",
         %{template: template} do
      node = connect_elastic(template, %{capacity: %{memory_bytes: 12 * @gib, cpus: 16}})
      insert_row(node, "sandboxd-" <> node, 10 * @gib, nil)
      assert Capacity.memory_limit_bytes(node_info(node)) == 10 * @gib

      insert_row(node, "sandboxd-replaced", 9 * @gib, nil)
      assert Capacity.memory_limit_bytes(node_info(node)) == 12 * @gib
    end

    test "shrinks a grown carve-out to the floor once its sandboxes no longer need it", %{template: template} do
      node = connect_elastic(template, %{capacity: %{memory_bytes: 12 * @gib, cpus: 16}})
      insert_row(node, "sandboxd-" <> node, 12 * @gib, DateTime.add(DateTime.utc_now(), -600, :second))
      resident(template, node)
      target = 8 * @gib - 256 * @mib

      expect(Nodes, :call, fn ^node, "reclaim", %{target_bytes: ^target}, _opts -> {:ok, %{}} end)

      expect(KubernetesClient, :resize_sandbox_daemon_memory, fn "tuist-sandboxes", _pod, bytes ->
        assert bytes == 8 * @gib
        {:ok, %{}}
      end)

      assert {:ok, limit} = Capacity.shrink(node_info(node))
      assert limit == 8 * @gib
      assert %SandboxNode{memory_limit_bytes: ^limit} = Repo.get(SandboxNode, node)
    end

    test "keeps what running sandboxes need when it shrinks", %{template: template} do
      node = connect_elastic(template, %{capacity: %{memory_bytes: 16 * @gib, cpus: 16}})
      insert_row(node, "sandboxd-" <> node, 16 * @gib, DateTime.add(DateTime.utc_now(), -600, :second))
      for _ <- 1..2, do: resident(template, node)
      stub(Nodes, :call, fn ^node, "reclaim", _args, _opts -> {:ok, %{}} end)
      stub(KubernetesClient, :resize_sandbox_daemon_memory, fn _namespace, _pod, _bytes -> {:ok, %{}} end)

      # Two 4160 MiB guests plus the reserve round up to 9 GiB.
      assert {:ok, limit} = Capacity.shrink(node_info(node))
      assert limit == 9 * @gib
    end

    test "holds a carve-out grown a moment ago", %{template: template} do
      node = connect_elastic(template, %{capacity: %{memory_bytes: 12 * @gib, cpus: 16}})
      insert_row(node, "sandboxd-" <> node, 12 * @gib, DateTime.utc_now(:second))
      reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

      assert :unchanged = Capacity.shrink(node_info(node))
    end

    test "retries a shrink the kubelet has not applied yet", %{template: template} do
      node = connect_elastic(template, %{capacity: %{memory_bytes: 12 * @gib, cpus: 16}})
      insert_row(node, "sandboxd-" <> node, 8 * @gib, DateTime.add(DateTime.utc_now(), -600, :second))
      stub(Nodes, :call, fn ^node, "reclaim", _args, _opts -> {:ok, %{}} end)

      expect(KubernetesClient, :resize_sandbox_daemon_memory, fn _namespace, _pod, bytes ->
        assert bytes == 8 * @gib
        {:ok, %{}}
      end)

      assert {:ok, limit} = Capacity.shrink(node_info(node))
      assert limit == 8 * @gib
    end

    test "leaves a carve-out at its floor alone", %{template: template} do
      node = connect_elastic(template)
      insert_row(node, "sandboxd-" <> node, 8 * @gib, DateTime.add(DateTime.utc_now(), -600, :second))
      reject(&KubernetesClient.resize_sandbox_daemon_memory/3)

      assert :unchanged = Capacity.shrink(node_info(node))
    end

    defp deferred_status do
      %{"conditions" => [%{"type" => "PodResizePending", "status" => "True", "reason" => "Deferred"}]}
    end

    defp applied_status(quantity) do
      %{"containerStatuses" => [%{"name" => "sandboxd", "resources" => %{"limits" => %{"memory" => quantity}}}]}
    end

    test "moves on to the next node when the first defers its growth, and gives that growth back", %{
      template: template
    } do
      # The roomier ceiling puts `full` first.
      full = connect_elastic(template, %{elastic: %{memory_floor_bytes: 8 * @gib, memory_ceiling_bytes: 20 * @gib}})
      free = connect_elastic(template)
      resident(template, full)
      resident(template, free)
      test_pid = self()

      stub(KubernetesClient, :get_pod, fn "tuist-sandboxes", pod ->
        if pod == "sandboxd-" <> full, do: {:ok, %{"status" => deferred_status()}}, else: {:ok, %{"status" => %{}}}
      end)

      stub(KubernetesClient, :resize_sandbox_daemon_memory, fn "tuist-sandboxes", pod, bytes ->
        send(test_pid, {:resized, pod, bytes})
        if pod == "sandboxd-" <> free, do: :ok = Nodes.update(free, %{capacity: %{memory_bytes: bytes, cpus: 16}})
        {:ok, %{}}
      end)

      assert {:ok, ^free} = Capacity.place(new_sandbox(template))
      full_pod = "sandboxd-" <> full
      assert_received {:resized, ^full_pod, grown} when grown == 9 * @gib
      assert_received {:resized, ^full_pod, released} when released == 8 * @gib
      assert %SandboxNode{memory_limit_bytes: limit} = Repo.get(SandboxNode, full)
      assert limit == 8 * @gib
    end

    test "admits a work item once the kubelet applies its growth, before the daemon reports it", %{
      template: template
    } do
      node = connect_elastic(template)
      resident(template, node)
      agent_environment = agent_environment_fixture(template: template)
      stub(KubernetesClient, :resize_sandbox_daemon_memory, fn _namespace, _pod, _bytes -> {:ok, %{}} end)
      stub(KubernetesClient, :get_pod, fn _namespace, _pod -> {:ok, %{"status" => applied_status("9Gi")}} end)

      assert Capacity.admissible?(agent_environment, "sesn_new")
      # The placement still waits for the daemon to report the new limit.
      assert Capacity.memory_limit_bytes(node_info(node)) == 8 * @gib
    end

    test "a node at a 1 GiB floor holds no sandbox until a sandbox needs it", %{template: template} do
      node =
        connect_elastic(template, %{
          capacity: %{memory_bytes: @gib, cpus: 16},
          elastic: %{memory_floor_bytes: @gib, memory_ceiling_bytes: 16 * @gib}
        })

      apply_resizes(node)

      # One 4160 MiB guest plus the 512 MiB reserve rounds up to 5 GiB.
      assert {:ok, ^node} = Capacity.place(new_sandbox(template))
      assert Capacity.memory_limit_bytes(node_info(node)) == 5 * @gib
    end

    defp insert_row(node, pod_name, limit, grown_at) do
      %SandboxNode{}
      |> SandboxNode.changeset(%{name: node, pod_name: pod_name, memory_limit_bytes: limit, grown_at: grown_at})
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :name)
    end
  end
end
