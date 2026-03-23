defmodule Cache.KeyValueReplicationShipperTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueReplicationShipper

  setup :set_mimic_from_context

  setup do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)
    stub(Config, :distributed_kv_node_name, fn -> "test-node" end)
    :ok
  end

  test "shared entries keep microsecond precision in updated_at" do
    now = ~U[2026-03-12 12:00:00.123456Z]

    expect(Repo, :insert_all, fn Entry, rows, opts ->
      assert [%{updated_at: ^now}] = rows
      assert Entry.__schema__(:type, :updated_at) == :utc_datetime_usec
      assert {:ok, _} = Ecto.Type.dump(Entry.__schema__(:type, :updated_at), now)
      assert opts[:conflict_target] == :key
      assert opts[:timeout]
      {1, nil}
    end)

    assert :ok =
             KeyValueReplicationShipper.upsert_shared_entries(
               [
                 %{
                   key: "keyvalue:acme:ios:cas",
                   account_handle: "acme",
                   project_handle: "ios",
                   cas_id: "cas",
                   json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
                   source_node: "node-a",
                   source_updated_at: now,
                   last_accessed_at: now
                 }
               ],
               now
             )
  end

  test "ships pending rows and clears the shipped token" do
    parent = self()
    token = DateTime.utc_now()
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    stub(Cleanup, :latest_project_cleanup_cutoffs, fn _scopes -> %{} end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)

    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    stub(KeyValueEntries, :clear_replication_token, fn "keyvalue:acme:ios:cas", ^token ->
      send(parent, :token_cleared)
      1
    end)

    stub(Repo, :insert_all, fn Entry, rows, opts ->
      assert [row] = rows
      assert row.key == "keyvalue:acme:ios:cas"
      assert row.account_handle == "acme"
      assert row.project_handle == "ios"
      assert row.cas_id == "cas"
      assert row.json_payload == json_payload
      assert row.source_node == "test-node"
      assert row.source_updated_at == token
      assert row.last_accessed_at == token
      assert %DateTime{} = row.updated_at
      assert opts[:conflict_target] == :key
      assert opts[:timeout]
      send(parent, :upserted)
      {1, nil}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :upserted
    assert_receive :token_cleared
  end

  test "batches shared repo work for one flush" do
    parent = self()
    token = DateTime.utc_now()

    pending_entries = [
      %KeyValueEntry{
        key: "keyvalue:acme:ios:cas-a",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-a"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      },
      %KeyValueEntry{
        key: "keyvalue:acme:ios:cas-b",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-b"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      }
    ]

    expect(Cleanup, :latest_project_cleanup_cutoffs, fn scopes ->
      assert Enum.map(scopes, &{&1.account_handle, &1.project_handle}) == [{"acme", "ios"}, {"acme", "ios"}]
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> pending_entries end)

    expect(KeyValueEntries, :clear_replication_token, 2, fn key, ^token ->
      assert key in ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      send(parent, {:token_cleared, key})
      1
    end)

    expect(Repo, :insert_all, fn Entry, rows, opts ->
      assert length(rows) == 2
      assert Enum.map(rows, & &1.key) == ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      assert Enum.map(rows, & &1.cas_id) == ["cas-a", "cas-b"]
      assert Enum.all?(rows, &(&1.source_node == "test-node"))
      assert %DateTime{} = hd(rows).updated_at
      assert opts[:conflict_target] == :key
      assert opts[:timeout]
      send(parent, :upsert_batch)
      {2, nil}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :cutoffs_loaded
    assert_receive :upsert_batch
    assert_receive {:token_cleared, _}
    assert_receive {:token_cleared, _}
  end

  test "reloads cleanup cutoffs on each flush" do
    parent = self()
    token = DateTime.utc_now()

    stub(Config, :distributed_kv_ship_interval_ms, fn -> 60_000 end)

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    expect(Cleanup, :latest_project_cleanup_cutoffs, 2, fn _scopes ->
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)
    stub(KeyValueEntries, :clear_replication_token, fn _key, _token -> 1 end)
    stub(Repo, :insert_all, fn _schema, _rows, _opts -> {1, nil} end)

    start_supervised!(KeyValueReplicationShipper)
    assert_receive :cutoffs_loaded

    assert :ok = KeyValueReplicationShipper.flush_now()
    assert_receive :cutoffs_loaded
  end

  test "same-second cleanup cutoffs do not discard pending rows" do
    parent = self()
    entry_updated_at = ~U[2026-03-12 12:00:00.050000Z]
    cleanup_started_at = ~U[2026-03-12 12:00:00.900000Z]
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      last_accessed_at: entry_updated_at,
      source_updated_at: entry_updated_at,
      replication_enqueued_at: entry_updated_at
    }

    expect(Cleanup, :latest_project_cleanup_cutoffs, fn _scopes ->
      %{{"acme", "ios"} => cleanup_started_at}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    expect(KeyValueEntries, :clear_replication_token, fn "keyvalue:acme:ios:cas", ^entry_updated_at ->
      send(parent, :token_cleared)
      1
    end)

    expect(Repo, :insert_all, fn Entry, rows, _opts ->
      assert [%{key: "keyvalue:acme:ios:cas"}] = rows
      send(parent, :upserted)
      {1, nil}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :upserted
    assert_receive :token_cleared
  end
end
