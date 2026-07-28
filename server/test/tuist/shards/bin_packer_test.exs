defmodule Tuist.Shards.BinPackerTest do
  use ExUnit.Case, async: true

  alias Tuist.Shards.BinPacker

  defp module_of(name), do: name |> String.split("/", parts: 2) |> hd()

  defp shard_of(result, name) do
    result
    |> Enum.find(fn {_i, units, _t} -> Enum.any?(units, fn {n, _} -> n == name end) end)
    |> elem(0)
  end

  defp makespan(result), do: result |> Enum.map(&elem(&1, 2)) |> Enum.max()

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

  describe "pack/3 (module-affinity)" do
    test "keeps a module's suites on one shard when balance allows" do
      # A=400, B=200, C=200; target (2 shards) = 400, so none is oversized.
      units =
        [{"A/1", 100}, {"A/2", 100}, {"A/3", 100}, {"A/4", 100}] ++
          [{"B/1", 100}, {"B/2", 100}, {"C/1", 100}, {"C/2", 100}]

      result = BinPacker.pack(units, 2, &module_of/1)

      # balance is unchanged vs the duration-optimal packing
      assert makespan(result) == makespan(BinPacker.pack(units, 2))

      # each non-split module lands entirely on a single shard
      for mod <- ["A", "B", "C"] do
        shards =
          units
          |> Enum.filter(fn {n, _} -> module_of(n) == mod end)
          |> Enum.map(fn {n, _} -> shard_of(result, n) end)
          |> Enum.uniq()

        assert length(shards) == 1, "#{mod} was split across shards #{inspect(shards)}"
      end
    end

    test "splits an oversized module across shards to keep balance" do
      # Big=600 > target 400, so it must be split; X=200 stays whole.
      units = for(i <- 1..6, do: {"Big/#{i}", 100}) ++ [{"X/1", 100}, {"X/2", 100}]

      result = BinPacker.pack(units, 2, &module_of/1)

      big_shards =
        units
        |> Enum.filter(fn {n, _} -> module_of(n) == "Big" end)
        |> Enum.map(fn {n, _} -> shard_of(result, n) end)
        |> Enum.uniq()

      assert length(big_shards) == 2
      assert makespan(result) == 400
    end

    test "falls back to the balanced packing when affinity would hurt balance" do
      # 3 equal modules of 200 into 2 shards: whole-module packing forces a
      # 400/200 split, so it must fall back to the 300/300 suite-level packing.
      units =
        [{"A/1", 100}, {"A/2", 100}, {"B/1", 100}, {"B/2", 100}, {"C/1", 100}, {"C/2", 100}]

      result = BinPacker.pack(units, 2, &module_of/1)

      assert makespan(result) == makespan(BinPacker.pack(units, 2))
      assert makespan(result) == 300
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

    test "treats nil min/max as defaults so callers can pass through unset options" do
      units = for i <- 1..144, do: {"module_#{i}", 1000}

      assert BinPacker.determine_shard_count(units, min: nil, max: 2, total: nil, max_duration: nil) == 2
      assert BinPacker.determine_shard_count(units, min: nil, max: nil, total: nil, max_duration: nil) == 10
    end
  end
end
