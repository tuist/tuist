defmodule Atlas.Finance.Providers.HelpersTest do
  use ExUnit.Case, async: true

  alias Atlas.Finance.Providers.Helpers

  describe "datetime/1" do
    test "normalizes datetime values to UTC datetimes truncated to seconds" do
      assert Helpers.datetime(nil) == nil
      assert Helpers.datetime("invalid") == nil
      assert Helpers.datetime(123) == nil

      assert Helpers.datetime(~U[2026-05-26 12:30:15.123456Z]) ==
               ~U[2026-05-26 12:30:15Z]

      assert Helpers.datetime(~N[2026-05-26 12:30:15.123456]) ==
               ~U[2026-05-26 12:30:15Z]

      assert Helpers.datetime("2026-05-26T14:30:15.123456+02:00") ==
               ~U[2026-05-26 12:30:15Z]

      assert Helpers.datetime("2026-05-26T12:30:15.123456") ==
               ~U[2026-05-26 12:30:15Z]
    end
  end

  describe "decimal/1" do
    test "normalizes decimal-compatible values" do
      decimal = Decimal.new("12.34")

      assert Helpers.decimal(nil) == nil
      assert Helpers.decimal(decimal) == decimal
      assert Decimal.equal?(Helpers.decimal(12), Decimal.new(12))
      assert Decimal.equal?(Helpers.decimal(12.5), Decimal.from_float(12.5))
      assert Decimal.equal?(Helpers.decimal(" 12.34 "), Decimal.new("12.34"))
      assert Helpers.decimal("12.34 EUR") == nil
      assert Helpers.decimal(%{}) == nil
    end
  end

  describe "presence/1" do
    test "trims strings and drops blank values" do
      assert Helpers.presence(nil) == nil
      assert Helpers.presence("") == nil
      assert Helpers.presence("   ") == nil
      assert Helpers.presence("  Tuist  ") == "Tuist"
      assert Helpers.presence(123) == 123
    end
  end

  describe "compact_map/1" do
    test "removes empty values from a map" do
      assert Helpers.compact_map(%{
               empty_list: [],
               empty_map: %{},
               empty_string: "",
               false_value: false,
               nested: %{id: "acc_123"},
               nil_value: nil,
               zero: 0
             }) == %{
               false_value: false,
               nested: %{id: "acc_123"},
               zero: 0
             }

      assert Helpers.compact_map(nil) == %{}
      assert Helpers.compact_map("invalid") == %{}
    end
  end

  describe "stable_hash/1" do
    test "returns a stable sha256 hash for JSON-encodable terms" do
      left = Helpers.stable_hash(%{external_id: "txn_123", amount: "12.34"})
      right = Helpers.stable_hash(%{amount: "12.34", external_id: "txn_123"})

      assert left == right
      assert String.length(left) == 64
      assert left =~ ~r/^[0-9a-f]+$/
    end
  end

  describe "max_datetime/2" do
    test "returns the newest non-nil datetime" do
      earlier = ~U[2026-05-26 12:00:00Z]
      later = ~U[2026-05-26 13:00:00Z]

      assert Helpers.max_datetime(nil, later) == later
      assert Helpers.max_datetime(earlier, nil) == earlier
      assert Helpers.max_datetime(earlier, later) == later
      assert Helpers.max_datetime(later, earlier) == later
      assert Helpers.max_datetime(later, later) == later
    end
  end
end
