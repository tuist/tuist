defmodule Cache.DistributedKV.LogicTest do
  use ExUnit.Case, async: true

  alias Cache.DistributedKV.Logic

  test "compare_source_versions uses source_node as equal-timestamp tie-breaker" do
    timestamp = DateTime.utc_now()

    assert Logic.compare_source_versions(timestamp, "node-b", timestamp, "node-a") == :gt
    assert Logic.compare_source_versions(timestamp, "node-a", timestamp, "node-b") == :lt
  end

  test "compare_source_versions orders nil timestamps before present ones" do
    timestamp = DateTime.utc_now()

    assert Logic.compare_source_versions(nil, "node-a", timestamp, "node-b") == :lt
    assert Logic.compare_source_versions(timestamp, "node-a", nil, "node-b") == :gt
    assert Logic.compare_source_versions(nil, "node-a", nil, "node-b") == :eq
  end

  test "max_datetime keeps the newest non-nil value" do
    older = DateTime.add(DateTime.utc_now(), -60, :second)
    newer = DateTime.add(older, 30, :second)

    assert Logic.max_datetime(older, newer) == newer
    assert Logic.max_datetime(newer, older) == newer
    assert Logic.max_datetime(nil, newer) == newer
    assert Logic.max_datetime(older, nil) == older
  end
end
