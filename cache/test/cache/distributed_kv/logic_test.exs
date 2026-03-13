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

  test "racing stale and fresh writes converge on the same winner regardless of apply order" do
    now = DateTime.utc_now()
    deleted_at = DateTime.add(now, -120, :second)
    stale_write = DateTime.add(now, -180, :second)
    fresh_write = DateTime.add(now, -60, :second)

    existing = %{
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      source_updated_at: stale_write,
      source_node: "node-seed",
      json_payload: "seed",
      last_accessed_at: stale_write,
      deleted_at: deleted_at
    }

    stale_incoming = %{
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      source_updated_at: stale_write,
      source_node: "node-stale",
      json_payload: "stale",
      last_accessed_at: deleted_at
    }

    fresh_incoming = %{
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      source_updated_at: fresh_write,
      source_node: "node-fresh",
      json_payload: "fresh",
      last_accessed_at: fresh_write
    }

    stale_then_fresh =
      existing
      |> Logic.merge_shared_entry(stale_incoming, now)
      |> Logic.merge_shared_entry(fresh_incoming, now)

    fresh_then_stale =
      existing
      |> Logic.merge_shared_entry(fresh_incoming, now)
      |> Logic.merge_shared_entry(stale_incoming, now)

    expected = %{
      json_payload: "fresh",
      source_node: "node-fresh",
      source_updated_at: fresh_write,
      last_accessed_at: fresh_write,
      deleted_at: nil
    }

    assert Map.take(stale_then_fresh, Map.keys(expected)) == expected
    assert Map.take(fresh_then_stale, Map.keys(expected)) == expected
  end
end
