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

  describe "config/1" do
    test "raises if buckets list is empty" do
      assert_raise ArgumentError, ~r/expected buckets list to be non-empty/, fn ->
        make_config([])
      end
    end

    test "raises if buckets contain non-numbers" do
      assert_raise ArgumentError, ~r/expected buckets list to contain only numbers/, fn ->
        make_config([1, "two", 3])
      end
    end

    test "raises if buckets are not ordered ascending" do
      assert_raise ArgumentError, ~r/expected buckets to be ordered ascending/, fn ->
        make_config([3, 2, 1])
      end
    end

    test "raises if buckets contain duplicates" do
      assert_raise ArgumentError, ~r/expected buckets to be ordered ascending/, fn ->
        make_config([1, 2, 2, 3])
      end
    end
  end

  describe "number_of_buckets/1" do
    test "returns the number of buckets" do
      config = make_config([1, 2, 3])
      assert Buckets.number_of_buckets(config) == 3
    end
  end

  describe "bucket_for/2" do
    test "returns 0 for value equal to first bucket (inclusive upper bound)" do
      config = make_config([1, 2, 3])
      assert Buckets.bucket_for(1, config) == 0
    end

    test "returns 0 for value less than first bucket" do
      config = make_config([1, 2, 3])
      assert Buckets.bucket_for(0, config) == 0
    end

    test "returns correct bucket index for exact bucket boundary values" do
      config = make_config([1, 2, 3])

      assert Buckets.bucket_for(1, config) == 0
      assert Buckets.bucket_for(2, config) == 1
      assert Buckets.bucket_for(3, config) == 2
    end

    test "returns correct bucket index for values between boundaries" do
      config = make_config([1, 2, 3])

      assert Buckets.bucket_for(0.5, config) == 0
      assert Buckets.bucket_for(1.5, config) == 1
      assert Buckets.bucket_for(2.5, config) == 2
    end

    test "returns number_of_buckets (overflow) for value greater than last bucket" do
      config = make_config([1, 2, 3])
      assert Buckets.bucket_for(4, config) == 3
      assert Buckets.bucket_for(100, config) == 3
    end

    test "handles float bucket boundaries with inclusive upper bound" do
      config = make_config([0.1, 0.2, 0.3])

      assert Buckets.bucket_for(0.1, config) == 0
      assert Buckets.bucket_for(0.2, config) == 1
      assert Buckets.bucket_for(0.3, config) == 2
    end

    test "handles integer values with float bucket boundaries" do
      config = make_config([0.5, 1.5, 2.5])

      assert Buckets.bucket_for(0, config) == 0
      assert Buckets.bucket_for(1, config) == 0
      assert Buckets.bucket_for(2, config) == 1
      # Note: integer 3 maps to bucket 2 because int_tree uses ceil(2.5)=3 -> bucket 2.
      # For accurate overflow detection with float boundaries, use float values.
      assert Buckets.bucket_for(3, config) == 2
      assert Buckets.bucket_for(3.0, config) == 3
    end

    test "handles negative values" do
      config = make_config([-2, -1, 0, 1, 2])

      assert Buckets.bucket_for(-3, config) == 0
      assert Buckets.bucket_for(-2, config) == 0
      assert Buckets.bucket_for(-1, config) == 1
      assert Buckets.bucket_for(0, config) == 2
      assert Buckets.bucket_for(1, config) == 3
      assert Buckets.bucket_for(2, config) == 4
      assert Buckets.bucket_for(3, config) == 5
    end
  end

  describe "upper_bound/2" do
    test "returns the upper bound for a bucket index" do
      config = make_config([1, 2, 3])

      assert Buckets.upper_bound(0, config) == "1.0"
      assert Buckets.upper_bound(1, config) == "2.0"
      assert Buckets.upper_bound(2, config) == "3.0"
    end

    test "returns +Inf for overflow bucket" do
      config = make_config([1, 2, 3])
      assert Buckets.upper_bound(3, config) == "+Inf"
    end

    test "returns +Inf for invalid bucket index" do
      config = make_config([1, 2, 3])
      assert Buckets.upper_bound(99, config) == "+Inf"
    end
  end
end
