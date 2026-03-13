defmodule Cache.KeyValueReplicationShipperTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Repo, as: DistributedRepo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueReplicationShipper

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :key_value_mode, :distributed)
    Application.put_env(:cache, :distributed_kv_node_name, "test-node")
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)
    :ok
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

    stub(DistributedRepo, :query!, fn sql, params, opts ->
      assert sql =~ "INSERT INTO kv_entries"
      assert sql =~ "ON CONFLICT (key) DO UPDATE"

      assert [
               ["keyvalue:acme:ios:cas"],
               ["acme"],
               ["ios"],
               ["cas"],
               [^json_payload],
               ["test-node"],
               [^token],
               [^token],
               [updated_at]
             ] = params

      assert %DateTime{} = updated_at
      assert opts[:timeout]
      send(parent, :upserted)
      %{num_rows: 1}
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

    expect(DistributedRepo, :query!, fn sql, params, opts ->
      assert sql =~ "FROM UNNEST"
      assert Enum.at(params, 0) == ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      assert Enum.at(params, 3) == ["cas-a", "cas-b"]
      assert Enum.at(params, 5) == ["test-node", "test-node"]
      assert length(Enum.at(params, 8)) == 2
      assert opts[:timeout]
      send(parent, :upsert_batch)
      %{num_rows: 2}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :cutoffs_loaded
    assert_receive :upsert_batch
    assert_receive {:token_cleared, _}
    assert_receive {:token_cleared, _}
  end
end
