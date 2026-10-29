defmodule Tuist.Sandboxes.MacosCapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.MacosCapacity
  alias Tuist.Sandboxes.Nodes

  setup do
    stub(FeatureFlags, :macos_sandboxes_enabled?, fn _ -> true end)
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

  test "a replacement Node cannot resume the previous owner's environment", %{node: node} do
    prior = sandbox(state: :paused, node_name: node.name, node_uid: "old-node", resident: false)
    assert {:error, :no_capacity} = Capacity.admit(prior)
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

  test "Linux placement never chooses a macOS node advertising the same template" do
    assert Capacity.ready_nodes("macos") == []
  end

  test "native creation respects account quotas before requesting a VM" do
    account = account_fixture()
    {:ok, account} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 4, sandbox_memory_gb_limit: 8})
    reject(&Nodes.call/4)

    assert {:error, :sandbox_concurrency_limit} = Sandboxes.create_sandbox(account, %{platform: :darwin})
    assert Concurrency.usage(account.id) == %{vcpus: 0, memory_mb: 0}
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
      assert Concurrency.usage(account.id) == %{vcpus: 8, memory_mb: 8192}
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

      assert {:error, :no_capacity} = Sandboxes.resume(paused)
      assert %{state: :paused, resident: true, error_message: nil} = Repo.reload!(paused)
      assert Concurrency.usage(paused.account_id) == %{vcpus: 0, memory_mb: 0}

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

  test "the macOS gate is required even in development and before any create side effect" do
    stub(FeatureFlags, :macos_sandboxes_enabled?, fn _ -> false end)
    reject(&Nodes.call/4)
    account = account_fixture()

    assert {:error, :macos_sandboxes_disabled} =
             Sandboxes.create_sandbox(account, %{platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192})

    assert {:error, :macos_sandboxes_disabled} = Sandboxes.create_agent_environment(account, %{platform: :darwin})
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
end
