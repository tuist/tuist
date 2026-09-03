defmodule Tuist.ClickHouse.TablesTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouse.Tables

  describe "view_target/2" do
    test "finds the table a view writes into" do
      ddl = "CREATE MATERIALIZED VIEW tuist.cas_events_daily_stats_mv TO tuist.cas_events_daily_stats AS SELECT 1"

      assert Tables.view_target(ddl, "tuist") == "cas_events_daily_stats"
    end

    test "finds it through backticks" do
      ddl = "CREATE MATERIALIZED VIEW `tuist`.`mv` TO `tuist`.`flaky_test_case_runs` AS SELECT 1"

      assert Tables.view_target(ddl, "tuist") == "flaky_test_case_runs"
    end

    test "returns nil for a view whose storage is implicit" do
      # These own an inner table instead, which was never cloned, so there is
      # nothing for the backfill to skip.
      ddl = "CREATE MATERIALIZED VIEW tuist.test_case_runs_daily_stats ENGINE = ReplicatedMergeTree AS SELECT 1"

      assert Tables.view_target(ddl, "tuist") == nil
    end

    test "ignores a target in another database" do
      ddl = "CREATE MATERIALIZED VIEW tuist.mv TO other.cas_events_daily_stats AS SELECT 1"

      assert Tables.view_target(ddl, "tuist") == nil
    end

    test "does not mistake a column or an alias named TO for a target" do
      ddl = "CREATE MATERIALIZED VIEW tuist.mv ENGINE = ReplicatedMergeTree AS SELECT a AS too FROM tuist.base"

      assert Tables.view_target(ddl, "tuist") == nil
    end
  end
end
