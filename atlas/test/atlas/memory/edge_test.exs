defmodule Atlas.Memory.EdgeTest do
  use Atlas.DataCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Memory
  alias Atlas.Memory.Edge
  alias Atlas.Memory.Node

  describe "create_edge/1" do
    test "inserts an edge between two nodes" do
      {:ok, a} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3."})
      {:ok, b} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q4."})

      assert {:ok, %Edge{} = edge} =
               Memory.create_edge(%{src_id: b.id, dst_id: a.id, kind: :updates, weight: 0.9})

      assert edge.src_id == b.id
      assert edge.dst_id == a.id
      assert edge.kind == :updates

      activity = Repo.get_by!(Activity, action: "memory_edge.created", target_id: edge.id)
      assert activity.metadata["source_node_id"] == b.id
      assert activity.metadata["destination_node_id"] == a.id
    end

    test "is idempotent on (src, dst, kind)" do
      {:ok, a} = Memory.create_node(%{kind: :fact, body: "First."})
      {:ok, b} = Memory.create_node(%{kind: :fact, body: "Second."})

      assert {:ok, edge1} = Memory.create_edge(%{src_id: b.id, dst_id: a.id, kind: :related_to})
      assert {:ok, edge2} = Memory.create_edge(%{src_id: b.id, dst_id: a.id, kind: :related_to})

      assert edge1.id == edge2.id
    end

    test "rejects self-edges" do
      {:ok, a} = Memory.create_node(%{kind: :fact, body: "First."})

      assert {:error, changeset} =
               Memory.create_edge(%{src_id: a.id, dst_id: a.id, kind: :related_to})

      refute changeset.valid?
    end
  end

  describe "search_nodes/2 supersession" do
    test "drops a node that has been updated by another node in the result set" do
      {:ok, old} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, new} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q4 2026."})
      {:ok, _} = Memory.create_edge(%{src_id: new.id, dst_id: old.id, kind: :updates})

      ids = Memory.search_nodes("Acme") |> Enum.map(& &1.id)

      assert new.id in ids
      refute old.id in ids
    end

    test "keeps a superseded node when its updater is not in the result set" do
      {:ok, old} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, new} = Memory.create_node(%{kind: :fact, body: "Pat prefers Loom."})
      {:ok, _} = Memory.create_edge(%{src_id: new.id, dst_id: old.id, kind: :updates})

      assert [%{id: id}] = Memory.search_nodes("Acme")
      assert id == old.id
    end
  end

  describe "search_nodes/2 contradiction" do
    test "drops the older of two contradicting nodes when both are in the result set" do
      {:ok, older} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3."})
      {:ok, newer} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q4."})
      {:ok, _} = Memory.create_edge(%{src_id: newer.id, dst_id: older.id, kind: :contradicts})

      backdate!(older, 60)

      ids = Memory.search_nodes("Acme") |> Enum.map(& &1.id)

      assert newer.id in ids
      refute older.id in ids
    end

    test "drops the older node when the edge points away from it" do
      {:ok, older} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3."})
      {:ok, newer} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q4."})
      {:ok, _} = Memory.create_edge(%{src_id: older.id, dst_id: newer.id, kind: :contradicts})

      # The pair above reaches the resolver in the order the edge was written, so
      # dropping the destination would be enough to satisfy the test with the
      # edge pointing the other way. Here the destination is the node that has to
      # survive, which leaves `inserted_at` as the only thing that can pick the
      # loser. `timestamps()` stores whole seconds, so without the backdate the
      # two nodes tie and the newer one is the one dropped.
      backdate!(older, 60)

      ids = Memory.search_nodes("Acme") |> Enum.map(& &1.id)

      assert newer.id in ids
      refute older.id in ids
    end
  end

  defp backdate!(node, seconds) do
    Node
    |> where([n], n.id == ^node.id)
    |> Repo.update_all(set: [inserted_at: NaiveDateTime.add(node.inserted_at, -seconds, :second)])
  end
end
