defmodule Tuist.Sandboxes.DiskSnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshotCopy
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @gib 1024 * 1024 * 1024

  defp backdate(snapshot, field, seconds) do
    at = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id), set: [{field, at}])
    Repo.reload!(snapshot)
  end

  describe "reconcile_node_report/2" do
    test "deletes copies no row knows and drops rows whose copy the node lost" do
      kept = disk_snapshot_fixture(node_name: "node-a")
      lost = backdate(disk_snapshot_fixture(node_name: "node-a"), :updated_at, 600)
      just_saved = disk_snapshot_fixture(node_name: "node-a")
      saving = backdate(disk_snapshot_fixture(node_name: "node-a", state: :saving), :updated_at, 600)
      elsewhere = backdate(disk_snapshot_fixture(node_name: "node-b"), :updated_at, 600)
      orphan_id = Ecto.UUID.generate()

      expect(Nodes, :call, fn "node-a", "delete_disks", %{snapshot_id: ^orphan_id}, _opts -> {:ok, %{}} end)

      assert :ok =
               DiskSnapshots.reconcile_node_report("node-a", %{
                 "disk_snapshots" => [%{"id" => kept.id}, %{"id" => orphan_id}, %{"id" => "not-a-uuid"}]
               })

      assert Repo.reload(kept)
      refute Repo.reload(lost)
      assert Repo.reload(just_saved)
      assert Repo.reload(saving)
      assert Repo.reload(elsewhere)
    end

    test "keeps an archived row whose copy the node lost, without a node" do
      archived =
        disk_snapshot_fixture(
          node_name: "node-a",
          archive_key: "k",
          archive_bytes: 1,
          archive_sha256: "abc",
          archived_at: DateTime.utc_now()
        )

      archived = backdate(archived, :updated_at, 600)
      reject(&Storage.delete_object/2)

      assert :ok = DiskSnapshots.reconcile_node_report("node-a", %{"disk_snapshots" => []})

      assert %DiskSnapshot{node_name: nil, archive_key: "k"} = Repo.reload!(archived)
      assert Capacity.reserved_disk_bytes(%{name: "node-a"}) == 0

      # A copy the node still lists for a row that gave it up is removed.
      expect(Nodes, :call, fn "node-a", "delete_disks", %{snapshot_id: id}, _opts when id == archived.id -> {:ok, %{}} end)

      assert :ok = DiskSnapshots.reconcile_node_report("node-a", %{"disk_snapshots" => [%{"id" => archived.id}]})
      assert Repo.reload(archived)
    end

    test "leaves rows alone when the daemon does not report disk snapshots" do
      snapshot = backdate(disk_snapshot_fixture(node_name: "node-a"), :updated_at, 600)
      reject(&Nodes.call/4)
      assert :ok = DiskSnapshots.reconcile_node_report("node-a", %{"sandboxes" => []})
      assert Repo.reload(snapshot)
    end
  end

  describe "Claude Code repository snapshots" do
    setup do
      account = account_fixture()

      agent_environment =
        agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_01")

      stub(Nodes, :connected_nodes, fn ->
        [
          %{
            name: "node-a",
            disk: %{},
            default_template: "default",
            default_template_tag: "sha-new",
            templates: [
              %{name: "default", ready: true, tag: "sha-old", rootfs_bytes: 1},
              %{name: "default", ready: true, tag: "sha-new", rootfs_bytes: 1}
            ]
          },
          %{name: "node-b", disk: %{}, templates: [%{name: "default", ready: true, tag: "sha-b", rootfs_bytes: 1}]}
        ]
      end)

      %{account: account, agent_environment: agent_environment}
    end

    defp repository_snapshot(account, agent_environment, opts) do
      at = DateTime.add(DateTime.utc_now(), Keyword.get(opts, :age_seconds, 0) * -1, :second)

      [account: account, agent_environment_id: agent_environment.id, repository: "acme/app", setup_sha256: "s1"]
      |> Keyword.merge(Keyword.delete(opts, :age_seconds))
      |> disk_snapshot_fixture()
      |> backdate_inserted_at(at)
    end

    defp backdate_inserted_at(snapshot, at) do
      at = DateTime.truncate(at, :second)
      Repo.update_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id), set: [inserted_at: at])
      Repo.reload!(snapshot)
    end

    test "find_ready_for_repository/3 picks the newest ready snapshot of the script on a tag nodes create with", %{
      account: account,
      agent_environment: agent_environment
    } do
      # node-b creates with its only tag.
      newest_usable = repository_snapshot(account, agent_environment, template_tag: "sha-b", age_seconds: 20)
      _older = repository_snapshot(account, agent_environment, template_tag: "sha-new", age_seconds: 30)
      # Newer, but each unusable for one reason.
      _old_image = repository_snapshot(account, agent_environment, template_tag: "sha-old", age_seconds: 1)
      _old_script = repository_snapshot(account, agent_environment, setup_sha256: "s0", template_tag: "sha-new")
      _saving = repository_snapshot(account, agent_environment, state: :saving, template_tag: "sha-new")
      _other_repository = repository_snapshot(account, agent_environment, repository: "acme/web", template_tag: "sha-new")
      _other_size = repository_snapshot(account, agent_environment, workspace_gb: 20, template_tag: "sha-new")

      other_environment =
        agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_02")

      _other_environment = repository_snapshot(account, other_environment, template_tag: "sha-new")

      assert DiskSnapshots.find_ready_for_repository(agent_environment, "acme/app", "s1").id == newest_usable.id

      stub(Nodes, :connected_nodes, fn -> [] end)
      assert DiskSnapshots.find_ready_for_repository(agent_environment, "acme/app", "s1") == nil
    end

    test "save_build/2 saves the builder's paused disks and replaces the environment's older snapshots of the repository",
         %{account: account, agent_environment: agent_environment} do
      older = repository_snapshot(account, agent_environment, setup_sha256: "s0", age_seconds: 60)
      other_repository = repository_snapshot(account, agent_environment, repository: "acme/web", age_seconds: 60)
      amp = disk_snapshot_fixture(account: account)
      {:ok, build} = DiskSnapshots.start_build(agent_environment, "acme/app", "s1")
      {:ok, other_build} = DiskSnapshots.start_build(agent_environment, "acme/app", "s2")

      sandbox =
        sandbox_fixture(
          account: account,
          id: build.id,
          agent_environment_id: agent_environment.id,
          state: :paused,
          node_name: "node-a",
          template_tag: "sha-new"
        )

      expect(Nodes, :call, fn "node-a", "save_disks", %{sandbox_id: id}, _opts when id == sandbox.id ->
        {:ok, %{"duration_ms" => 3}}
      end)

      expect(Nodes, :call, fn "node-a", "delete_disks", %{snapshot_id: id}, _opts when id == older.id -> {:ok, %{}} end)

      assert {:ok, %DiskSnapshot{state: :ready, repository: "acme/app", setup_sha256: "s1", template_tag: "sha-new"}} =
               DiskSnapshots.save_build(build, sandbox)

      refute Repo.reload(build)
      refute Repo.reload(older)
      assert Repo.reload(other_build)
      assert Repo.reload(other_repository)
      assert Repo.reload(amp)
    end
  end

  test "delete_expired/0 removes unused snapshots and stuck saves" do
    unused = backdate(disk_snapshot_fixture(node_name: "node-a"), :last_used_at, 73 * 3600)
    recent = backdate(disk_snapshot_fixture(node_name: "node-a"), :last_used_at, 71 * 3600)
    stuck = backdate(disk_snapshot_fixture(node_name: "node-a", state: :saving), :updated_at, 16 * 60)
    saving = disk_snapshot_fixture(node_name: "node-a", state: :saving)

    expect(Nodes, :call, 2, fn "node-a", "delete_disks", %{snapshot_id: id}, _opts ->
      assert id in [unused.id, stuck.id]
      {:ok, %{}}
    end)

    DiskSnapshots.delete_expired()

    refute Repo.reload(unused)
    refute Repo.reload(stuck)
    assert Repo.reload(recent)
    assert Repo.reload(saving)
  end

  describe "delete/1" do
    test "removes the node copy, the archive object and the row" do
      snapshot = disk_snapshot_fixture(node_name: "node-a", archive_key: "k", archived_at: DateTime.utc_now())

      expect(Nodes, :call, fn "node-a", "delete_disks", %{snapshot_id: id}, _opts when id == snapshot.id -> {:ok, %{}} end)

      expect(Storage, :delete_object, fn "k", _account -> :ok end)

      assert :ok = DiskSnapshots.delete(snapshot)
      refute Repo.reload(snapshot)
    end

    test "aborts an upload in flight and keeps an archived row storage refused to delete" do
      uploading = disk_snapshot_fixture(node_name: nil, archive_key: "up", archive_upload_id: "upload-1")
      expect(Storage, :multipart_abort, fn "up", "upload-1", _account -> :ok end)
      expect(Storage, :delete_object, fn "up", _account -> :ok end)
      reject(&Nodes.call/4)
      assert :ok = DiskSnapshots.delete(uploading)
      refute Repo.reload(uploading)

      archived = disk_snapshot_fixture(node_name: nil, archive_key: "k", archived_at: DateTime.utc_now())
      expect(Storage, :delete_object, fn "k", _account -> {:error, :unavailable} end)
      assert {:error, :unavailable} = DiskSnapshots.delete(archived)
      assert %DiskSnapshot{node_name: nil, archive_key: "k"} = Repo.reload!(archived)
    end
  end

  test "a snapshot reserves its ceiling against its node's disk budget" do
    node = %{name: "node-a", disk: %{budget_bytes: 100 * @gib}, templates: [%{name: "default", rootfs_bytes: 8 * @gib}]}
    before = Capacity.reserved_disk_bytes(node)
    disk_snapshot_fixture(node_name: "node-a", workspace_gb: 10)
    disk_snapshot_fixture(node_name: "node-b", workspace_gb: 10)

    assert Capacity.reserved_disk_bytes(node) - before ==
             Capacity.disk_snapshot_ceiling_bytes(%{workspace_gb: 10, template: "default"}, node)

    assert Capacity.disk_snapshot_ceiling_bytes(%{workspace_gb: 10, template: "default"}, node) > 18 * @gib
  end

  describe "copies" do
    defp copy_node(name),
      do: %{
        name: name,
        disk: %{budget_bytes: 100 * @gib},
        templates: [%{name: "default", ready: true, rootfs_bytes: 8 * @gib}]
      }

    defp popular_snapshot(opts \\ []) do
      account = Keyword.get_lazy(opts, :account, &AccountsFixtures.account_fixture/0)

      snapshot =
        disk_snapshot_fixture(
          Keyword.merge(
            [
              account: account,
              amp_snapshot_id: "proj-1",
              node_name: "node-a",
              archive_key: "snapshot-key",
              archive_bytes: 2048,
              archive_sha256: "cafe",
              archived_at: DateTime.utc_now()
            ],
            opts
          )
        )

      for _ <- 1..Keyword.get(opts, :running, 2)//1,
          do: sandbox_fixture(account: account, amp_base_snapshot_id: snapshot.amp_snapshot_id, node_name: "node-a")

      snapshot
    end

    defp copied_nodes(snapshot) do
      Repo.all(
        from(c in DiskSnapshotCopy,
          where: c.disk_snapshot_id == ^snapshot.id and c.state == :ready,
          select: c.node_name,
          order_by: c.node_name
        )
      )
    end

    setup do
      stub(Environment, :sandbox_archive_disk_high_water_percent, fn -> 85 end)
      stub(Storage, :generate_download_url, fn "snapshot-key", _actor, _opts -> "https://s3/snapshot" end)
      :ok
    end

    test "copies a popular snapshot to a node that stays under the high-water mark with it" do
      snapshot = popular_snapshot()
      # 72 GiB reserved: the copy's 18 GiB fits node-b's budget but not 85% of it.
      sandbox_fixture(node_name: "node-b", state: :paused, workspace_gb: 60)
      stub(Nodes, :connected_nodes, fn -> Enum.map(~w(node-a node-b node-c), &copy_node/1) end)
      before = Capacity.reserved_disk_bytes(copy_node("node-c"))

      expect(Nodes, :call, fn "node-c", "copy_disks", args, _opts ->
        assert args == %{
                 snapshot_id: snapshot.id,
                 template: "default",
                 workspace_gb: 10,
                 from_archive: %{url: "https://s3/snapshot", bytes: 2048, sha256: "cafe"}
               }

        assert [%DiskSnapshotCopy{state: :copying}] = Repo.all(DiskSnapshotCopy)
        {:ok, %{"duration_ms" => 40_000}}
      end)

      assert {:error, :no_capacity} = DiskSnapshots.copy(snapshot)

      assert [%DiskSnapshotCopy{node_name: "node-c", state: :ready}] = Repo.all(DiskSnapshotCopy)
      assert Enum.sort(DiskSnapshots.held_nodes(snapshot)) == ["node-a", "node-c"]

      assert Capacity.reserved_disk_bytes(copy_node("node-c")) - before ==
               Capacity.disk_snapshot_ceiling_bytes(snapshot, copy_node("node-c"))
    end

    defp mac_host(name, tag, budget_gib \\ 1000),
      do: %{
        name: name,
        platform: "darwin",
        archives: true,
        generation: "uid-" <> name,
        disk: %{budget_bytes: budget_gib * @gib, available_bytes: 500 * @gib, snapshots_bytes: 0},
        templates: [%{name: "macos", tag: tag, ready: true, rootfs_bytes: 200 * @gib}]
      }

    defp mac_snapshot,
      do:
        popular_snapshot(
          platform: :darwin,
          node_name: "mac-a",
          template: "macos",
          template_tag: "img@sha256:a",
          disk_bytes: 5 * @gib
        )

    # A macOS snapshot is an overlay on the image it was saved from: it
    # copies to hosts that restore archives of its template, which clone that
    # image even when their template moved on, reserves the bytes its host
    # measured rather than a whole root disk, and names the host's
    # incarnation.
    test "copies a popular macOS snapshot to hosts restoring its template's archives with room for its bytes" do
      snapshot = mac_snapshot()

      hosts = [
        mac_host("mac-a", "img@sha256:a"),
        mac_host("mac-b", "img@sha256:b"),
        Map.put(mac_host("mac-c", "img@sha256:a"), :archives, false),
        copy_node("node-x")
      ]

      stub(Nodes, :connected_nodes, fn -> hosts end)
      stub(Nodes, :lookup, fn name -> {:ok, self(), Enum.find(hosts, &(&1.name == name))} end)

      expect(Nodes, :call, fn "mac-b", "copy_disks", args, _opts ->
        assert %{snapshot_id: id, template: "macos", node_uid: "uid-mac-b", bytes: bytes, template_tag: "img@sha256:a"} =
                 args

        assert id == snapshot.id and bytes == 5 * @gib
        {:ok, %{"bytes" => 5 * @gib}}
      end)

      assert :ok = DiskSnapshots.copy(snapshot)
      assert Enum.sort(DiskSnapshots.held_nodes(snapshot)) == ["mac-a", "mac-b"]

      # A host whose budget cannot take the bytes gets no copy.
      other = mac_snapshot()
      stub(Nodes, :connected_nodes, fn -> [mac_host("mac-a", "img@sha256:a"), mac_host("mac-d", "img@sha256:a", 4)] end)
      reject(&Nodes.call/4)
      assert {:error, :no_capacity} = DiskSnapshots.copy(other)
      assert DiskSnapshots.held_nodes(other) == ["mac-a"]
    end

    test "every snapshot of a lineage is copied to the same nodes, however the nodes are listed" do
      account = AccountsFixtures.account_fixture()
      nodes = Enum.map(1..8, &copy_node("node-#{&1}"))
      stub(Nodes, :call, fn _node, "copy_disks", _args, _opts -> {:ok, %{}} end)

      # Two Orbs ran at once, so three nodes hold the lineage; the snapshot's
      # own node-a is not ready here and does not count.
      stub(Nodes, :connected_nodes, fn -> nodes end)
      first = popular_snapshot(account: account, amp_snapshot_id: "proj-1", lineage_id: "proj-0")
      assert :ok = DiskSnapshots.copy(first)
      assert length(copied_nodes(first)) == 3

      # Amp's refresh lands on the same nodes, even when they report in
      # another order and an older copy fills part of their disk.
      stub(Nodes, :connected_nodes, fn -> Enum.reverse(nodes) end)
      refreshed = popular_snapshot(account: account, amp_snapshot_id: "proj-2", lineage_id: "proj-0")
      assert :ok = DiskSnapshots.copy(refreshed)
      assert copied_nodes(refreshed) == copied_nodes(first)
    end

    test "a lineage is held by half again as many nodes as its Orbs ran on at once, at least two, with at most four copies" do
      stub(Nodes, :connected_nodes, fn -> Enum.map(1..8, &copy_node("node-#{&1}")) end)
      stub(Nodes, :call, fn _node, "copy_disks", _args, _opts -> {:ok, %{}} end)

      # Four Orbs at once want six holders; copies stop at four.
      busy = popular_snapshot(running: 4)
      assert :ok = DiskSnapshots.copy(busy)
      assert length(copied_nodes(busy)) == 4

      # Three Orbs one after another: one at a time.
      account = AccountsFixtures.account_fixture()
      sequential = popular_snapshot(account: account, running: 0)
      start = DateTime.utc_now() |> DateTime.add(-6 * 3600) |> DateTime.truncate(:second)

      for hour <- [0, 2, 4] do
        orb =
          sandbox_fixture(
            account: account,
            amp_base_snapshot_id: sequential.amp_snapshot_id,
            state: :deleted,
            inserted_at: DateTime.add(start, hour * 3600)
          )

        Repo.update_all(from(s in Sandbox, where: s.id == ^orb.id),
          set: [updated_at: DateTime.add(start, hour * 3600 + 3600)]
        )
      end

      assert :ok = DiskSnapshots.copy(sequential)
      assert length(copied_nodes(sequential)) == 2
    end

    test "copies no snapshot that is not popular or not archived" do
      account = AccountsFixtures.account_fixture()

      unpopular =
        disk_snapshot_fixture(account: account, archive_key: "snapshot-key", archived_at: DateTime.utc_now())

      sandbox_fixture(account: account, amp_base_snapshot_id: unpopular.amp_snapshot_id)
      unarchived = popular_snapshot(archived_at: nil)
      stub(Nodes, :connected_nodes, fn -> [copy_node("node-b")] end)
      reject(&Nodes.call/4)

      refute DiskSnapshots.queue_copies(unpopular)
      refute DiskSnapshots.queue_copies(unarchived)
      assert :ok = DiskSnapshots.copy(unpopular)
      assert Repo.all(DiskSnapshotCopy) == []
    end

    test "a refreshed snapshot is as popular as its lineage, though the snapshots it refreshed are gone" do
      account = AccountsFixtures.account_fixture()

      # One Orb spawned from each earlier snapshot of the lineage; the last
      # saved this one, and the rows they were spawned from are deleted.
      sandbox_fixture(account: account, amp_base_snapshot_id: "proj-1", amp_snapshot_lineage_id: "proj-0")
      source = sandbox_fixture(account: account, amp_base_snapshot_id: "proj-2", amp_snapshot_lineage_id: "proj-0")
      sandbox_fixture(account: account, amp_base_snapshot_id: "other-1", amp_snapshot_lineage_id: "other-0")

      fresh =
        popular_snapshot(
          account: account,
          amp_snapshot_id: "proj-3",
          lineage_id: "proj-0",
          source_sandbox_id: source.id,
          running: 0
        )

      assert DiskSnapshots.queue_copies(fresh)

      # Another lineage's single spawn does not make it popular.
      lone =
        popular_snapshot(account: account, amp_snapshot_id: "other-2", lineage_id: "other-0", running: 0)

      refute DiskSnapshots.queue_copies(lone)
    end

    test "a Claude Code snapshot is popular through its environment's sessions and is copied past the high-water mark" do
      account = AccountsFixtures.account_fixture()

      agent_environment =
        agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_03")

      snapshot =
        disk_snapshot_fixture(
          account: account,
          agent_environment_id: agent_environment.id,
          repository: "acme/app",
          setup_sha256: "abc",
          node_name: "node-a",
          archive_key: "snapshot-key",
          archive_bytes: 2048,
          archive_sha256: "cafe",
          archived_at: DateTime.utc_now()
        )

      # A builder has no session and does not count.
      sandbox_fixture(account: account, agent_environment_id: agent_environment.id, node_name: "node-a")

      sandbox_fixture(
        account: account,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "s1",
        node_name: "node-a"
      )

      refute DiskSnapshots.queue_copies(snapshot)

      sandbox_fixture(
        account: account,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "s2",
        node_name: "node-a"
      )

      assert DiskSnapshots.queue_copies(snapshot)

      # 72 GiB reserved: the copy's 18 GiB passes 85% of node-b's budget but
      # fits the whole of it, which an Amp snapshot's copy would not get.
      sandbox_fixture(node_name: "node-b", state: :paused, workspace_gb: 60)
      stub(Nodes, :connected_nodes, fn -> Enum.map(~w(node-a node-b), &copy_node/1) end)
      expect(Nodes, :call, fn "node-b", "copy_disks", _args, _opts -> {:ok, %{}} end)

      assert :ok = DiskSnapshots.copy(snapshot)
      assert copied_nodes(snapshot) == ["node-b"]
    end

    test "a Linux environment's macOS snapshot is popular through the Macs created for its repository and template" do
      account = AccountsFixtures.account_fixture()

      agent_environment =
        agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_04")

      snapshot =
        disk_snapshot_fixture(
          account: account,
          agent_environment_id: agent_environment.id,
          repository: "acme/app",
          setup_sha256: "abc",
          platform: :darwin,
          template: "macos-xcode-27-2",
          disk_bytes: 1024,
          node_name: "host-a",
          archive_key: "snapshot-key",
          archive_bytes: 2048,
          archive_sha256: "cafe",
          archived_at: DateTime.utc_now()
        )

      # The environment's Linux sessions, another repository's Mac, the
      # repository's Mac on another Xcode and a create that failed do not
      # count.
      for id <- ~w(s1 s2) do
        sandbox_fixture(account: account, agent_environment_id: agent_environment.id, anthropic_session_id: id)
      end

      sandbox_fixture(account: account, platform: :darwin, repository: "acme/other", template: "macos-xcode-27-2")
      sandbox_fixture(account: account, platform: :darwin, repository: "acme/app", template: "macos-xcode-27-0")
      sandbox_fixture(account: account, platform: :darwin, repository: "acme/app", template: "macos-xcode-27-2")

      sandbox_fixture(
        account: account,
        platform: :darwin,
        repository: "acme/app",
        template: "macos-xcode-27-2",
        state: :error
      )

      refute DiskSnapshots.queue_copies(snapshot)

      sandbox_fixture(account: account, platform: :darwin, repository: "acme/app", template: "macos-xcode-27-2")

      assert DiskSnapshots.queue_copies(snapshot)
    end

    test "a failed copy gives its reservation back" do
      snapshot = popular_snapshot()
      stub(Nodes, :connected_nodes, fn -> [copy_node("node-a"), copy_node("node-b")] end)

      expect(Nodes, :call, fn "node-b", "copy_disks", _args, _opts -> {:error, "restoring archive: checksum mismatch"} end)

      assert {:error, "restoring archive: checksum mismatch"} = DiskSnapshots.copy(snapshot)
      assert Repo.all(DiskSnapshotCopy) == []
    end

    test "node reports keep copies and forget the ones their node lost" do
      snapshot = popular_snapshot()
      kept = disk_snapshot_copy_fixture(snapshot, node_name: "node-b")
      copying = disk_snapshot_copy_fixture(snapshot, node_name: "node-c", state: :copying)
      lost = disk_snapshot_copy_fixture(popular_snapshot(), node_name: "node-b")
      Repo.update_all(from(c in DiskSnapshotCopy, where: c.id == ^lost.id), set: [updated_at: ~U[2026-01-01 00:00:00Z]])
      reject(&Nodes.call/4)

      assert :ok = DiskSnapshots.reconcile_node_report("node-b", %{"disk_snapshots" => [%{"id" => snapshot.id}]})
      assert :ok = DiskSnapshots.reconcile_node_report("node-c", %{"disk_snapshots" => []})

      assert Repo.reload(kept)
      assert Repo.reload(copying)
      refute Repo.reload(lost)
    end

    test "deleting a snapshot, as a refresh under a new id does, removes its copies from their nodes" do
      snapshot = popular_snapshot()
      disk_snapshot_copy_fixture(snapshot, node_name: "node-b")
      expect(Storage, :delete_object, fn "snapshot-key", _account -> :ok end)

      expect(Nodes, :call, 2, fn node, "delete_disks", %{snapshot_id: id}, _opts when id == snapshot.id ->
        assert node in ["node-a", "node-b"]
        {:ok, %{}}
      end)

      assert :ok = DiskSnapshots.delete(snapshot)
      assert Repo.all(DiskSnapshotCopy) == []
    end

    test "copies unused for a day are dropped" do
      snapshot = popular_snapshot()

      unused =
        disk_snapshot_copy_fixture(snapshot,
          node_name: "node-b",
          last_used_at: DateTime.add(DateTime.utc_now(), -25 * 3600)
        )

      used =
        disk_snapshot_copy_fixture(snapshot,
          node_name: "node-c",
          last_used_at: DateTime.add(DateTime.utc_now(), -23 * 3600)
        )

      expect(Nodes, :call, fn "node-b", "delete_disks", _args, _opts -> {:ok, %{}} end)

      DiskSnapshots.delete_expired()

      refute Repo.reload(unused)
      assert Repo.reload(used)
      assert Repo.reload(snapshot)
    end

    test "a node that needs room drops its least recently used copy before archiving an Orb" do
      stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)

      older =
        disk_snapshot_copy_fixture(popular_snapshot(),
          node_name: "node-b",
          last_used_at: DateTime.add(DateTime.utc_now(), -3600)
        )

      newer = disk_snapshot_copy_fixture(popular_snapshot(), node_name: "node-b")

      sandbox_fixture(
        amp_orb_id: "amp-idle",
        node_name: "node-b",
        state: :paused,
        paused_at: DateTime.add(DateTime.utc_now(), -3600)
      )

      stub(Nodes, :call, fn "node-b", "delete_disks", _args, _opts -> {:ok, %{}} end)
      reserved = Capacity.reserved_disk_bytes(copy_node("node-b"))

      assert Archives.make_node_room(["node-b"])

      refute Repo.reload(older)
      assert Repo.reload(newer)
      refute_enqueued(worker: ArchiveSandboxesWorker)
      assert Capacity.reserved_disk_bytes(copy_node("node-b")) < reserved
    end

    test "the disk-pressure sweep keeps a copy used in the last hour and archives an idle Orb instead" do
      stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
      stub(Nodes, :call, fn "node-b", "delete_disks", _args, _opts -> {:ok, %{}} end)

      # An Orb was just spawned on this copy, which is what pushed the node over.
      used = disk_snapshot_copy_fixture(popular_snapshot(), node_name: "node-b")

      sandbox_fixture(
        amp_orb_id: "amp-idle",
        node_name: "node-b",
        state: :paused,
        paused_at: DateTime.add(DateTime.utc_now(), -3600)
      )

      assert Archives.make_node_room(["node-b"], disk_pressure: true)
      assert Repo.reload(used)
      assert_enqueued(worker: ArchiveSandboxesWorker, args: %{node_names: ["node-b"], disk_pressure: true})

      # A copy idle for over an hour still goes first.
      idle =
        disk_snapshot_copy_fixture(popular_snapshot(),
          node_name: "node-b",
          last_used_at: DateTime.add(DateTime.utc_now(), -61 * 60)
        )

      assert Archives.make_node_room(["node-b"], disk_pressure: true)
      refute Repo.reload(idle)
      assert Repo.reload(used)

      # A node that refused a sandbox still gives up even a just-used copy.
      assert Archives.make_node_room(["node-b"])
      refute Repo.reload(used)
    end

    test "with no copy left, a node gives up its archived snapshots' node copies before archiving an Orb" do
      stub(Environment, :sandbox_archive_after_hours, fn -> 24 end)
      stub(Nodes, :call, fn "node-b", "delete_disks", _args, _opts -> {:ok, %{}} end)
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2 * 3600)

      idle = popular_snapshot(node_name: "node-b", last_used_at: two_hours_ago)
      used = popular_snapshot(node_name: "node-b", amp_snapshot_id: "proj-2")
      # Not archived yet: the node holds its only copy.
      only = disk_snapshot_fixture(node_name: "node-b", last_used_at: DateTime.add(DateTime.utc_now(), -3 * 3600))

      sandbox_fixture(
        amp_orb_id: "amp-idle",
        node_name: "node-b",
        state: :paused,
        paused_at: DateTime.add(DateTime.utc_now(), -3600)
      )

      reserved = Capacity.reserved_disk_bytes(copy_node("node-b"))

      assert Archives.make_node_room(["node-b"], disk_pressure: true)
      assert %DiskSnapshot{node_name: nil} = Repo.reload!(idle)
      assert Capacity.reserved_disk_bytes(copy_node("node-b")) < reserved
      refute_enqueued(worker: ArchiveSandboxesWorker)

      # The sweep keeps one used in the last hour and archives an idle Orb instead.
      assert Archives.make_node_room(["node-b"], disk_pressure: true)
      assert Repo.reload!(used).node_name == "node-b"
      assert_enqueued(worker: ArchiveSandboxesWorker, args: %{node_names: ["node-b"], disk_pressure: true})

      # A node that refused a sandbox gives it up too, never the only copy.
      assert Archives.make_node_room(["node-b"])
      assert %DiskSnapshot{node_name: nil} = Repo.reload!(used)
      assert Repo.reload!(only).node_name == "node-b"
    end
  end
end
