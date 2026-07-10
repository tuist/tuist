defmodule Tuist.ClickHouseRetentionTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouseRetention

  describe "configured_targets/1" do
    test "does not apply product-data retention by default" do
      assert ClickHouseRetention.configured_targets(%{}) == []
    end

    test "applies a default retention window to all known ClickHouse domains" do
      targets =
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_DEFAULT_DAYS" => "30"
        })

      assert Enum.any?(targets, &(&1.table == "build_runs" and &1.days == 30))
      assert Enum.any?(targets, &(&1.table == "test_case_runs" and &1.days == 30))
      assert Enum.any?(targets, &(&1.table == "command_events" and &1.days == 30))
    end

    test "domain retention overrides the default retention window" do
      targets =
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_DEFAULT_DAYS" => "30",
          "TUIST_CLICKHOUSE_RETENTION_TESTS_DAYS" => "14"
        })

      assert Enum.find(targets, &(&1.table == "test_case_runs")).days == 14
      assert Enum.find(targets, &(&1.table == "build_runs")).days == 30
    end

    test "domain retention can disable a domain when a default is set" do
      targets =
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_DEFAULT_DAYS" => "30",
          "TUIST_CLICKHOUSE_RETENTION_WEBHOOKS_DAYS" => "0"
        })

      refute Enum.any?(targets, &(&1.table == "webhook_delivery_attempts"))
      assert Enum.any?(targets, &(&1.table == "build_runs"))
    end

    test "table retention overrides domain retention" do
      targets =
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_TESTS_DAYS" => "30",
          "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON" => ~s({"test_case_runs": 7})
        })

      assert Enum.find(targets, &(&1.table == "test_case_runs")).days == 7
      assert Enum.find(targets, &(&1.table == "test_runs")).days == 30
    end

    test "table retention can disable a table when its domain is enabled" do
      targets =
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_TESTS_DAYS" => "30",
          "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON" => ~s({"test_case_runs": 0})
        })

      refute Enum.any?(targets, &(&1.table == "test_case_runs"))
      assert Enum.any?(targets, &(&1.table == "test_runs"))
    end

    test "raises on invalid retention days" do
      assert_raise ArgumentError, ~r/TUIST_CLICKHOUSE_RETENTION_TESTS_DAYS/, fn ->
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_TESTS_DAYS" => "two-weeks"
        })
      end
    end

    test "raises on unknown table retention overrides" do
      assert_raise ArgumentError, ~r/unknown table/, fn ->
        ClickHouseRetention.configured_targets(%{
          "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON" => ~s({"unknown_table": 7})
        })
      end
    end
  end

  describe "alter_table_statement/3" do
    test "quotes ClickHouse table and column identifiers" do
      assert ClickHouseRetention.alter_table_statement("test_case_runs", "inserted_at", 14) ==
               "ALTER TABLE `test_case_runs` MODIFY TTL `inserted_at` + INTERVAL 14 DAY DELETE"
    end
  end
end
