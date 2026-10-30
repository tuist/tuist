defmodule Tuist.Sandboxes.AmpOrbsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Cache
  alias Tuist.Environment
  alias Tuist.Guardian
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  setup do
    account = account_fixture()
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    stub(Sites, :node_site, fn _node -> nil end)
    stub(Kura, :runner_cache_endpoint_url, fn _account, _platform, _site -> nil end)
    %{account: account}
  end

  defp spawn_params, do: %{operation: "spawn", orb_token: "orb-secret"}

  test "creates once and bootstraps repeated spawn with a protected residency", %{account: account} do
    expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

    expect(Nodes, :call, 2, fn "node-a", "exec", args, _opts ->
      assert args.cmd == ["/usr/local/bin/sbx-orb-bootstrap"]
      assert %{"ORB_TOKEN" => "orb-secret", "AMP_URL" => "https://ampcode.com", "TUIST_TOKEN" => "" <> _} = args.env
      refute Map.has_key?(args.env, "TUIST_CACHE_ENDPOINT")
      assert Repo.get!(Sandbox, args.sandbox_id).residency_work_id == "amp:amp-thread"
      assert {:ok, :skipped} = Sandboxes.pause_idle(args.sandbox_id)
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, first} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert {:ok, second} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert first.id == second.id
    assert [%{amp_orb_id: "amp-thread"}] = Sandboxes.list_sandboxes(account)
  end

  test "resume uses the existing disk and passes a fresh token and custom URL", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", state: :paused, node_name: "node-a")
    expect(Capacity, :admit, fn actual -> {:ok, actual} end)

    expect(Nodes, :call, fn "node-a", "resume", %{sandbox_id: id}, _opts ->
      assert id == sandbox.id
      {:ok, %{}}
    end)

    expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
      assert %{"ORB_TOKEN" => "fresh-token", "AMP_URL" => "https://amp.example.com"} = env
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, %{id: id, state: :running}} =
             AmpOrbs.dispatch(account, "amp-thread", %{
               operation: "spawn",
               orb_token: "fresh-token",
               amp_url: "https://amp.example.com"
             })

    assert id == sandbox.id
  end

  test "passes a read-only account cache credential and the Node's site-local cache endpoint", %{account: account} do
    project = project_fixture(account: account)
    other_project = project_fixture()
    sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    endpoint = "http://kura-test.kura.svc.cluster.local:4000"
    expect(Sites, :node_site, fn "node-a" -> "larch" end)

    expect(Kura, :runner_cache_endpoint_url, fn %{id: account_id}, :linux, "larch" ->
      assert account_id == account.id
      endpoint
    end)

    parent = self()

    expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
      send(parent, {:env, env})
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, _sandbox} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert_receive {:env, %{"TUIST_TOKEN" => token} = env}
    assert env["TUIST_CACHE_ENDPOINT"] == endpoint
    assert env["TUIST_URL"] == Environment.app_url()

    assert {:ok, claims} = Guardian.decode_and_verify(token)
    assert_in_delta claims["exp"] - claims["iat"], 6 * 3600, 1
    assert {:ok, %AuthenticatedAccount{} = subject} = Guardian.resource_from_claims(claims)
    assert subject.account.id == account.id
    assert subject.scopes == ["account:cache:read", "project:cache:read"]

    assert %{"account" => %{"read" => [account_handle], "write" => []}, "project" => %{"read" => readable, "write" => []}} =
             Cache.cache_grants(subject)

    assert account_handle == account.name
    assert "#{account.name}/#{project.name}" in readable
    refute Enum.any?(readable, &String.ends_with?(&1, "/#{other_project.name}"))
    assert Authorization.authorize(:project_cache_read, subject, project) == :ok
    assert Authorization.authorize(:project_cache_create, subject, project) != :ok
    assert Authorization.authorize(:account_cache_create, subject, account) != :ok
    assert Authorization.authorize(:run_create, subject, project) != :ok
  end

  test "pause is repeatable and only releases residency after a successful snapshot", %{account: account} do
    sandbox =
      sandbox_fixture(
        account: account,
        amp_orb_id: "amp-thread",
        node_name: "node-a",
        residency_work_id: "amp:amp-thread"
      )

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, :timeout} end)
    assert {:error, :timeout} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    assert Repo.reload!(sandbox).residency_work_id == "amp:amp-thread"

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert {:ok, %{state: :paused, residency_work_id: nil}} =
             AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

    assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
  end

  test "delete is repeatable and lookup is account-scoped", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    other = account_fixture()
    assert {:ok, nil} = AmpOrbs.dispatch(other, "amp-thread", %{operation: "delete"})
    assert {:ok, nil} = AmpOrbs.dispatch(other, "amp-thread", %{operation: "pause"})
    assert Repo.reload!(sandbox)
    expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
    assert {:ok, nil} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
    assert {:ok, nil} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
    refute Repo.get(Sandbox, sandbox.id)
  end

  test "bootstrap failure drops the residency and never returns guest output", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")

    expect(Nodes, :call, fn "node-a", "exec", _args, opts ->
      opts[:on_stream].({"stderr", Base.encode64("orb-secret")})
      {:ok, %{"exit_code" => 1}}
    end)

    assert {:error, :orb_bootstrap_failed} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox).residency_work_id == nil
  end

  test "CI admission refusal never starts bootstrap", %{account: account} do
    sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    expect(Capacity, :admit_turn, fn _sandbox, _fun -> {:error, :no_capacity} end)
    reject(&Nodes.call/4)
    assert {:error, :no_capacity} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
  end

  test "a placed errored Orb retains its disk instead of being recreated", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", state: :error)
    reject(&Nodes.call/4)
    assert {:error, {:invalid_state, :error}} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox)
  end

  test "overlapping dispatch receives a bounded conflict without touching the VM", %{account: account} do
    parent = self()

    task =
      Task.async(fn ->
        Sandboxes.with_sandbox_lock("amp:#{account.id}:amp-thread", fn ->
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked
    reject(&Nodes.call/4)
    assert {:error, :locked} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    send(task.pid, :release)
    Task.await(task)
  end

  test "retries failed placement without a node instead of stranding the Orb identity", %{account: account} do
    expect(Capacity, :place, fn _ -> {:error, :no_capacity} end)
    assert {:error, :no_capacity} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert %{state: :error, node_name: nil} = Repo.get_by!(Sandbox, account_id: account.id, amp_orb_id: "amp-thread")

    expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
    expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
    assert {:ok, %{state: :running}} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert length(Sandboxes.list_sandboxes(account)) == 1
  end

  test "database identity is unique within an account and independent across accounts", %{account: account} do
    sandbox_fixture(account: account, amp_orb_id: "amp-thread")
    other = account_fixture()
    assert sandbox_fixture(account: other, amp_orb_id: "amp-thread")

    attrs = %{
      account_id: account.id,
      amp_orb_id: "amp-thread",
      template: "default",
      vcpus: 2,
      memory_mb: 4096,
      workspace_gb: 10
    }

    assert {:error, changeset} = %Sandbox{} |> Sandbox.create_changeset(attrs) |> Repo.insert()
    assert %{account_id: ["has already been taken"]} = errors_on(changeset)
  end

  describe "project snapshots" do
    defp sandbox_node(name), do: %{name: name, disk: %{}, templates: [%{name: "default", ready: true, rootfs_bytes: 1}]}

    test "a pause with a snapshot ID syncs the disks and saves them once", %{account: account} do
      sandbox =
        sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a", residency_work_id: "amp:x")

      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)

      expect(Nodes, :call, fn "node-a", "pause", args, _opts ->
        assert args == %{sandbox_id: sandbox.id, sync_disks: true}
        {:ok, %{"disks_synced" => true}}
      end)

      expect(Nodes, :call, fn "node-a", "save_disks", %{sandbox_id: id, snapshot_id: snapshot_id}, _opts ->
        assert id == sandbox.id
        assert Repo.get!(DiskSnapshot, snapshot_id).state == :saving
        {:ok, %{"duration_ms" => 3}}
      end)

      params = %{operation: "pause", snapshot_id: "proj-1"}
      assert {:ok, %{state: :paused, residency_work_id: nil}} = AmpOrbs.dispatch(account, "amp-thread", params)

      assert [%DiskSnapshot{state: :ready, amp_snapshot_id: "proj-1", node_name: "node-a", source_sandbox_id: source}] =
               Repo.all(DiskSnapshot)

      assert source == sandbox.id

      # Amp may replay the pause; the copy of this pause is not saved twice.
      reject(&Nodes.call/4)
      assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", params)
    end

    test "a newer save replaces the older snapshot of the same ID", %{account: account} do
      old = disk_snapshot_fixture(account: account, amp_snapshot_id: "proj-1", node_name: "node-b")
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-b", "delete_disks", %{snapshot_id: id}, _opts ->
        assert id == old.id
        {:ok, %{}}
      end)

      assert {:ok, _} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj-1"})
      assert [%DiskSnapshot{node_name: "node-a"}] = Repo.all(DiskSnapshot)
    end

    test "a failed save still pauses the Orb and keeps no snapshot", %{account: account} do
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{"disks_synced" => false}} end)

      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts ->
        {:error, "disks were not synced by the last pause"}
      end)

      expect(Nodes, :call, fn "node-a", "delete_disks", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %{state: :paused}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj-1"})

      assert Repo.all(DiskSnapshot) == []
    end

    test "a full node disk budget skips the save", %{account: account} do
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")

      stub(Nodes, :connected_nodes, fn ->
        [%{sandbox_node("node-a") | disk: %{budget_bytes: 1, available_bytes: 1}}]
      end)

      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %{state: :paused}} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj-1"})

      assert Repo.all(DiskSnapshot) == []
    end

    test "a new Orb is cloned from the saved snapshot on its node", %{account: account} do
      snapshot =
        disk_snapshot_fixture(
          account: account,
          amp_snapshot_id: "proj-1",
          node_name: "node-a",
          last_used_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        )

      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", args, _opts ->
        assert args.from_disk_snapshot == snapshot.id
        {:ok, %{"boot_ms" => 700}}
      end)

      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{state: :running, node_name: "node-a"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      assert DateTime.after?(Repo.reload!(snapshot).last_used_at, snapshot.last_used_at)
    end

    test "a clone the node lost falls back to the template on the same node", %{account: account} do
      snapshot = disk_snapshot_fixture(account: account, amp_snapshot_id: "proj-1", node_name: "node-a")
      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", %{from_disk_snapshot: _}, _opts ->
        {:error, "disk snapshot not found: #{snapshot.id}"}
      end)

      expect(Nodes, :call, fn "node-a", "delete_disks", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "create", args, _opts ->
        refute Map.has_key?(args, :from_disk_snapshot)
        {:ok, %{}}
      end)

      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{state: :running}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      refute Repo.get(DiskSnapshot, snapshot.id)
    end

    test "a snapshot node without room boots the template elsewhere", %{account: account} do
      disk_snapshot_fixture(account: account, amp_snapshot_id: "proj-1", node_name: "node-a")
      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:error, :no_capacity} end)
      expect(Capacity, :place, fn _sandbox -> {:ok, "node-b"} end)

      expect(Nodes, :call, fn "node-b", "create", args, _opts ->
        refute Map.has_key?(args, :from_disk_snapshot)
        {:ok, %{}}
      end)

      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))
    end

    test "snapshots are account-scoped", %{account: account} do
      disk_snapshot_fixture(account: account_fixture(), amp_snapshot_id: "proj-1", node_name: "node-a")
      reject(&Capacity.place_on_node/2)
      expect(Capacity, :place, fn _sandbox -> {:ok, "node-b"} end)
      expect(Nodes, :call, fn "node-b", "create", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, _} = AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))
    end
  end
end
