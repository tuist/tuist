defmodule Cache.DistributedKV.LogicTest do
  use ExUnit.Case, async: true

  alias Cache.DistributedKV.Logic

  test "compare_source_versions uses source_node as equal-timestamp tie-breaker" do
    timestamp = DateTime.utc_now()

    assert Logic.compare_source_versions(timestamp, "node-b", timestamp, "node-a") == :gt
    assert Logic.compare_source_versions(timestamp, "node-a", timestamp, "node-b") == :lt
  end

  test "merge_shared_entry keeps tombstone for stale writes" do
    now = DateTime.utc_now()
    source_updated_at = DateTime.add(now, -120, :second)
    deleted_at = DateTime.add(now, -60, :second)

    existing = %{
      source_updated_at: source_updated_at,
      source_node: "node-a",
      json_payload: "old",
      last_accessed_at: source_updated_at,
      deleted_at: deleted_at
    }

    incoming = %{
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      source_updated_at: source_updated_at,
      source_node: "node-b",
      json_payload: "new",
      last_accessed_at: now
    }

    merged = Logic.merge_shared_entry(existing, incoming, now)

    assert merged.deleted_at == deleted_at
    assert merged.last_accessed_at == now
  end

  test "merge_shared_entry clears tombstone for newer writes" do
    now = DateTime.utc_now()
    deleted_at = DateTime.add(now, -120, :second)
    fresh_write = DateTime.add(now, -60, :second)

    existing = %{
      source_updated_at: deleted_at,
      source_node: "node-a",
      json_payload: "old",
      last_accessed_at: deleted_at,
      deleted_at: deleted_at
    }

    incoming = %{
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      source_updated_at: fresh_write,
      source_node: "node-b",
      json_payload: "new",
      last_accessed_at: now
    }

    merged = Logic.merge_shared_entry(existing, incoming, now)

    assert is_nil(merged.deleted_at)
    assert merged.json_payload == "new"
  end
end
