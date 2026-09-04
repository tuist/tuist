defmodule Tuist.ClickHouse.TablesTest do
  use ExUnit.Case, async: true

  use Mimic

  alias Tuist.ClickHouse.Tables

  describe "schema_drift/2" do
    setup do
      # Both endpoints go through the same repository module, so the stub
      # answers on the database name the way two real servers would.
      stub(Tuist.IngestRepo, :query!, fn _sql, %{"database" => database}, _opts ->
        rows =
          case database do
            "cloud" ->
              [["build_runs", "id", "UUID"], ["build_runs", "added_later", "String"], ["only_on_cloud", "id", "UUID"]]

            "in_cluster" ->
              [["build_runs", "id", "UUID"], ["only_in_cluster", "id", "UUID"]]
          end

        %{rows: rows}
      end)

      %{
        source: %{repo: Tuist.IngestRepo, database: "cloud"},
        target: %{repo: Tuist.IngestRepo, database: "in_cluster"}
      }
    end

    test "sees a table the destination does not have", %{source: source, target: target} do
      # The case that matters: every other check enumerates the destination, so
      # a table only the source has is invisible to them by construction.
      assert %{missing_on_destination: ["only_on_cloud"]} = Tables.schema_drift(source, target)
    end

    test "sees a column added to a table both have", %{source: source, target: target} do
      # What a migration that ran against one server and not the other leaves
      # behind, and what makes a mirrored write fail against the other.
      assert %{differing_columns: [{"build_runs", ["added_later String"], []}]} =
               Tables.schema_drift(source, target)
    end

    test "reports the other direction too", %{source: source, target: target} do
      assert %{missing_on_source: ["only_in_cluster"]} = Tables.schema_drift(source, target)
    end

    test "is empty when the two agree" do
      stub(Tuist.IngestRepo, :query!, fn _sql, _params, _opts -> %{rows: [["build_runs", "id", "UUID"]]} end)

      endpoint = fn database -> %{repo: Tuist.IngestRepo, database: database} end

      assert %{missing_on_destination: [], missing_on_source: [], differing_columns: []} =
               Tables.schema_drift(endpoint.("cloud"), endpoint.("in_cluster"))
    end
  end

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
