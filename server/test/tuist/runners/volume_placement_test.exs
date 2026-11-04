defmodule Tuist.Runners.VolumePlacementTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.VolumePlacement

  defp weights(names, weight \\ 1), do: Map.new(names, &{&1, weight})

  describe "holders/3" do
    test "picks the same distinct Nodes for a key every time" do
      nodes = weights(~w(mac-01 mac-02 mac-03 mac-04 mac-05))
      holders = VolumePlacement.holders("1/org/repo", nodes, 3)

      assert length(holders) == 3
      assert holders == Enum.uniq(holders)
      assert Enum.all?(holders, &Map.has_key?(nodes, &1))
      assert VolumePlacement.holders("1/org/repo", nodes, 3) == holders
    end

    test "picks every Node when asked for at least as many" do
      nodes = weights(~w(mac-01 mac-02))

      assert Enum.sort(VolumePlacement.holders("1/org/repo", nodes, 5)) == ["mac-01", "mac-02"]
      assert VolumePlacement.holders("1/org/repo", %{}, 2) == []
    end

    test "spreads keys over Nodes in proportion to their weight" do
      nodes = %{"large" => 2, "small-1" => 1, "small-2" => 1}

      counts =
        Enum.frequencies(for n <- 1..4000, do: hd(VolumePlacement.holders("#{n}/org/repo", nodes, 1)))

      assert_in_delta counts["large"] / 4000, 0.5, 0.05
      assert_in_delta counts["small-1"] / 4000, 0.25, 0.05
      assert_in_delta counts["small-2"] / 4000, 0.25, 0.05
    end

    test "moves only the keys a new Node takes" do
      before = weights(~w(mac-01 mac-02 mac-03 mac-04))
      later = Map.put(before, "mac-05", 1)

      for n <- 1..500 do
        key = "#{n}/org/repo"
        old = VolumePlacement.holders(key, before, 2)
        new = VolumePlacement.holders(key, later, 2)
        assert MapSet.subset?(MapSet.new(new -- ["mac-05"]), MapSet.new(old))
      end
    end
  end

  describe "replicas/2" do
    test "keeps one Node beyond the repository's peak concurrency, at least two" do
      assert VolumePlacement.replicas(0, 13) == 2
      assert VolumePlacement.replicas(1, 13) == 2
      assert VolumePlacement.replicas(3, 13) == 4
    end

    test "never asks for more Nodes than there are" do
      assert VolumePlacement.replicas(20, 13) == 13
      assert VolumePlacement.replicas(0, 1) == 1
      assert VolumePlacement.replicas(0, 0) == 0
    end
  end
end
