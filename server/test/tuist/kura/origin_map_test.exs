defmodule Tuist.Kura.OriginMapTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.OriginMap

  describe "candidates/1" do
    test "puts the nearest region first for each continent" do
      assert ["eu-central" | _rest] = OriginMap.candidates("FR")
      assert ["eu-central" | _rest] = OriginMap.candidates("DE")
      assert ["ap-southeast" | _rest] = OriginMap.candidates("SG")
      assert ["ap-southeast" | _rest] = OriginMap.candidates("AU")
      assert ["us-east" | _rest] = OriginMap.candidates("BR")
      assert ["eu-central" | _rest] = OriginMap.candidates("ZA")
    end

    test "splits the countries that hold more than one region" do
      assert ["us-west" | _rest] = OriginMap.candidates("US-OR")
      assert ["us-west" | _rest] = OriginMap.candidates("US-CA")
      assert ["us-east" | _rest] = OriginMap.candidates("US-VA")
      assert ["us-east" | _rest] = OriginMap.candidates("US-NY")
      assert ["ca-east" | _rest] = OriginMap.candidates("CA-QC")
      assert ["us-west" | _rest] = OriginMap.candidates("CA-BC")
    end

    test "falls back to the country when the subdivision is unmapped" do
      # An unrecognised subdivision still knows which continent it is on, which
      # is the coarser answer rather than a wrong one.
      assert OriginMap.candidates("FR-XYZ") == OriginMap.candidates("FR")
      assert OriginMap.candidates("US-ZZ") == OriginMap.candidates("US")
    end

    test "answers for an unmapped origin and for none at all" do
      # The default is where an account stating no constraint resolves today,
      # so an origin nobody mapped changes nothing rather than moving someone.
      assert ["us-east" | _rest] = OriginMap.candidates("ZZ")
      assert ["us-east" | _rest] = OriginMap.candidates(nil)
    end

    test "every origin can name every region" do
      # A region being unserved or unfunded has to narrow the choice, never
      # leave an origin with no answer at all.
      count = length(OriginMap.candidate_region_ids())

      for origin <- ["FR", "US-OR", "SG", "CA-QC", "BR", "ZZ", nil] do
        candidates = OriginMap.candidates(origin)

        assert length(candidates) == count
        assert Enum.uniq(candidates) == candidates
      end
    end
  end

  describe "preferred/2" do
    test "picks the nearest permitted region" do
      assert OriginMap.preferred("FR", ["us-east", "eu-central"]) == "eu-central"
      assert OriginMap.preferred("US-OR", ["us-east", "us-west"]) == "us-west"
      assert OriginMap.preferred("US-VA", ["us-east", "us-west"]) == "us-east"
    end

    test "falls to the next nearest when the nearest is not permitted" do
      # Which is what a residency constraint or an unfunded Air region does: it
      # narrows the set rather than refusing to answer.
      assert OriginMap.preferred("FR", ["us-east", "us-west"]) == "us-east"
      assert OriginMap.preferred("SG", ["us-east", "us-west"]) == "us-west"
    end

    test "answers nothing when no candidate is permitted" do
      assert OriginMap.preferred("FR", []) == nil
      assert OriginMap.preferred("FR", ["local-controller"]) == nil
    end
  end

  describe "distance/2" do
    test "orders regions by how near they are to the origin" do
      assert OriginMap.distance("FR", "eu-central") < OriginMap.distance("FR", "us-east")
      assert OriginMap.distance("US-OR", "us-west") < OriginMap.distance("US-OR", "us-east")
    end

    test "sorts a region the table does not name last" do
      assert OriginMap.distance("FR", "local-controller") > OriginMap.distance("FR", "ap-southeast")
    end
  end

  test "version/0 is a positive integer decisions can be dated by" do
    assert is_integer(OriginMap.version())
    assert OriginMap.version() > 0
  end
end
