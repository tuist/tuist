defmodule Tuist.Sandboxes.DiskSnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Storage

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
end
