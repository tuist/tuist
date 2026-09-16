defmodule Tuist.ClickHouse.ParityTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouse.Parity

  describe "ttl_expression/1" do
    test "reads the expression a table's TTL deletes rows by" do
      engine_full =
        "MergeTree PARTITION BY toYYYYMMDD(inserted_at) ORDER BY (inserted_at, id) TTL inserted_at + toIntervalDay(30) SETTINGS index_granularity = 8192"

      assert Parity.ttl_expression(engine_full) == "inserted_at + toIntervalDay(30)"
    end

    test "reads it from a replicated engine and drops an explicit DELETE" do
      engine_full =
        "ReplicatedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}') PARTITION BY toYYYYMMDD(inserted_at) ORDER BY (inserted_at, id) TTL inserted_at + toIntervalDay(30) DELETE SETTINGS index_granularity = 8192"

      assert Parity.ttl_expression(engine_full) == "inserted_at + toIntervalDay(30)"
    end

    test "is nil for a table without a TTL" do
      assert Parity.ttl_expression("MergeTree ORDER BY id SETTINGS index_granularity = 8192") == nil
    end

    test "is nil for a TTL that moves data or has more than one rule" do
      # Neither is a single expression rows are deleted by, so a table with one
      # is compared as before rather than over a guessed window.
      assert Parity.ttl_expression(
               "MergeTree ORDER BY id TTL d + toIntervalDay(7) TO VOLUME 'cold' SETTINGS index_granularity = 8192"
             ) ==
               nil

      assert Parity.ttl_expression("MergeTree ORDER BY id TTL d + toIntervalDay(7), d + toIntervalDay(30) DELETE") == nil
    end
  end
end
