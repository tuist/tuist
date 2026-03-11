defmodule Tuist.Shards.BinPackerTest do
  use ExUnit.Case, async: true

  alias Tuist.Shards.BinPacker

  describe "pack/2" do
    test "distributes units across shards using LPT" do
      units = [{"A", 100}, {"B", 80}, {"C", 60}, {"D", 40}, {"E", 20}]

      result = BinPacker.pack(units, 2)

      assert length(result) == 2
      {0, shard_0_units, shard_0_total} = Enum.at(result, 0)
      {1, shard_1_units, shard_1_total} = Enum.at(result, 1)

      assert shard_0_total + shard_1_total == 300

      shard_0_names = Enum.map(shard_0_units, fn {name, _} -> name end)
      shard_1_names = Enum.map(shard_1_units, fn {name, _} -> name end)

      all_names = MapSet.new(shard_0_names ++ shard_1_names)
      assert all_names == MapSet.new(["A", "B", "C", "D", "E"])
    end

    test "single unit in single shard" do
      result = BinPacker.pack([{"A", 100}], 1)
      assert result == [{0, [{"A", 100}], 100}]
    end

    test "single unit in multiple shards" do
      result = BinPacker.pack([{"A", 100}], 3)
      assert length(result) == 3

      assert Enum.at(result, 0) == {0, [{"A", 100}], 100}
      assert Enum.at(result, 1) == {1, [], 0}
      assert Enum.at(result, 2) == {2, [], 0}
    end

    test "empty units list" do
      result = BinPacker.pack([], 2)
      assert result == [{0, [], 0}, {1, [], 0}]
    end

    test "equal durations distributes evenly" do
      units = [{"A", 50}, {"B", 50}, {"C", 50}, {"D", 50}]
      result = BinPacker.pack(units, 2)

      {_, _, total_0} = Enum.at(result, 0)
      {_, _, total_1} = Enum.at(result, 1)
      assert total_0 == 100
      assert total_1 == 100
    end

    test "preserves shard indices" do
      units = [{"A", 30}, {"B", 20}, {"C", 10}]
      result = BinPacker.pack(units, 3)

      indices = Enum.map(result, fn {i, _, _} -> i end)
      assert indices == [0, 1, 2]
    end

    test "handles zero-duration units" do
      units = [{"A", 100}, {"B", 0}, {"C", 0}]
      result = BinPacker.pack(units, 2)

      totals = Enum.map(result, fn {_, _, t} -> t end)
      assert Enum.sum(totals) == 100
    end

    test "many units in few shards" do
      units = for i <- 1..20, do: {"test_#{i}", i * 10}
      result = BinPacker.pack(units, 3)

      assert length(result) == 3
      all_names = result |> Enum.flat_map(fn {_, u, _} -> Enum.map(u, &elem(&1, 0)) end) |> MapSet.new()
      expected = for i <- 1..20, into: MapSet.new(), do: "test_#{i}"
      assert all_names == expected
    end
  end

  describe "determine_shard_count/2" do
    test "returns total when specified" do
      units = [{"A", 100}, {"B", 80}]
      assert BinPacker.determine_shard_count(units, total: 3) == 2
    end

    test "clamps total to unit count" do
      units = [{"A", 100}]
      assert BinPacker.determine_shard_count(units, total: 5) == 1
    end

    test "total of 0 becomes 1" do
      units = [{"A", 100}]
      assert BinPacker.determine_shard_count(units, total: 0) == 1
    end

    test "returns 1 for empty units" do
      assert BinPacker.determine_shard_count([]) == 1
    end

    test "uses max_duration to calculate shard count" do
      units = [{"A", 100}, {"B", 100}, {"C", 100}]
      assert BinPacker.determine_shard_count(units, max_duration: 150) == 2
    end

    test "max_duration respects min/max bounds" do
      units = for i <- 1..10, do: {"test_#{i}", 100}
      assert BinPacker.determine_shard_count(units, max_duration: 100, min: 2, max: 5) == 5
    end

    test "max_duration does not exceed unit count" do
      units = [{"A", 100}, {"B", 100}]
      assert BinPacker.determine_shard_count(units, max_duration: 50, max: 10) == 2
    end

    test "defaults to max when no max_duration or total" do
      units = [{"A", 100}, {"B", 80}, {"C", 60}]
      assert BinPacker.determine_shard_count(units, min: 2, max: 5) == 3
    end

    test "default max is capped to unit count" do
      units = [{"A", 100}]
      assert BinPacker.determine_shard_count(units) == 1
    end

    test "uses max shards when available" do
      units = [{"A", 100}, {"B", 80}, {"C", 60}, {"D", 40}, {"E", 20}]
      assert BinPacker.determine_shard_count(units, max: 3) == 3
    end
  end
end
