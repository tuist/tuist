defmodule Tuist.Runners.CatalogTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.Catalog

  describe "parse_shapes_json/1" do
    test "parses the Helm-injected JSON into the config shape" do
      # The exact value the chart renders into TUIST_RUNNER_LINUX_SHAPES.
      json = ~s([{"memoryGb":2,"vcpus":1},{"default":true,"memoryGb":16,"vcpus":4}])

      assert [
               %{vcpus: 1, memory_gb: 2} = first,
               %{vcpus: 4, memory_gb: 16, default: true}
             ] = Catalog.parse_shapes_json(json)

      # Non-default entries don't carry a :default key.
      refute Map.has_key?(first, :default)
    end

    test "ignores unknown keys (e.g. per-shape autoscaling)" do
      json = ~s([{"vcpus":4,"memoryGb":16,"default":true,"autoscaling":{"minWarmPoolFloor":30}}])

      assert [%{vcpus: 4, memory_gb: 16, default: true}] = Catalog.parse_shapes_json(json)
    end

    test "returns :error on malformed JSON so the caller keeps the default" do
      assert :error = Catalog.parse_shapes_json("not json")
      assert :error = Catalog.parse_shapes_json("{}")
      assert :error = Catalog.parse_shapes_json(nil)
    end
  end
end
