defmodule Tuist.Sandboxes.MacosCapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.MacosCapacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxEvent

  setup do
    name = "mac-#{System.unique_integer([:positive])}"

    node = %{
      name: name,
      platform: "darwin",
      generation: "node-uid",
      control_uid: "control-uid",
      capacity: %{memory_bytes: 24 * 1024 * 1024 * 1024, cpus: 8},
      templates: [%{name: "macos", ready: true, tag: "image@sha256:abc"}],
      admission: %{
        "allow" => true,
        "memory_bytes" => 24 * 1024 * 1024 * 1024,
        "cpu_milli" => 8000,
        "slots" => 2,
        "node_uid" => "node-uid",
        "control_uid" => "control-uid",
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
      }
    }

    stub(Nodes, :connected_nodes, fn -> [node] end)
    stub(Nodes, :lookup, fn ^name -> {:ok, self(), node} end)
    %{node: node}
  end

  defp sandbox(opts \\ []) do
    sandbox_fixture(
      Keyword.merge(
        [platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192, node_name: nil, state: :creating],
        opts
      )
    )
  end

  test "placement atomically records ownership and retains paused VM charges", %{node: node} do
    first = sandbox()
    assert {:ok, name} = Capacity.place(first)
    assert name == node.name
    assert %{node_uid: "node-uid", resident: true} = Repo.reload!(first)
    assert {:error, :no_capacity} = Capacity.place(sandbox())

    first |> Repo.reload!() |> Ecto.Changeset.change(state: :paused) |> Repo.update!()
    assert {:error, :no_capacity} = Capacity.place(sandbox())
    assert {:ok, %{state: :resuming}} = Capacity.admit(Repo.reload!(first))

    first |> Repo.reload!() |> Ecto.Changeset.change(state: :paused, resident: false) |> Repo.update!()
    assert {:ok, _} = Capacity.place(sandbox())
  end

  test "a Claude Code snapshot builder is placed only on a host whose granted slots are both free", %{node: node} do
    environment =
      agent_environment_fixture(
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01macos",
        platform: :darwin,
        template: "macos",
        vcpus: 8,
        memory_mb: 8192,
        setup_script: "brew bundle\n"
      )

    {:ok, build} = DiskSnapshots.start_build(environment, "acme/app", "sha")
    builder = sandbox(id: build.id, vcpus: 4, memory_mb: 4096)

    one_slot = %{node | admission: Map.put(node.admission, "slots", 1)}
    stub(Nodes, :connected_nodes, fn -> [one_slot] end)
    assert {:error, :no_capacity} = Capacity.place(builder)

    stub(Nodes, :connected_nodes, fn -> [node] end)
    session = sandbox(vcpus: 4, memory_mb: 4096)
    assert {:ok, _name} = Capacity.place(session)
    assert {:error, :no_capacity} = Capacity.place(builder)

    session |> Repo.reload!() |> Repo.delete!()
    assert {:ok, name} = Capacity.place(builder)
    assert name == node.name
  end

  test "placement prefers a host with a warm VM of the requested shape", %{node: node} do
    cold = %{node | name: "cold-#{System.unique_integer([:positive])}"}
    warm_template = %{name: "macos", ready: true, tag: "image@sha256:abc", warm: ["8x8192"]}
    warm = %{node | templates: [warm_template]}
    odd = %{node | name: "odd-#{System.unique_integer([:positive])}", templates: [%{warm_template | warm: ["8x16384"]}]}

    stub(Nodes, :connected_nodes, fn -> [cold, odd, warm] end)
    stub(Nodes, :lookup, fn name -> {:ok, self(), Enum.find([cold, odd, warm], &(&1.name == name))} end)

    assert {:ok, name} = Capacity.place(sandbox())
    assert name == warm.name
  end

  test "placement spreads creates across hosts by free slots, not host name", %{node: node} do
    # Sorted by name, ber1's hosts come before larch's.
    ber1 = %{node | name: "tuist-tuist-rack-fleet-ber1-runner-b03"}
    larch = %{node | name: "tuist-tuist-rack-fleet-larch-runner-b03"}
    nodes = [ber1, larch]
    stub(Nodes, :connected_nodes, fn -> nodes end)
    stub(Nodes, :lookup, fn name -> {:ok, self(), Enum.find(nodes, &(&1.name == name))} end)

    # Two idle hosts with two slots each take one sandbox each.
    assert {:ok, first} = Capacity.place(sandbox(vcpus: 4))
    assert {:ok, second} = Capacity.place(sandbox(vcpus: 4))
    assert Enum.sort([first, second]) == [ber1.name, larch.name]

    # A host already holding a VM is tried after an idle one, whatever its
    # name, and the log tells the sites' same-named hosts apart.
    Logger.put_module_level(MacosCapacity, :info)
    on_exit(fn -> Logger.delete_module_level(MacosCapacity) end)
    larch_name = larch.name
    Repo.delete_all(from(s in Sandbox, where: s.node_name == ^larch_name))

    log = capture_log([level: :info], fn -> assert {:ok, ^larch_name} = Capacity.place(sandbox(vcpus: 4)) end)
    assert log =~ "hosts=ber1/b03=not_tried larch/b03=chosen"
  end

  test "placement logs why a host holding a warm VM was not chosen", %{node: node} do
    Logger.put_module_level(MacosCapacity, :info)
    on_exit(fn -> Logger.delete_module_level(MacosCapacity) end)
    warm_template = %{name: "macos", ready: true, tag: "image@sha256:abc", warm: ["8x8192"]}
    warm = %{node | name: "rack-b04", templates: [warm_template], admission: Map.put(node.admission, "slots", 0)}
    stale = %{node | name: "rack-b05", admission: Map.put(node.admission, "observed_at", "2020-01-01T00:00:00Z")}
    cold = %{node | name: "rack-b06"}

    stub(Nodes, :connected_nodes, fn -> [cold, stale, warm] end)

    log = capture_log([level: :info], fn -> assert {:ok, "rack-b06"} = Capacity.place(sandbox()) end)

    assert log =~ "sandboxes: macOS placement"
    assert log =~ "shape=8x8192"
    assert log =~ "hosts=b04=warm:refused_no_capacity_no_slot b05=grant_stale b06=chosen"
  end

  test "turns on a running VM need no grant, even when CI closed it during the restore", %{node: node} do
    sandbox = sandbox(state: :paused, node_name: node.name, node_uid: "node-uid", resident: false)
    closed = %{node | admission: Map.put(node.admission, "allow", false)}
    restored = start_supervised!({Agent, fn -> false end})
    stub(Nodes, :lookup, fn _name -> {:ok, self(), if(Agent.get(restored, & &1), do: closed, else: node)} end)

    expect(Nodes, :call, fn _name, "resume", _args, _opts ->
      Agent.update(restored, fn _ -> true end)
      {:ok, %{"restore_ms" => 3000}}
    end)

    assert {:ok, %{state: :running, residency_work_id: "amp:orb"}} = Sandboxes.prepare_residency(sandbox, "amp:orb")
    # First come, first served: the running VM keeps its place for its next turn.
    assert {:ok, %{residency_work_id: "amp:other"}} = Sandboxes.begin_residency(Repo.reload!(sandbox), "amp:other")
  end

  test "CI revocation, stale grants and replaced control identities deny new work", %{node: node} do
    for grant <- [
          Map.put(node.admission, "allow", false),
          Map.put(node.admission, "observed_at", DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -16))),
          Map.put(node.admission, "control_uid", "replacement"),
          %{}
        ] do
      refute MacosCapacity.allowed?(%{node | admission: grant})
    end
  end

  test "a refused resume names why its own host can't take it", %{node: node} do
    stale = DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -16))

    for {host, why} <- [
          {%{node | admission: Map.put(node.admission, "allow", false)}, :ci},
          {%{node | admission: Map.put(node.admission, "observed_at", stale)}, :no_grant},
          {%{node | admission: Map.put(node.admission, "memory_bytes", 4 * 1024 * 1024 * 1024)}, :full},
          {:not_connected, :not_connected}
        ] do
      paused = sandbox(state: :paused, node_name: node.name, node_uid: node.generation, resident: true)

      stub(Nodes, :lookup, fn _name ->
        if host == :not_connected, do: {:error, :not_connected}, else: {:ok, self(), host}
      end)

      assert {:error, {:host_busy, ^why}} = Capacity.admit(paused)
      assert Repo.reload!(paused).state == :paused
      paused |> Repo.reload!() |> Ecto.Changeset.change(state: :deleted, resident: false) |> Repo.update!()
    end
  end

  test "a replacement Node cannot resume the previous owner's environment", %{node: node} do
    prior = sandbox(state: :paused, node_name: node.name, node_uid: "old-node", resident: false)
    assert {:error, {:host_busy, :replaced}} = Capacity.admit(prior)
    assert Repo.reload!(prior).state == :paused
  end

  test "placement respects the grant's remaining CI capacity, not the whole host", %{node: node} do
    for grant <- [
          Map.put(node.admission, "cpu_milli", 4000),
          Map.put(node.admission, "memory_bytes", 4096 * 1024 * 1024),
          Map.put(node.admission, "slots", 0),
          Map.delete(node.admission, "cpu_milli")
        ] do
      stub(Nodes, :connected_nodes, fn -> [%{node | admission: grant}] end)
      assert {:error, :no_capacity} = Capacity.place(sandbox())
    end
  end

  test "placement counts evicted environments against the disk the host reports", %{node: node} do
    gib = 1024 * 1024 * 1024
    rootfs = 101_000_000_000
    # What the host's diskRoom reserves for one 8 GiB environment.
    ceiling = rootfs + 2 * 8 * gib + 128 * 1024 * 1024
    templates = [%{name: "macos", ready: true, tag: "image@sha256:abc", rootfs_bytes: rootfs}]
    disk = %{budget_bytes: 2 * ceiling + gib, available_bytes: 500 * gib}
    full = Map.merge(node, %{name: "a-#{System.unique_integer([:positive])}", templates: templates, disk: disk})

    roomy = %{full | name: "b-#{System.unique_integer([:positive])}", disk: %{disk | budget_bytes: 10 * ceiling}}

    nodes = [full, roomy]
    stub(Nodes, :lookup, fn name -> {:ok, self(), Enum.find(nodes, &(&1.name == name))} end)

    # One evicted environment still leaves room for a second.
    stub(Nodes, :connected_nodes, fn -> [full] end)
    sandbox(state: :paused, node_name: full.name, node_uid: node.generation, resident: false)
    first = sandbox()
    assert {:ok, name} = Capacity.place(first)
    assert name == full.name
    first |> Repo.reload!() |> Ecto.Changeset.change(state: :paused, resident: false) |> Repo.update!()
    stub(Nodes, :connected_nodes, fn -> nodes end)

    # Two evicted environments hold none of the grant's slots, but their disks fill the budget.
    assert {:ok, name} = Capacity.place(sandbox())
    assert name == roomy.name

    # Free space below two memory images and 20 GiB rules a host out too.
    low = %{roomy | disk: %{roomy.disk | available_bytes: 2 * 8 * gib + 19 * gib}}
    stub(Nodes, :connected_nodes, fn -> [full, low] end)
    assert {:error, :no_capacity} = Capacity.place(sandbox())

    # A host that reports no disk (an older tart-kubelet) is not budgeted.
    stub(Nodes, :connected_nodes, fn -> [%{full | disk: %{}}] end)
    assert {:ok, _name} = Capacity.place(sandbox())
  end

  test "a create the host refuses moves on to the next host", %{node: node} do
    refusing = %{node | name: "b-#{System.unique_integer([:positive])}"}
    # One granted slot to the refusing host's two, so it is tried second.
    accepting = %{node | name: "a-#{System.unique_integer([:positive])}", generation: "other-uid"}
    accepting = update_in(accepting.admission, &Map.merge(&1, %{"node_uid" => "other-uid", "slots" => 1}))
    nodes = [refusing, accepting]
    stub(Nodes, :connected_nodes, fn -> nodes end)
    stub(Nodes, :lookup, fn name -> {:ok, self(), Enum.find(nodes, &(&1.name == name))} end)

    refusing_name = refusing.name
    accepting_name = accepting.name

    expect(Nodes, :call, 2, fn
      ^refusing_name, "create", %{node_uid: "node-uid"}, _opts ->
        {:error, "macOS sandbox capacity unavailable: sandbox disk reserve"}

      ^accepting_name, "create", %{node_uid: "other-uid"}, _opts ->
        {:ok, %{}}
    end)

    assert {:ok, created} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})
    assert %{state: :running, node_uid: "other-uid"} = created
    assert created.node_name == accepting.name

    # A refusal whose cleanup also failed is not only a refusal.
    error = "macOS sandbox capacity unavailable: sandbox disk reserve\nreservation release failed"

    expect(Nodes, :call, 2, fn
      _name, "create", _args, _opts -> {:error, error}
      _name, "delete", _args, _opts -> {:ok, %{}}
    end)

    assert {:error, ^error} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})
  end

  test "a failed create is deleted from its host at once and holds nothing there", %{node: node} do
    name = node.name
    error = "workspace: diskutil apfs addVolume disk3 APFS TuistSandboxWorkspace: exit status 1"

    expect(Nodes, :call, 2, fn
      ^name, "create", %{node_uid: "node-uid"}, _opts -> {:error, error}
      ^name, "delete", %{sandbox_id: _id, node_uid: "node-uid"}, _opts -> {:ok, %{}}
    end)

    assert {:error, ^error} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})

    failed = Repo.one!(from(s in Sandbox, where: s.platform == :darwin and s.state == :error))
    assert %{node_name: nil, node_uid: nil, resident: false, error_message: ^error} = failed

    # The host had room for one 8-vCPU VM: the failed create no longer takes it.
    expect(Nodes, :call, fn ^name, "create", _args, _opts -> {:ok, %{}} end)
    assert {:ok, created} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})
    assert %{state: :running, node_name: ^name} = created

    # The failure is kept on its `failed` event, which outlives the row.
    assert [%{error_message: ^error, node_name: ^name, template: "macos"}] =
             ClickHouseRepo.all(from(e in SandboxEvent, where: e.sandbox_id == ^failed.id and e.event == "failed"))
  end

  test "a failed create its host could not delete is deleted when the host reports it", %{node: node} do
    name = node.name

    expect(Nodes, :call, 2, fn
      ^name, "create", _args, _opts -> {:error, :timeout}
      ^name, "delete", _args, _opts -> {:error, :not_connected}
    end)

    assert {:error, :timeout} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})
    failed = Repo.one!(from(s in Sandbox, where: s.platform == :darwin and s.state == :error))
    assert %{node_name: ^name, resident: true} = failed
    assert {:error, :no_capacity} = Capacity.place(sandbox())

    failed_id = failed.id
    expect(Nodes, :call, fn ^name, "delete", %{sandbox_id: ^failed_id, node_uid: "node-uid"}, _opts -> {:ok, %{}} end)

    report = %{
      "generation" => node.generation,
      "sandboxes" => [%{"id" => failed.id, "state" => "error", "resident" => false, "error" => "lost"}]
    }

    assert :ok = Sandboxes.reconcile_node_report(name, report)
    assert %{state: :error, node_name: nil, resident: false} = Repo.reload!(failed)
    assert {:ok, ^name} = Capacity.place(sandbox())
  end

  test "errored rows the host no longer lists stop holding it", %{node: node} do
    old = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
    held = [node_name: node.name, node_uid: node.generation, state: :error, resident: true]

    errored = fn opts ->
      held |> Keyword.merge(opts) |> sandbox() |> Ecto.Changeset.change(updated_at: old) |> Repo.update!()
    end

    never_ran = errored.([])
    used = errored.(last_active_at: old)
    other_host = errored.(node_uid: "replaced-uid")
    just_failed = sandbox(held)

    assert :ok = Sandboxes.reconcile_node_report(node.name, %{"generation" => node.generation, "sandboxes" => []})

    # The retention still counts from the failure.
    assert %{node_name: nil, node_uid: nil, resident: false, updated_at: ^old} = Repo.reload!(never_ran)
    assert %{node_name: name, resident: false, state: :error} = Repo.reload!(used)
    assert name == node.name
    # Another incarnation of the host says nothing about it, and a report can
    # predate a failure that just happened.
    assert %{resident: true} = Repo.reload!(other_host)
    assert %{resident: true} = Repo.reload!(just_failed)
  end

  test "an errored session sandbox without a node is replaced, a placed one needs recovery", %{node: node} do
    environment = agent_environment_fixture(platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192)
    session_id = "sesn_#{System.unique_integer([:positive])}"
    name = node.name

    placed =
      sandbox(
        agent_environment_id: environment.id,
        anthropic_session_id: session_id,
        state: :error,
        node_name: name,
        node_uid: node.generation
      )

    assert {:error, :sandbox_recovery_required} = Router.find_or_create_sandbox(environment, session_id)

    placed |> Ecto.Changeset.change(node_name: nil, node_uid: nil) |> Repo.update!()
    assert :ok = MacosCapacity.admission(environment, session_id)

    expect(Nodes, :call, fn ^name, "create", _args, _opts -> {:ok, %{}} end)
    assert {:ok, created, true} = Router.find_or_create_sandbox(environment, session_id)
    assert %{state: :running, node_name: ^name} = created
    refute Repo.get(Sandbox, placed.id)
  end

  test "Linux placement never chooses a macOS node advertising the same template" do
    assert Capacity.ready_nodes("macos") == []
  end

  test "native creation respects account quotas before requesting a VM" do
    account = account_fixture()
    {:ok, account} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 4, sandbox_memory_gb_limit: 8})
    reject(&Nodes.call/4)

    assert {:error, :sandbox_concurrency_limit} = Sandboxes.create_sandbox(account, %{platform: :darwin})
    assert Concurrency.usage(account.id) == %{vcpus: 0.0, memory_mb: 0}
  end

  test "resident and evicted resumes acquire the account quota again", %{node: node} do
    for resident <- [true, false] do
      account = account_fixture()
      {:ok, account} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 8, sandbox_memory_gb_limit: 8})

      environment =
        agent_environment_fixture(account: account, platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192)

      held = sandbox(account: account, state: :running, node_name: "another-node")

      paused =
        sandbox(
          account: account,
          state: :paused,
          node_name: node.name,
          node_uid: node.generation,
          resident: resident,
          agent_environment_id: environment.id,
          anthropic_session_id: "session"
        )

      refute Capacity.admissible?(environment, "session")
      refute Capacity.admissible?(environment, "new-session")
      assert {:error, :sandbox_concurrency_limit} = Capacity.admit(paused)
      assert Repo.reload!(paused).state == :paused
      assert Repo.reload!(paused).resident == resident

      held |> Ecto.Changeset.change(state: :paused) |> Repo.update!()
      assert {:ok, %{state: :resuming}} = Capacity.admit(paused)
      assert Concurrency.usage(account.id) == %{vcpus: 8.0, memory_mb: 8192}
      paused |> Repo.reload!() |> Ecto.Changeset.change(state: :paused, resident: false) |> Repo.update!()
    end
  end

  test "CI revocation after resume admission keeps the checkpoint retryable", %{node: node} do
    for resident <- [false, true] do
      paused = sandbox(state: :paused, node_name: node.name, node_uid: node.generation, resident: resident)

      expect(Nodes, :call, fn _name, "resume", _args, _opts ->
        assert Repo.reload!(paused).state == :resuming
        {:error, "macOS sandbox capacity unavailable"}
      end)

      assert {:error, {:host_busy, :ci}} = Sandboxes.resume(paused)
      assert %{state: :paused, resident: true, error_message: nil} = Repo.reload!(paused)
      assert Concurrency.usage(paused.account_id) == %{vcpus: 0.0, memory_mb: 0}

      assert :ok =
               Sandboxes.reconcile_node_report(node.name, %{
                 "generation" => node.generation,
                 "sandboxes" => [%{"id" => paused.id, "state" => "paused", "resident" => resident}]
               })

      assert Repo.reload!(paused).resident == resident
      expect(Nodes, :call, fn _name, "resume", _args, _opts -> {:ok, %{"restore_ms" => 10}} end)
      assert {:ok, %{state: :running}} = Sandboxes.resume(paused)
      paused |> Repo.reload!() |> Ecto.Changeset.change(state: :deleted, resident: false) |> Repo.update!()
    end
  end

  test "a capacity denial with uncertain cleanup remains an error", %{node: node} do
    paused = sandbox(state: :paused, node_name: node.name, node_uid: node.generation)
    error = "macOS sandbox capacity unavailable\nreservation release failed"
    expect(Nodes, :call, fn _name, "resume", _args, _opts -> {:error, error} end)

    assert {:error, ^error} = Sandboxes.resume(paused)
    assert %{state: :error, resident: true, error_message: ^error} = Repo.reload!(paused)
  end

  test "create and pause route through the recorded owner with authenticated protocol fields", %{node: node} do
    expect(Nodes, :call, fn name, "create", args, _opts ->
      assert name == node.name
      assert args.node_uid == "node-uid"
      {:ok, %{"template_tag" => "image@sha256:abc"}}
    end)

    assert {:ok, created} =
             Sandboxes.create_sandbox(account_fixture(), %{
               platform: :darwin,
               template: "macos",
               vcpus: 8,
               memory_mb: 8192
             })

    assert created.platform == :darwin
    assert created.node_uid == "node-uid"
    assert Sandboxes.workspace(created) == "/Users/runner/work"
    expect(Nodes, :call, fn _name, "pause", %{node_uid: "node-uid"}, _opts -> {:ok, %{"resident" => true}} end)
    assert {:ok, %{state: :paused, resident: true}} = Sandboxes.pause(created)
  end

  test "platform-only create uses the native template and shape", %{node: node} do
    expect(Nodes, :call, fn name, "create", args, _opts ->
      assert name == node.name
      assert %{template: "macos", vcpus: 8, memory_mb: 8192, node_uid: "node-uid"} = args
      {:ok, %{}}
    end)

    assert {:ok, %{platform: :darwin, vcpus: 8}} = Sandboxes.create_sandbox(account_fixture(), %{platform: :darwin})
  end

  test "completion reports recover a lost event but cannot end a newer turn", %{node: node} do
    sandbox = sandbox(state: :running, node_name: node.name, node_uid: node.generation, resident: true)
    sandbox = sandbox |> Ecto.Changeset.change(residency_work_id: "work-new", residency_epoch: 5) |> Repo.update!()

    report = %{
      "generation" => node.generation,
      "sandboxes" => [%{"id" => sandbox.id, "state" => "running", "resident" => true, "finished_work_id" => "work-old"}]
    }

    assert :ok = Sandboxes.reconcile_node_report(node.name, report)
    assert Repo.reload!(sandbox).residency_work_id == "work-new"

    report =
      put_in(report, ["sandboxes"], [
        %{"id" => sandbox.id, "state" => "running", "resident" => true, "finished_work_id" => "work-new"}
      ])

    assert :ok = Sandboxes.reconcile_node_report(node.name, report)
    assert Repo.reload!(sandbox).residency_work_id == nil
  end

  test "replaced node reports and death events cannot mutate prior ownership", %{node: node} do
    sandbox = sandbox(state: :running, node_name: node.name, node_uid: node.generation, resident: true)
    assert :ok = Sandboxes.reconcile_node_report(node.name, %{"generation" => "replacement", "sandboxes" => []})

    assert :ok =
             Sandboxes.handle_node_event(node.name, %{
               "event" => "sandbox_died",
               "sandbox_id" => sandbox.id,
               "generation" => "replacement"
             })

    assert Repo.reload!(sandbox).state == :running
  end

  test "admission names why each host cannot take a session's work item", %{node: node} do
    environment = agent_environment_fixture(platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192)
    stale = DateTime.utc_now() |> DateTime.add(-20, :second) |> DateTime.to_iso8601()

    hosts = %{
      "building" => %{node | templates: [%{name: "macos", ready: false, tag: "t"}]},
      "other-template" => %{node | templates: [%{name: "linux", ready: true, tag: "t"}]},
      "stale" => put_in(node.admission["observed_at"], stale),
      "denied" => put_in(node.admission["allow"], false),
      "replaced" => put_in(node.admission["node_uid"], "old-node-uid"),
      # What tart-kubelet forwards for a Node without a grant annotation.
      "ungranted" => %{
        node
        | admission: %{
            "node_uid" => "",
            "control_uid" => "",
            "observed_at" => "0001-01-01T00:00:00Z",
            "allow" => false,
            "slots" => 0
          }
      },
      "full" => put_in(node.admission["slots"], 0)
    }

    stub(Nodes, :connected_nodes, fn -> Enum.map(hosts, fn {name, host} -> Map.put(host, :name, name) end) end)

    assert {:error,
            {:no_node,
             %{
               "building" => :template_not_ready,
               "other-template" => :no_template,
               "stale" => :grant_stale,
               "denied" => :grant_denied,
               "replaced" => :grant_mismatch,
               "ungranted" => :no_grant,
               "full" => :no_room
             }}} = Capacity.admission(environment, "new-session")

    stub(Nodes, :connected_nodes, fn -> [node | Enum.map(hosts, fn {name, host} -> Map.put(host, :name, name) end)] end)
    assert :ok = Capacity.admission(environment, "new-session")

    stub(Nodes, :lookup, fn _name -> {:error, :not_connected} end)

    sandbox(
      state: :paused,
      node_name: node.name,
      node_uid: node.generation,
      agent_environment_id: environment.id,
      anthropic_session_id: "paused-session"
    )

    assert {:error, {node_name, :not_connected}} = Capacity.admission(environment, "paused-session")
    assert node_name == node.name

    # An archived session's sandbox left its host, so any host with room admits it.
    sandbox(
      state: :archived,
      agent_environment_id: environment.id,
      anthropic_session_id: "archived-session",
      archive_key: "k",
      archived_at: DateTime.utc_now()
    )

    assert :ok = Capacity.admission(environment, "archived-session")
    stub(Nodes, :connected_nodes, fn -> [put_in(node.admission["slots"], 0)] end)
    assert {:error, {:no_node, %{}}} = Capacity.admission(environment, "archived-session")
  end
end
