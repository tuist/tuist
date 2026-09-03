defmodule Tuist.ClickHouse.SchemaCloneTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouse.SchemaClone

  describe "rewrite/3" do
    test "maps every Cloud Shared engine onto its self-managed Replicated equivalent" do
      for {shared, replicated} <- [
            {"SharedMergeTree", "ReplicatedMergeTree"},
            {"SharedReplacingMergeTree", "ReplicatedReplacingMergeTree"},
            {"SharedAggregatingMergeTree", "ReplicatedAggregatingMergeTree"},
            {"SharedSummingMergeTree", "ReplicatedSummingMergeTree"}
          ] do
        ddl =
          "CREATE TABLE default.t (`id` UUID) ENGINE = #{shared}('/clickhouse/tables/{uuid}/{shard}', '{replica}') ORDER BY id"

        assert SchemaClone.rewrite(ddl, "default", "tuist") =~ "ENGINE = #{replicated}("
        refute SchemaClone.rewrite(ddl, "default", "tuist") =~ "Shared"
      end
    end

    test "keeps the Keeper path arguments the source emits" do
      # The destination is configured with
      # `database_replicated_allow_replicated_engine_arguments = 2`, which
      # accepts these and substitutes its own defaults. Stripping them here
      # would work too, but it would mean parsing the argument list to tell a
      # path from a version column, and getting that wrong silently changes
      # the deduplication key of a ReplacingMergeTree.
      ddl =
        "CREATE TABLE default.build_runs (`id` UUID) ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', updated_at) ORDER BY id"

      rewritten = SchemaClone.rewrite(ddl, "default", "tuist")

      assert rewritten =~ "ReplicatedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', updated_at)"
    end

    test "requalifies the database in both the target and the view's own select" do
      ddl =
        "CREATE MATERIALIZED VIEW default.mv TO default.target (`id` UUID) AS SELECT id FROM default.source"

      rewritten = SchemaClone.rewrite(ddl, "default", "tuist")

      assert rewritten =~ "CREATE MATERIALIZED VIEW IF NOT EXISTS tuist.mv TO tuist.target"
      assert rewritten =~ "FROM tuist.source"
      refute rewritten =~ "default."
    end

    test "is idempotent so a partial clone can be re-run" do
      ddl = "CREATE TABLE default.t (`id` UUID) ENGINE = SharedMergeTree ORDER BY id"

      once = SchemaClone.rewrite(ddl, "default", "tuist")
      twice = SchemaClone.rewrite(once, "tuist", "tuist")

      assert once =~ "CREATE TABLE IF NOT EXISTS tuist.t"
      assert twice == once
    end

    test "leaves an already self-managed source untouched apart from the database" do
      ddl =
        "CREATE TABLE default.t (`id` UUID) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}') ORDER BY id"

      rewritten = SchemaClone.rewrite(ddl, "default", "tuist")

      assert rewritten =~ "ENGINE = ReplicatedMergeTree("
      assert rewritten =~ "tuist.t"
    end

    test "preserves indexes, projections and default expressions" do
      # Taken from the real production `command_events`, which is the widest
      # DDL in the database: eleven skip indexes, a projection, and columns
      # whose defaults are expressions over other columns.
      ddl = """
      CREATE TABLE default.command_events (`id` UUID, `legacy_id` UInt64 DEFAULT generateSerialID('command_events_legacy_id'), \
      `cacheable_targets` Array(String), `cacheable_targets_count` UInt32 DEFAULT length(cacheable_targets), \
      INDEX idx_name name TYPE bloom_filter GRANULARITY 4, PROJECTION proj_by_id (SELECT * ORDER BY id)) \
      ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}') ORDER BY id
      """

      rewritten = SchemaClone.rewrite(ddl, "default", "tuist")

      assert rewritten =~ "INDEX idx_name name TYPE bloom_filter GRANULARITY 4"
      assert rewritten =~ "PROJECTION proj_by_id (SELECT * ORDER BY id)"
      assert rewritten =~ "DEFAULT generateSerialID('command_events_legacy_id')"
      assert rewritten =~ "DEFAULT length(cacheable_targets)"
      assert rewritten =~ "ENGINE = ReplicatedMergeTree("
    end
  end

  describe "run/1" do
    test "does nothing when no destination is configured" do
      # `TUIST_CLICKHOUSE_BARE_METAL_URL` is unset in test, so this must not
      # try to start a repository that is not configured.
      assert {:error, :no_target_configured} = SchemaClone.run()
    end
  end
end
