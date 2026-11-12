defmodule Condukt.SessionStore.SnapshotTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.Snapshot

  describe "building" do
    test "stamps the current version and both timestamps" do
      snapshot = Snapshot.new(%{messages: [Message.user("hi")]})

      assert snapshot.version == Snapshot.current_version()
      assert %DateTime{} = snapshot.created_at
      assert %DateTime{} = snapshot.updated_at
    end

    # A session that has been saved before started when it started, not when it
    # was last written, or every save would reset its own age.
    test "keeps an existing creation time" do
      started = ~U[2026-01-01 00:00:00Z]
      snapshot = Snapshot.new(%{messages: [], created_at: started})

      assert snapshot.created_at == started
      assert DateTime.after?(snapshot.updated_at, started)
    end

    test "carries the identity a platform needs to attribute a session" do
      snapshot = Snapshot.new(%{id: "sess-1", actor: %{user: 7}})

      assert snapshot.id == "sess-1"
      assert snapshot.actor == %{user: 7}
    end
  end

  describe "migrating" do
    test "a current snapshot passes through unchanged" do
      snapshot = Snapshot.new(%{messages: [Message.user("hi")]})

      assert {:ok, ^snapshot} = Snapshot.migrate(snapshot)
    end

    test "a version 2 snapshot keeps its history and identity" do
      snapshot = %{
        Snapshot.new(%{id: "sess-2", actor: %{user: 8}, messages: [Message.assistant("before reasoning")]})
        | version: 2
      }

      assert {:ok, migrated} = Snapshot.migrate(snapshot)
      assert migrated == %{snapshot | version: Snapshot.current_version()}
    end

    # Version 1 had no version field at all. Those snapshots are on real disks,
    # and refusing them would throw away conversations that are otherwise
    # intact, so the absence of the field is what identifies them.
    test "a version 1 snapshot is read rather than rejected" do
      messages = [Message.user("from before"), Message.assistant("hello")]

      legacy =
        Map.merge(
          %{__struct__: Snapshot},
          %{messages: messages, model: "anthropic:old", thinking_level: :low, system_prompt: "be useful"}
        )

      assert {:ok, migrated} = Snapshot.migrate(legacy)
      assert migrated.version == Snapshot.current_version()
      assert migrated.messages == messages
      assert migrated.model == "anthropic:old"
      assert migrated.thinking_level == :low
      assert migrated.system_prompt == "be useful"
    end

    test "version 1 leaves the fields it never had empty" do
      legacy = Map.put(%{__struct__: Snapshot}, :messages, [])

      assert {:ok, migrated} = Snapshot.migrate(legacy)
      assert migrated.id == nil
      assert migrated.actor == nil
    end

    # Reading a newer snapshot would mean guessing at fields this build has
    # never seen, and the next save would write the guess back over the truth.
    test "a snapshot from a newer build is refused" do
      future = %Snapshot{version: Snapshot.current_version() + 1}

      assert {:error, {:unsupported_snapshot_version, _version}} = Snapshot.migrate(future)
    end

    test "anything that is not a snapshot is refused" do
      assert {:error, :invalid_snapshot} = Snapshot.migrate(%{messages: []})
      assert {:error, :invalid_snapshot} = Snapshot.migrate("nonsense")
    end
  end
end
