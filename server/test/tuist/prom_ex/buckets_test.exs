defmodule Tuist.PromEx.BucketsTest do
  use ExUnit.Case, async: true

  alias Tuist.PromEx.Buckets

  defp make_config(buckets) do
    Buckets.config(%Telemetry.Metrics.Distribution{
      reporter_options: [buckets: buckets],
      name: [:test],
      event_name: [:test],
      measurement: nil,
      tags: [],
      tag_values: nil,
      keep: nil,
      description: nil,
      unit: nil
    })
  end

  describe "bucket_for/2" do
    test "returns correct bucket for integer values" do
      config = make_config([1, 2, 3])

      assert Buckets.bucket_for(0, config) == 0
      assert Buckets.bucket_for(100, config) == 3
    end

    test "returns correct bucket for float values" do
      config = make_config([1, 2, 3])

      assert Buckets.bucket_for(0.8, config) == 0
      assert Buckets.bucket_for(1.1, config) == 1
    end

    test "bucket upper bound is inclusive" do
      config = make_config([1, 2, 3])

      assert Buckets.bucket_for(1, config) == 0
    end
  end

  describe "upper_bound/2" do
    test "returns the upper bound for a bucket index" do
      config = make_config([1, 2, 3])

      assert Buckets.upper_bound(0, config) == "1.0"
      assert Buckets.upper_bound(1, config) == "2.0"
      assert Buckets.upper_bound(2, config) == "3.0"
    end

    test "returns +Inf for out of range bucket index" do
      config = make_config([1, 2, 3])

      assert Buckets.upper_bound(3, config) == "+Inf"
      assert Buckets.upper_bound(99, config) == "+Inf"
    end
  end
end
