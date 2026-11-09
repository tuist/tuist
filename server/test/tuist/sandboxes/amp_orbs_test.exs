defmodule Tuist.Sandboxes.AmpOrbsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxEvent
  alias Tuist.Sandboxes.Workers.ArchiveDiskSnapshotWorker
  alias Tuist.Storage

  setup do
    account = account_fixture()
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    stub(Sites, :node_site, fn _node -> nil end)
    stub(Kura, :runner_cache_endpoint_url, fn _account, _platform, _site -> nil end)
    %{account: account}
  end

  defp spawn_params, do: %{operation: "spawn", orb_token: "orb-secret"}

  # Every Orb pause first reads the setup log's times; `stdout` is what the
  # guest prints, empty when there is nothing new to record.
  defp expect_setup_read(stdout \\ "") do
    expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["sh", "-c", _read]}, opts ->
      if stdout != "", do: opts[:on_stream].({:stdout, stdout})
      {:ok, %{"exit_code" => 0}}
    end)
  end

  defp sandbox_events(%Sandbox{id: id}, event) do
    ClickHouseRepo.all(
      from(e in SandboxEvent,
        where: e.sandbox_id == ^id and e.event == ^event,
        select: %{boot_source: e.boot_source, duration_ms: e.duration_ms, inserted_at: e.inserted_at}
      )
    )
  end

  test "creates once and bootstraps repeated spawn with a protected residency", %{account: account} do
    expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

    expect(Nodes, :call, 2, fn "node-a", "exec", args, _opts ->
      assert args.cmd == ["/usr/local/bin/sbx-orb-bootstrap"]
      assert %{"ORB_TOKEN" => "orb-secret", "AMP_URL" => "https://ampcode.com"} = args.env
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

  test "passes the Tuist URL and the Node's site-local cache endpoint but no Tuist credential", %{account: account} do
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
    assert_receive {:env, env}
    refute Map.has_key?(env, "TUIST_TOKEN")
    assert env["TUIST_CACHE_ENDPOINT"] == endpoint
    assert env["TUIST_URL"] == Environment.app_url()
  end

  test "pause is repeatable and only releases residency after a successful snapshot", %{account: account} do
    sandbox =
      sandbox_fixture(
        account: account,
        amp_orb_id: "amp-thread",
        node_name: "node-a",
        residency_work_id: "amp:amp-thread"
      )

    expect_setup_read()
    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, :timeout} end)
    assert {:error, :timeout} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    assert Repo.reload!(sandbox).residency_work_id == "amp:amp-thread"

    # Every Orb pause syncs the disks, which archiving relies on.
    expect_setup_read()
    expect(Nodes, :call, fn "node-a", "pause", %{sync_disks: true}, _opts -> {:ok, %{}} end)

    assert {:ok, %{state: :paused, residency_work_id: nil}} =
             AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

    assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
  end

  test "records the setup that ran in the Orb from its log before pausing", %{account: account} do
    sandbox =
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a", residency_work_id: "amp:x")

    started_s = DateTime.to_unix(sandbox.inserted_at) + 30
    expect_setup_read("#{started_s} #{started_s + 240}\n")
    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

    assert [%{duration_ms: 240_000, inserted_at: finished_at}] = sandbox_events(sandbox, "setup")

    assert DateTime.to_unix(DateTime.from_naive!(finished_at, "Etc/UTC")) == started_s + 240
  end

  test "ignores a setup log older than the Orb, which came with the snapshot it was cloned from", %{account: account} do
    sandbox =
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a", residency_work_id: "amp:x")

    started_s = DateTime.to_unix(sandbox.inserted_at) - 3600
    expect_setup_read("#{started_s} #{started_s + 240}\n")
    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    assert sandbox_events(sandbox, "setup") == []
  end

  describe "pause_idle/2" do
    setup %{account: account} do
      quiet_since = DateTime.truncate(DateTime.add(DateTime.utc_now(), -700, :second), :second)

      sandbox =
        sandbox_fixture(
          account: account,
          amp_orb_id: "amp-thread",
          node_name: "node-a",
          residency_work_id: "amp:amp-thread",
          guest_cpu_ms: 1000,
          last_active_at: quiet_since
        )

      %{quiet_since: quiet_since, sandbox: sandbox}
    end

    test "pauses an Orb still quiet since the given activity as Amp's pause would", %{
      sandbox: sandbox,
      quiet_since: quiet_since
    } do
      expect_setup_read()
      expect(Nodes, :call, fn "node-a", "pause", %{sync_disks: true}, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :paused, residency_work_id: nil, guest_cpu_ms: nil}} =
               AmpOrbs.pause_idle(sandbox.id, quiet_since)
    end

    test "skips an Orb active since, and sandboxes that are not Orbs", %{
      account: account,
      sandbox: sandbox,
      quiet_since: quiet_since
    } do
      reject(&Nodes.call/4)
      assert {:ok, :skipped} = AmpOrbs.pause_idle(sandbox.id, DateTime.add(quiet_since, -30, :second))
      assert Repo.reload!(sandbox).state == :running

      api = sandbox_fixture(account: account, node_name: "node-a", last_active_at: quiet_since)
      assert {:ok, :skipped} = AmpOrbs.pause_idle(api.id, quiet_since)
    end
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

  test "a macOS Orb holds its host against idle eviction and bootstraps through the guest bridge", %{
    account: account
  } do
    sandbox =
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", platform: :darwin, node_name: "mac-a", node_uid: "uid")

    expect(Nodes, :call, fn "mac-a", "hold_residency", args, _opts ->
      assert args == %{sandbox_id: sandbox.id, work_id: "amp:amp-thread", node_uid: "uid"}
      {:ok, %{}}
    end)

    expect(Nodes, :call, fn "mac-a", "exec", args, opts ->
      assert args.cmd == ["/usr/local/libexec/tuist-sandbox/sbx-macos", "--orb-bootstrap"]
      assert args.cwd == "/Users/runner/work"
      assert %{"ORB_TOKEN" => "orb-secret"} = args.env
      assert opts[:timeout] > 120_000
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, _} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox).residency_work_id == "amp:amp-thread"

    # A failed bootstrap releases the host hold along with the residency.
    expect(Nodes, :call, fn "mac-a", "hold_residency", _args, _opts -> {:ok, %{}} end)
    expect(Nodes, :call, fn "mac-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 1}} end)

    expect(Nodes, :call, fn "mac-a", "release_residency", %{work_id: "amp:amp-thread"}, _opts -> {:ok, %{}} end)

    assert {:error, :orb_bootstrap_failed} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox).residency_work_id == nil
  end

  test "a macOS Orb's first spawn starts its turn even when CI closed the grant while the VM booted", %{
    account: account
  } do
    expect(Capacity, :place, fn _ -> {:ok, "mac-a"} end)
    expect(Nodes, :call, fn "mac-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 19_000}} end)
    stub(Capacity, :admit_turn, fn _sandbox, _fun -> {:error, :no_capacity} end)
    expect(Nodes, :call, fn "mac-a", "hold_residency", _args, _opts -> {:ok, %{}} end)
    expect(Nodes, :call, fn "mac-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

    assert {:ok, sandbox} =
             AmpOrbs.dispatch(
               account,
               "amp-thread",
               Map.merge(spawn_params(), %{platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192})
             )

    assert %{state: :running, residency_work_id: "amp:amp-thread"} = Repo.reload!(sandbox)
  end

  test "a macOS Orb's pause saves no disk snapshot and is never archived", %{account: account} do
    sandbox_fixture(account: account, amp_orb_id: "amp-thread", platform: :darwin, node_name: "mac-a", node_uid: "uid")

    expect(Nodes, :call, fn "mac-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 1}} end)
    expect(Nodes, :call, fn "mac-a", "pause", _args, _opts -> {:ok, %{"resident" => true}} end)

    assert {:ok, paused} =
             AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj:snap"})

    assert paused.state == :paused
    refute Repo.exists?(DiskSnapshot)
    refute Tuist.Sandboxes.Archives.archivable?(Repo.reload!(paused))
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

  test "a spawn for another platform never boots the existing Orb", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    reject(&Nodes.call/4)

    assert {:error, :orb_type_mismatch} =
             AmpOrbs.dispatch(account, "amp-thread", Map.put(spawn_params(), :platform, :darwin))

    assert %{platform: :linux, state: :running, residency_work_id: nil} = Repo.reload!(sandbox)
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
      stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)

      expect_setup_read()

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

      # The ready snapshot is queued for upload, so any node can boot from it.
      assert [%{args: %{"disk_snapshot_id" => queued}}] = all_enqueued(worker: ArchiveDiskSnapshotWorker)
      assert queued == Repo.one!(DiskSnapshot).id

      # Amp may replay the pause; the copy of this pause is not saved twice.
      reject(&Nodes.call/4)
      assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", params)
    end

    test "a newer save replaces the older snapshot of the same ID", %{account: account} do
      old = disk_snapshot_fixture(account: account, amp_snapshot_id: "proj-1", node_name: "node-b")
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)
      expect_setup_read()
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-b", "delete_disks", %{snapshot_id: id}, _opts ->
        assert id == old.id
        {:ok, %{}}
      end)

      assert {:ok, _} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj-1"})
      assert [%DiskSnapshot{node_name: "node-a"}] = Repo.all(DiskSnapshot)
    end

    test "a save under a new ID replaces the snapshot the Orb was spawned from", %{account: account} do
      base = disk_snapshot_fixture(account: account, amp_snapshot_id: "proj-1", node_name: "node-a")
      other_project = disk_snapshot_fixture(account: account, amp_snapshot_id: "other-1", node_name: "node-a")
      other_account = disk_snapshot_fixture(account: account_fixture(), amp_snapshot_id: "proj-1", node_name: "node-a")

      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", %{from_disk_snapshot: _}, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, _} = AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)
      expect_setup_read()
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{"disks_synced" => true}} end)
      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "delete_disks", %{snapshot_id: id}, _opts ->
        assert id == base.id
        {:ok, %{}}
      end)

      assert {:ok, _} = AmpOrbs.dispatch(account, "amp-new", %{operation: "pause", snapshot_id: "proj-2"})

      refute Repo.get(DiskSnapshot, base.id)
      assert Repo.get(DiskSnapshot, other_project.id)
      assert Repo.get(DiskSnapshot, other_account.id)
      assert Repo.get_by(DiskSnapshot, account_id: account.id, amp_snapshot_id: "proj-2", state: :ready)
    end

    # Amp records a snapshot whenever the pause succeeds, so a save that
    # failed must fail the pause or later Orbs name a snapshot that is not there.
    test "a failed save pauses the Orb but fails the pause, and a replay retries the save", %{account: account} do
      sandbox =
        sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a", residency_work_id: "amp:x")

      stub(Nodes, :connected_nodes, fn -> [sandbox_node("node-a")] end)
      expect_setup_read()
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{"disks_synced" => false}} end)

      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts ->
        {:error, "disks were not synced by the last pause"}
      end)

      expect(Nodes, :call, fn "node-a", "delete_disks", _args, _opts -> {:ok, %{}} end)

      params = %{operation: "pause", snapshot_id: "proj-1"}
      assert {:error, :snapshot_not_saved} = AmpOrbs.dispatch(account, "amp-thread", params)

      assert %Sandbox{state: :paused, residency_work_id: nil} = Repo.reload!(sandbox)
      assert Repo.all(DiskSnapshot) == []

      expect(Nodes, :call, fn "node-a", "save_disks", _args, _opts -> {:ok, %{}} end)
      assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", params)
      assert [%DiskSnapshot{state: :ready, amp_snapshot_id: "proj-1"}] = Repo.all(DiskSnapshot)
    end

    test "a full node disk budget fails the pause without saving", %{account: account} do
      sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")

      stub(Nodes, :connected_nodes, fn ->
        [%{sandbox_node("node-a") | disk: %{budget_bytes: 1, available_bytes: 1}}]
      end)

      expect_setup_read()
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

      assert {:error, :snapshot_not_saved} =
               AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause", snapshot_id: "proj-1"})

      assert Repo.reload!(sandbox).state == :paused
      assert Repo.all(DiskSnapshot) == []
    end

    test "a pause of an archived Orb succeeds unless it asks for a snapshot", %{account: account} do
      sandbox_fixture(account: account, amp_orb_id: "amp-thread", state: :archived, node_name: nil)
      reject(&Nodes.call/4)

      assert {:ok, %{state: :archived}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

      assert {:error, :snapshot_not_saved} =
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

      sandbox = Repo.get_by!(Sandbox, amp_orb_id: "amp-new")
      assert [%{boot_source: "disk_snapshot"}] = sandbox_events(sandbox, "started")
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

    defp archived_snapshot(account, opts) do
      disk_snapshot_fixture(
        Keyword.merge(
          [
            account: account,
            amp_snapshot_id: "proj-1",
            node_name: "node-a",
            archive_key: "snapshot-key",
            archive_bytes: 2048,
            archive_sha256: "cafe",
            archived_at: DateTime.utc_now(),
            last_used_at: DateTime.add(DateTime.utc_now(), -3600, :second)
          ],
          opts
        )
      )
    end

    defp expect_archive_create(node_name) do
      expect(Storage, :generate_download_url, fn "snapshot-key", _actor, _opts -> "https://s3/snapshot" end)

      expect(Nodes, :call, fn ^node_name, "create", args, opts ->
        assert args.from_archive == %{url: "https://s3/snapshot", bytes: 2048, sha256: "cafe"}
        refute Map.has_key?(args, :from_disk_snapshot)
        assert opts[:timeout] > to_timeout(second: 120)
        {:ok, %{}}
      end)
    end

    test "a snapshot node without room creates the Orb from the snapshot's archive elsewhere", %{account: account} do
      snapshot = archived_snapshot(account, [])
      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:error, :no_capacity} end)
      expect(Capacity, :place, fn %Sandbox{node_name: nil} -> {:ok, "node-b"} end)
      expect_archive_create("node-b")
      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{state: :running, node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      assert DateTime.after?(Repo.reload!(snapshot).last_used_at, snapshot.last_used_at)
      sandbox = Repo.get_by!(Sandbox, amp_orb_id: "amp-new")
      assert [%{boot_source: "disk_snapshot_archive"}] = sandbox_events(sandbox, "started")
    end

    test "an archived snapshot whose node copy is gone is created from its archive", %{account: account} do
      archived_snapshot(account, node_name: nil)
      reject(&Capacity.place_on_node/2)
      expect(Capacity, :place, fn _sandbox -> {:ok, "node-b"} end)
      expect_archive_create("node-b")
      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))
    end

    test "a clone the node lost falls back to the archive and keeps the archived row", %{account: account} do
      snapshot = archived_snapshot(account, [])
      expect(Capacity, :place_on_node, fn _sandbox, "node-a" -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", %{from_disk_snapshot: _}, _opts ->
        {:error, "disk snapshot not found: #{snapshot.id}"}
      end)

      expect(Capacity, :place, fn %Sandbox{node_name: nil} = sandbox ->
        refute Repo.reload!(sandbox).node_name
        {:ok, "node-b"}
      end)

      expect_archive_create("node-b")
      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      assert %DiskSnapshot{node_name: nil, archive_key: "snapshot-key"} = Repo.reload!(snapshot)
    end

    test "a failed create from the archive boots the template on the same node", %{account: account} do
      archived_snapshot(account, node_name: nil)
      expect(Capacity, :place, fn _sandbox -> {:ok, "node-b"} end)
      expect(Storage, :generate_download_url, fn _key, _actor, _opts -> "https://s3/snapshot" end)

      expect(Nodes, :call, fn "node-b", "create", %{from_archive: _}, _opts ->
        {:error, "restoring archive: checksum mismatch"}
      end)

      expect(Nodes, :call, fn "node-b", "create", args, _opts ->
        refute Map.has_key?(args, :from_archive)
        {:ok, %{}}
      end)

      expect(Nodes, :call, fn "node-b", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{node_name: "node-b"}} =
               AmpOrbs.dispatch(account, "amp-new", Map.put(spawn_params(), :snapshot_id, "proj-1"))

      sandbox = Repo.get_by!(Sandbox, amp_orb_id: "amp-new")
      assert [%{boot_source: "template"}] = sandbox_events(sandbox, "started")
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
