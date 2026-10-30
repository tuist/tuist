defmodule Tuist.Sandboxes.DiskSnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Nodes

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

    test "leaves rows alone when the daemon does not report disk snapshots" do
      snapshot = backdate(disk_snapshot_fixture(node_name: "node-a"), :updated_at, 600)
      reject(&Nodes.call/4)
      assert :ok = DiskSnapshots.reconcile_node_report("node-a", %{"sandboxes" => []})
      assert Repo.reload(snapshot)
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
