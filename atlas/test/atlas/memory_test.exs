defmodule Atlas.MemoryTest do
  use Atlas.DataCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Memory
  alias Atlas.Memory.Bulletin
  alias Atlas.Memory.Node
  alias Atlas.Repo
  alias Atlas.Slack.Channel

  describe "create_node/1" do
    test "creates a node and applies the default importance for the kind" do
      assert {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme is in Paris."})
      assert node.kind == :fact
      assert node.body == "Acme is in Paris."
      assert node.importance == Node.default_importance(:fact)
      assert node.scope == :global
      refute node.forgotten

      activity = Repo.get_by!(Activity, action: "memory_node.created", target_id: node.id)
      assert activity.metadata["path"] == "/admin/memory/#{node.id}"
    end

    test "honors an explicit importance" do
      assert {:ok, node} =
               Memory.create_node(%{kind: :decision, body: "Adopt RRF.", importance: 0.55})

      assert node.importance == 0.55
    end

    test "rejects an empty body" do
      assert {:error, changeset} = Memory.create_node(%{kind: :fact, body: ""})
      refute changeset.valid?
    end
  end

  describe "update_node/2" do
    test "updates editable node fields" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

      assert {:ok, updated} =
               Memory.update_node(node, %{
                 kind: "decision",
                 body: "Acme renewal moved to Q4 2026.",
                 importance: "0.85"
               })

      assert updated.kind == :decision
      assert updated.body == "Acme renewal moved to Q4 2026."
      assert updated.importance == 0.85

      activity = Repo.get_by!(Activity, action: "memory_node.updated", target_id: updated.id)
      assert activity.metadata["changed_fields"] == ["body", "importance", "kind"]
      refute Map.has_key?(activity.metadata, "changed")
      refute inspect(activity.metadata) =~ updated.body
    end

    test "rejects invalid edits" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

      assert {:error, changeset} = Memory.update_node(node, %{body: ""})
      refute changeset.valid?
    end

    test "restores forgotten nodes" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, forgotten} = Memory.forget_node(node)

      assert forgotten.forgotten

      assert {:ok, restored} = Memory.restore_node(forgotten)
      refute restored.forgotten
      assert Repo.get_by!(Activity, action: "memory_node.forgotten", target_id: node.id)
      assert Repo.get_by!(Activity, action: "memory_node.restored", target_id: node.id)
    end
  end

  describe "list_nodes/1" do
    test "filters by query and can include forgotten nodes" do
      {:ok, active} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, forgotten} = Memory.create_node(%{kind: :fact, body: "Acme prefers annual billing."})
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Globex expands to Germany."})
      {:ok, _} = Memory.forget_node(forgotten)

      assert [%Node{id: id}] = Memory.list_nodes(query: "Acme", limit: 10)
      assert id == active.id

      ids =
        Memory.list_nodes(query: "Acme", include_forgotten: true, limit: 10)
        |> Enum.map(& &1.id)

      assert active.id in ids
      assert forgotten.id in ids
    end

    test "filters by status" do
      {:ok, active} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, forgotten} = Memory.create_node(%{kind: :fact, body: "Acme prefers annual billing."})
      {:ok, _} = Memory.forget_node(forgotten)

      assert [%Node{id: id}] = Memory.list_nodes(status: :active)
      assert id == active.id

      assert [%Node{id: id}] = Memory.list_nodes(status: :forgotten)
      assert id == forgotten.id
    end
  end

  describe "search_nodes/2" do
    test "returns matching nodes by fulltext, scoped to global" do
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _} = Memory.create_node(%{kind: :preference, body: "Pat prefers Loom over Zoom."})

      results = Memory.search_nodes("Acme renewal")

      assert Enum.any?(results, &(&1.body =~ "Acme"))
      refute Enum.any?(results, &(&1.body =~ "Loom"))
    end

    test "filters by kind when given" do
      {:ok, _} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _} = Memory.create_node(%{kind: :decision, body: "Acme deal needs legal review."})

      results = Memory.search_nodes("Acme", kind: :decision)

      assert length(results) == 1
      assert hd(results).kind == :decision
    end

    test "excludes forgotten nodes" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _} = Memory.forget_node(node)

      assert Memory.search_nodes("Acme") == []
    end

    test "bumps access_count and last_accessed_at on every recall" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      assert node.access_count == 0

      _ = Memory.search_nodes("Acme")
      assert %Node{access_count: 1, last_accessed_at: %DateTime{}} = Memory.get_node(node.id)

      _ = Memory.search_nodes("Acme")
      assert %Node{access_count: 2} = Memory.get_node(node.id)
    end

    test "returns [] for a blank query" do
      assert Memory.search_nodes("") == []
      assert Memory.search_nodes("   ") == []
    end
  end

  describe "confirm_node/1 and discard_node/1" do
    test "confirm_node flips pending to confirmed" do
      {:ok, pending} =
        Memory.create_node(%{
          kind: :fact,
          body: "Acme team likes Loom recordings.",
          confirmation: :pending
        })

      assert pending.confirmation == :pending

      assert {:ok, confirmed} = Memory.confirm_node(pending)
      assert confirmed.confirmation == :confirmed
      assert Repo.get_by!(Activity, action: "memory_node.confirmed", target_id: pending.id)
    end

    test "confirm_node is idempotent on already-confirmed nodes" do
      {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3."})
      assert node.confirmation == :confirmed

      assert {:ok, same} = Memory.confirm_node(node)
      assert same.id == node.id
    end

    test "discard_node marks a pending proposal as forgotten" do
      {:ok, pending} =
        Memory.create_node(%{kind: :fact, body: "Off-the-record.", confirmation: :pending})

      assert {:ok, discarded} = Memory.discard_node(pending)
      assert discarded.forgotten
    end

    test "list_nodes excludes pending by default and includes them with include_pending" do
      {:ok, _confirmed} = Memory.create_node(%{kind: :fact, body: "Public roadmap published."})

      {:ok, pending} =
        Memory.create_node(%{
          kind: :fact,
          body: "Confidential pipeline note.",
          confirmation: :pending
        })

      bodies =
        Memory.list_nodes(scope: :global)
        |> Enum.map(& &1.body)

      assert "Public roadmap published." in bodies
      refute "Confidential pipeline note." in bodies

      pending_ids =
        Memory.list_nodes(scope: :global, confirmation: :pending, include_pending: true)
        |> Enum.map(& &1.id)

      assert pending.id in pending_ids
    end

    test "search_nodes excludes pending proposals" do
      {:ok, _pending} =
        Memory.create_node(%{
          kind: :fact,
          body: "Acme considering a renewal in Q3.",
          confirmation: :pending
        })

      assert Memory.search_nodes("Acme") == []
    end
  end

  describe "get_pending_node_by_proposal/2" do
    test "returns the pending node anchored to a (channel_id, proposal_ts) pair" do
      channel = insert_slack_channel!()

      {:ok, node} =
        Memory.create_node(%{
          kind: :fact,
          body: "Pending proposal.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1700.000200"
        })

      assert %Node{id: id} = Memory.get_pending_node_by_proposal(channel.id, "1700.000200")
      assert id == node.id
    end

    test "returns nil once the proposal has been confirmed" do
      channel = insert_slack_channel!()

      {:ok, node} =
        Memory.create_node(%{
          kind: :fact,
          body: "Pending proposal.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1700.000200"
        })

      {:ok, _confirmed} = Memory.confirm_node(node)

      assert Memory.get_pending_node_by_proposal(channel.id, "1700.000200") == nil
    end
  end

  describe "update_node/2 workflow-state protection" do
    test "ignores confirmation and proposal_slack_ts in attrs" do
      channel = insert_slack_channel!()

      {:ok, pending} =
        Memory.create_node(%{
          kind: :fact,
          body: "Pending proposal.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1700.000200"
        })

      assert pending.confirmation == :pending
      assert pending.proposal_slack_ts == "1700.000200"

      {:ok, updated} =
        Memory.update_node(pending, %{
          body: "Edited body.",
          confirmation: :confirmed,
          proposal_slack_ts: "9999.999999"
        })

      assert updated.body == "Edited body."
      assert updated.confirmation == :pending
      assert updated.proposal_slack_ts == "1700.000200"
    end
  end

  describe "upsert_bulletin/3" do
    test "inserts when none exists then updates in place" do
      assert {:ok, %Bulletin{} = first} = Memory.upsert_bulletin(:global, "First.")
      assert first.body == "First."

      assert {:ok, %Bulletin{} = second} = Memory.upsert_bulletin(:global, "Second.")
      assert second.id == first.id
      assert second.body == "Second."

      assert %Bulletin{body: "Second."} = Memory.get_bulletin(:global)
    end
  end

  defp insert_slack_channel!(attrs \\ %{}) do
    defaults = %{
      slack_app: :company,
      channel_id: "C#{System.unique_integer([:positive])}",
      channel_name: "general",
      is_shared: false,
      is_ext_shared: false
    }

    Repo.insert!(struct(Channel, Map.merge(defaults, attrs)))
  end
end
