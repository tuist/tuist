defmodule Cache.KeyValueReplicationShipperTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry, as: DistributedEntry
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

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    stub(Cleanup, :latest_project_cleanup_cutoff, fn _account, _project -> nil end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)

    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    stub(KeyValueEntries, :clear_replication_token, fn "keyvalue:acme:ios:cas", ^token ->
      send(parent, :token_cleared)
      1
    end)

    stub(DistributedRepo, :transaction, fn fun, _opts ->
      fun.()
      {:ok, :ok}
    end)

    stub(DistributedRepo, :get, fn DistributedEntry, "keyvalue:acme:ios:cas" -> nil end)

    stub(DistributedRepo, :insert!, fn changeset ->
      assert changeset.changes.account_handle == "acme"
      assert changeset.changes.project_handle == "ios"
      assert changeset.changes.cas_id == "cas"
      assert changeset.changes.source_node == "test-node"
      send(parent, :inserted)
      %DistributedEntry{}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :inserted
    assert_receive :token_cleared
  end
end
