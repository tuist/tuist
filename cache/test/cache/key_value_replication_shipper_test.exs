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
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup_all do
    ensure_distributed_repo_storage!()

    case start_supervised(Repo) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.run(&1, :up, all: true))

    :ok
  end

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all(Entry)
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)
    stub(Config, :distributed_kv_node_name, fn -> "test-node" end)
    :ok
  end

  test "shared entries keep microsecond precision in updated_at" do
    source_updated_at = ~U[2026-03-12 12:00:00.123456Z]

    assert :ok =
             KeyValueReplicationShipper.upsert_shared_entries([
               %{
                 key: "keyvalue:acme:ios:cas",
                 account_handle: "acme",
                 project_handle: "ios",
                 cas_id: "cas",
                 json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
                 source_node: "node-a",
                 source_updated_at: source_updated_at,
                 last_accessed_at: source_updated_at
               }
             ])

    record = Repo.get!(Entry, "keyvalue:acme:ios:cas")
    assert record.source_updated_at == source_updated_at
    assert record.updated_at != source_updated_at
    assert Entry.__schema__(:type, :updated_at) == :utc_datetime_usec
    assert {:ok, _} = Ecto.Type.dump(Entry.__schema__(:type, :updated_at), record.updated_at)
  end

  test "shared entry inserts use database time expressions for replication ordering" do
    source_updated_at = ~U[2026-03-12 12:00:00.123456Z]

    expect(Repo, :insert_all, fn Entry, %Ecto.Query{} = query, opts ->
      {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)

      assert sql =~ "clock_timestamp()"
      assert inspect(opts[:on_conflict]) =~ "clock_timestamp()"
      assert opts[:conflict_target] == :key
      assert opts[:timeout]

      {1, nil}
    end)

    assert :ok =
             KeyValueReplicationShipper.upsert_shared_entries([
               %{
                 key: "keyvalue:acme:ios:cas",
                 account_handle: "acme",
                 project_handle: "ios",
                 cas_id: "cas",
                 json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
                 source_node: "node-a",
                 source_updated_at: source_updated_at,
                 last_accessed_at: source_updated_at
               }
             ])
  end

  test "shared entry conflict updates refresh updated_at" do
    source_updated_at = ~U[2026-03-12 12:00:00.123456Z]

    assert :ok =
             KeyValueReplicationShipper.upsert_shared_entries([
               %{
                 key: "keyvalue:acme:ios:cas",
                 account_handle: "acme",
                 project_handle: "ios",
                 cas_id: "cas",
                 json_payload: Jason.encode!(%{entries: [%{"value" => "old"}]}),
                 source_node: "node-a",
                 source_updated_at: source_updated_at,
                 last_accessed_at: source_updated_at
               }
             ])

    original = Repo.get!(Entry, "keyvalue:acme:ios:cas")
    Process.sleep(10)

    assert :ok =
             KeyValueReplicationShipper.upsert_shared_entries([
               %{
                 key: "keyvalue:acme:ios:cas",
                 account_handle: "acme",
                 project_handle: "ios",
                 cas_id: "cas",
                 json_payload: Jason.encode!(%{entries: [%{"value" => "new"}]}),
                 source_node: "node-b",
                 source_updated_at: DateTime.add(source_updated_at, 1, :second),
                 last_accessed_at: DateTime.add(source_updated_at, 1, :second)
               }
             ])

    updated = Repo.get!(Entry, "keyvalue:acme:ios:cas")
    assert DateTime.after?(updated.updated_at, original.updated_at)
  end

  test "ships pending rows and clears the shipped token" do
    parent = self()
    token = DateTime.utc_now()
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      id: 1,
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      source_node: "test-node",
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    stub(Cleanup, :effective_project_barriers, fn _scopes -> %{} end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)

    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    stub(KeyValueEntries, :clear_replication_tokens, fn [entry] ->
      assert entry.id == 1
      assert entry.key == "keyvalue:acme:ios:cas"
      assert entry.replication_enqueued_at == token
      send(parent, :token_cleared)
      1
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :token_cleared

    assert %Entry{
             account_handle: "acme",
             project_handle: "ios",
             cas_id: "cas",
             json_payload: ^json_payload,
             source_node: "test-node",
             source_updated_at: ^token,
             last_accessed_at: ^token
           } = Repo.get!(Entry, "keyvalue:acme:ios:cas")
  end

  test "access-only replication preserves the original source node" do
    parent = self()
    source_updated_at = DateTime.add(DateTime.utc_now(), -60, :second)
    replication_enqueued_at = DateTime.utc_now()

    pending_entry = %KeyValueEntry{
      id: 1,
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      last_accessed_at: replication_enqueued_at,
      source_updated_at: source_updated_at,
      replication_enqueued_at: replication_enqueued_at
    }

    stub(Cleanup, :effective_project_barriers, fn _scopes -> %{} end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    stub(KeyValueEntries, :clear_replication_tokens, fn [_entry] ->
      send(parent, :token_cleared)
      1
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :token_cleared

    assert %Entry{source_node: "node-a", source_updated_at: ^source_updated_at} =
             Repo.get!(Entry, "keyvalue:acme:ios:cas")
  end

  test "batches shared repo work for one flush" do
    parent = self()
    token = DateTime.utc_now()

    pending_entries = [
      %KeyValueEntry{
        id: 1,
        key: "keyvalue:acme:ios:cas-a",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-a"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      },
      %KeyValueEntry{
        id: 2,
        key: "keyvalue:acme:ios:cas-b",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-b"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      }
    ]

    expect(Cleanup, :effective_project_barriers, fn scopes ->
      assert Enum.map(scopes, &{&1.account_handle, &1.project_handle}) == [{"acme", "ios"}, {"acme", "ios"}]
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> pending_entries end)

    expect(KeyValueEntries, :clear_replication_tokens, fn entries ->
      assert Enum.map(entries, & &1.id) == [1, 2]
      assert Enum.map(entries, & &1.key) == ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      assert Enum.all?(entries, &(&1.replication_enqueued_at == token))
      send(parent, :tokens_cleared)
      2
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :cutoffs_loaded
    assert_receive :tokens_cleared

    assert Entry |> Repo.all() |> Enum.sort_by(& &1.key) |> Enum.map(&{&1.key, &1.cas_id, &1.source_node}) == [
             {"keyvalue:acme:ios:cas-a", "cas-a", "test-node"},
             {"keyvalue:acme:ios:cas-b", "cas-b", "test-node"}
           ]
  end

  test "reloads cleanup cutoffs on each flush" do
    parent = self()
    token = DateTime.utc_now()

    stub(Config, :distributed_kv_ship_interval_ms, fn -> 60_000 end)

    pending_entry = %KeyValueEntry{
      id: 1,
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    expect(Cleanup, :effective_project_barriers, 2, fn _scopes ->
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)
    stub(KeyValueEntries, :clear_replication_tokens, fn [_entry] -> 1 end)

    start_supervised!(KeyValueReplicationShipper)
    assert_receive :cutoffs_loaded

    assert :ok = KeyValueReplicationShipper.flush_now()
    assert_receive :cutoffs_loaded
  end

  test "same-second cleanup cutoffs do not discard pending rows" do
    parent = self()
    entry_updated_at = ~U[2026-03-12 12:00:00.050000Z]
    cleanup_started_at = ~U[2026-03-12 12:00:00Z]
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      id: 1,
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      last_accessed_at: entry_updated_at,
      source_updated_at: entry_updated_at,
      replication_enqueued_at: entry_updated_at
    }

    expect(Cleanup, :effective_project_barriers, fn _scopes ->
      %{{"acme", "ios"} => cleanup_started_at}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    expect(KeyValueEntries, :clear_replication_tokens, fn [entry] ->
      assert entry.id == 1
      assert entry.key == "keyvalue:acme:ios:cas"
      assert entry.replication_enqueued_at == entry_updated_at
      send(parent, :token_cleared)
      1
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :token_cleared
    assert %Entry{key: "keyvalue:acme:ios:cas"} = Repo.get!(Entry, "keyvalue:acme:ios:cas")
  end

  defp ensure_distributed_repo_storage! do
    case Repo.__adapter__().storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "failed to create distributed KV test database: #{inspect(reason)}"
    end
  end
end
