defmodule Tuist.PromEx.BucketsTest do
  use ExUnit.Case, async: true

  alias Tuist.PromEx.Buckets

  setup do
    config =
      Buckets.config(%Telemetry.Metrics.Distribution{
        reporter_options: [buckets: [1, 2, 3]],
        name: [:test],
        event_name: [:test],
        measurement: nil,
        tags: [],
        tag_values: nil,
        keep: nil,
        description: nil,
        unit: nil
      })

    %{config: config}
  end

  describe "bucket_for/2" do
    test "returns correct bucket for integer values", %{config: config} do
      assert Buckets.bucket_for(0, config) == 0
      assert Buckets.bucket_for(100, config) == 3
    end

    test "returns correct bucket for float values", %{config: config} do
      assert Buckets.bucket_for(0.8, config) == 0
      assert Buckets.bucket_for(1.1, config) == 1
    end

    test "bucket upper bound is inclusive", %{config: config} do
      assert Buckets.bucket_for(1, config) == 0
    end
  end

  describe "upper_bound/2" do
    test "returns the upper bound for a bucket index", %{config: config} do
      assert Buckets.upper_bound(0, config) == "1.0"
      assert Buckets.upper_bound(1, config) == "2.0"
      assert Buckets.upper_bound(2, config) == "3.0"
    end

    test "returns +Inf for out of range bucket index", %{config: config} do
      assert Buckets.upper_bound(3, config) == "+Inf"
      assert Buckets.upper_bound(99, config) == "+Inf"
    end
  end
end
