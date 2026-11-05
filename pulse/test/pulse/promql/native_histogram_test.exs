defmodule Pulse.PromQL.NativeHistogramTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.NativeHistogram
  alias Pulse.Record.NativeHistogram, as: Histogram

  # The `*_cases/0` tables at the bottom are transcribed from Prometheus
  # v3.5.0's model/histogram/float_histogram_test.go and generic_test.go
  # (inputs and expected values verbatim). Quantile, fraction and variance
  # expectations come from promql/promqltest/testdata/native_histograms.test,
  # which compares sample values with a relative tolerance of 1e-6.
  # Exception: differing custom-bound addition/subtraction now use Mimir dd039cdd's
  # common-bound reconciliation instead of Prometheus 3.5.0's rejection;
  # mismatched-bound reset detection likewise compares reconciled bucket totals.

  describe "add/2 and sub/2" do
    test "match FloatHistogramAdd with Mimir custom-bound reconciliation in both operand orders" do
      for {name, a, b, expected, error} <- add_cases() do
        if error do
          assert NativeHistogram.add(a, b) == {:error, error}, name
          assert NativeHistogram.add(b, a) == {:error, error}, name
        else
          assert {:ok, result} = NativeHistogram.add(a, b), name
          assert NativeHistogram.compact(result) == NativeHistogram.compact(expected), name
          assert {:ok, result} = NativeHistogram.add(b, a), name
          assert NativeHistogram.compact(result) == NativeHistogram.compact(expected), name
        end
      end
    end

    test "match FloatHistogramSub with Mimir custom-bound reconciliation, including the negated reverse" do
      for {name, a, b, expected, error} <- sub_cases() do
        if error do
          assert NativeHistogram.sub(a, b) == {:error, error}, name
          assert NativeHistogram.sub(b, a) == {:error, error}, name
        else
          assert {:ok, result} = NativeHistogram.sub(a, b), name
          assert NativeHistogram.compact(result) == NativeHistogram.compact(expected), name

          assert {:ok, result} = NativeHistogram.sub(b, a), name
          negated = expected |> NativeHistogram.scale(-1.0) |> NativeHistogram.compact()
          # Primitive Sub preserves its receiver's hint; Mul(-1) now produces a gauge.
          negated = %{negated | counter_reset_hint: b.counter_reset_hint}
          assert NativeHistogram.compact(result) == negated, name
        end
      end
    end

    test "resolve the counter reset hint like FloatHistogram.Add" do
      hints = [:unknown, :yes, :no, :gauge]

      expected = %{
        {:yes, :no} => :unknown,
        {:no, :yes} => :unknown,
        {:unknown, :yes} => :unknown,
        {:yes, :unknown} => :unknown,
        {:unknown, :no} => :unknown,
        {:no, :unknown} => :unknown
      }

      for a <- hints, b <- hints do
        {:ok, result} = NativeHistogram.add(h(counter_reset_hint: a), h(counter_reset_hint: b))

        want =
          cond do
            a == b -> a
            :gauge in [a, b] -> :gauge
            true -> Map.fetch!(expected, {a, b})
          end

        assert result.counter_reset_hint == want, "#{a} + #{b}"
      end

      # Sub leaves the receiver's hint alone.
      {:ok, result} = NativeHistogram.sub(h(counter_reset_hint: :no), h(counter_reset_hint: :gauge))
      assert result.counter_reset_hint == :no
    end

    test "subtract across schemas as native_histograms.test's histogram_sub cases" do
      sub_0 =
        h(
          count: 41.0,
          sum: 2345.6,
          zero_count: 5.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 7}],
          positive_buckets: [1.0, 3.0, 1.0, 2.0, 1.0, 1.0, 1.0],
          negative_spans: [{0, 12}],
          negative_buckets: [0.0, 1.0, 4.0, 2.0, 7.0, 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 2.0]
        )

      sub_1 =
        h(
          count: 11.0,
          sum: 1234.5,
          zero_count: 3.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 3}],
          positive_buckets: [0.0, 2.0, 1.0],
          negative_spans: [{0, 4}],
          negative_buckets: [0.0, 0.0, 3.0, 2.0]
        )

      assert {:ok, result} = NativeHistogram.sub(sub_0, sub_1)

      assert_histogram(
        result,
        h(
          count: 30.0,
          sum: 1111.1,
          zero_count: 2.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 7}],
          positive_buckets: [1.0, 1.0, 0.0, 2.0, 1.0, 1.0, 1.0],
          negative_spans: [{0, 12}],
          negative_buckets: [0.0, 1.0, 1.0, 0.0, 7.0, 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 2.0]
        )
      )

      assert {:ok, result} = NativeHistogram.sub(sub_0, %{sub_1 | schema: 1})

      assert_histogram(
        result,
        h(
          count: 30.0,
          sum: 1111.1,
          zero_count: 2.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 7}],
          positive_buckets: [1.0, 0.0, 1.0, 2.0, 1.0, 1.0, 1.0],
          negative_spans: [{0, 12}],
          negative_buckets: [0.0, -2.0, 2.0, 2.0, 7.0, 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 2.0]
        )
      )

      assert {:ok, result} = NativeHistogram.sub(%{sub_1 | schema: 1}, sub_0)

      assert_histogram(
        result,
        h(
          count: -30.0,
          sum: -1111.1,
          zero_count: -2.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 7}],
          positive_buckets: [-1.0, 0.0, -1.0, -2.0, -1.0, -1.0, -1.0],
          negative_spans: [{0, 12}],
          negative_buckets: [0.0, 2.0, -2.0, -2.0, -7.0, 0.0, 0.0, 0.0, 0.0, -5.0, -5.0, -2.0]
        )
      )
    end
  end

  describe "scale/2 and divide/2" do
    test "matches TestFloatHistogramMul values with Mimir's negative-scaling gauge hints" do
      for {name, input, factor, expected} <- mul_cases() do
        expected = if factor < 0, do: %{expected | counter_reset_hint: :gauge}, else: expected
        assert NativeHistogram.scale(input, factor) == expected, name
      end
    end

    test "matches TestFloatHistogramDiv values with Mimir's negative-divisor gauge hints" do
      for {name, input, divisor, expected} <- div_cases() do
        expected = if divisor < 0, do: %{expected | counter_reset_hint: :gauge}, else: expected
        assert NativeHistogram.divide(input, divisor) == expected, name
      end
    end

    test "follow native_histograms.test's histogram_mul_div cases" do
      input =
        h(
          count: 30.0,
          sum: 33.0,
          zero_count: 3.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 3}],
          positive_buckets: [3.0, 3.0, 3.0],
          negative_spans: [{0, 3}],
          negative_buckets: [6.0, 6.0, 6.0]
        )

      assert NativeHistogram.scale(input, -3.0) ==
               h(
                 counter_reset_hint: :gauge,
                 count: -90.0,
                 sum: -99.0,
                 zero_count: -9.0,
                 zero_threshold: 0.001,
                 positive_spans: [{0, 3}],
                 positive_buckets: [-9.0, -9.0, -9.0],
                 negative_spans: [{0, 3}],
                 negative_buckets: [-18.0, -18.0, -18.0]
               )

      assert NativeHistogram.divide(input, -3.0) ==
               h(
                 counter_reset_hint: :gauge,
                 count: -10.0,
                 sum: -11.0,
                 zero_count: -1.0,
                 zero_threshold: 0.001,
                 positive_spans: [{0, 3}],
                 positive_buckets: [-1.0, -1.0, -1.0],
                 negative_spans: [{0, 3}],
                 negative_buckets: [-2.0, -2.0, -2.0]
               )

      assert NativeHistogram.divide(input, 0.0) ==
               h(count: :infinity, sum: :infinity, zero_count: :infinity, zero_threshold: 0.001)

      assert input |> NativeHistogram.scale(0.0) |> NativeHistogram.divide(0.0) ==
               h(count: :nan, sum: :nan, zero_count: :nan, zero_threshold: 0.001)
    end
  end

  describe "compact/1 and reduce_resolution/2" do
    test "compact/1 matches Prometheus's TestFloatHistogramCompact with no empty buckets kept" do
      for {name, input, expected} <- compact_cases() do
        assert NativeHistogram.compact(input) == expected, name
      end
    end

    test "reduce_resolution/2 matches TestFloatHistogramCopyToSchema and TestFloatHistogramReduceResolution" do
      for {name, target, input, expected} <- copy_to_schema_cases() do
        assert NativeHistogram.reduce_resolution(input, target) == expected, name
      end

      for {input, expected} <- reduce_resolution_cases() do
        assert NativeHistogram.reduce_resolution(input, expected.schema) == expected
      end
    end

    test "reduce_resolution/2 refuses to raise resolution or touch custom buckets" do
      assert_raise ArgumentError, fn -> NativeHistogram.reduce_resolution(h(schema: 0), 1) end
      assert_raise ArgumentError, fn -> NativeHistogram.reduce_resolution(h(schema: -53), -1) end
      assert_raise ArgumentError, fn -> NativeHistogram.reduce_resolution(h(schema: 0), -53) end
    end
  end

  describe "detect_reset?/2" do
    test "matches Prometheus's TestFloatHistogramDetectReset" do
      for {name, current, previous, expected} <- detect_reset_cases() do
        assert NativeHistogram.detect_reset?(current, previous) == expected, name
      end
    end

    test "trusts explicit reset hints and treats gauges like counters" do
      bigger = h(count: 10.0, positive_spans: [{0, 1}], positive_buckets: [10.0])
      smaller = h(count: 1.0, positive_spans: [{0, 1}], positive_buckets: [1.0])

      assert NativeHistogram.detect_reset?(%{bigger | counter_reset_hint: :yes}, smaller)
      refute NativeHistogram.detect_reset?(%{smaller | counter_reset_hint: :no}, bigger)
      assert NativeHistogram.detect_reset?(%{smaller | counter_reset_hint: :gauge}, bigger)
      refute NativeHistogram.detect_reset?(%{bigger | counter_reset_hint: :gauge}, smaller)
    end

    test "custom layout changes compare plain interval sums, including missing and infinite buckets" do
      previous =
        h(
          schema: -53,
          count: 20.0,
          custom_values: [1.0, 3.0],
          positive_spans: [{0, 3}],
          positive_buckets: [4.0, 6.0, 10.0]
        )

      for {counts, count, reset?} <- [
            {[1.0, 3.0, 2.0, 4.0, 10.0], 20.0, false},
            {[1.0, 2.0, 2.0, 5.0, 12.0], 22.0, true},
            {[1.0, 4.0, 3.0, 7.0, 9.0], 24.0, true},
            {[1.0, 4.0, 3.0, 17.0], 25.0, true}
          ] do
        current =
          h(
            schema: -53,
            count: count,
            custom_values: [0.0, 1.0, 2.0, 3.0],
            positive_spans: [{0, length(counts)}],
            positive_buckets: counts
          )

        assert NativeHistogram.detect_reset?(current, previous) == reset?
        refute NativeHistogram.detect_reset?(%{current | counter_reset_hint: :no}, previous)
        assert NativeHistogram.detect_reset?(%{current | counter_reset_hint: :yes}, previous)
      end

      # No common finite boundary: every bucket joins the final +Inf interval.
      current =
        h(
          schema: -53,
          count: 20.0,
          custom_values: [-1.0, 2.0],
          positive_spans: [{0, 3}],
          positive_buckets: [3.0, 8.0, 9.0]
        )

      refute NativeHistogram.detect_reset?(current, previous)
      assert NativeHistogram.detect_reset?(%{current | count: 19.0}, previous)

      # Compensated summation would incorrectly erase this plain-sum decrease.
      previous =
        h(
          schema: -53,
          count: 1.0e20,
          custom_values: [2.0],
          positive_spans: [{0, 1}],
          positive_buckets: [10_000_000_000_000_002.0]
        )

      current =
        h(
          schema: -53,
          count: 1.0e20,
          custom_values: [-1.0, 0.0, 1.0],
          positive_spans: [{0, 3}],
          positive_buckets: [1.0e16, 1.0, 1.0]
        )

      assert NativeHistogram.detect_reset?(current, previous)
      refute NativeHistogram.detect_reset?(previous, current)
    end

    # Mimir's pinned DetectReset keeps visiting the previous iterator after
    # current exhaustion, unlike the older Prometheus 3.5.0 behavior.
    test "checks every remaining previous bucket when the current buckets run out" do
      previous = h(count: 5.0, positive_spans: [{0, 2}], positive_buckets: [0.0, 5.0])
      assert NativeHistogram.detect_reset?(h(count: 10.0), previous)

      previous = h(count: 5.0, positive_spans: [{0, 3}], positive_buckets: [1.0, 0.0, 4.0])
      assert NativeHistogram.detect_reset?(h(count: 10.0, positive_spans: [{0, 1}], positive_buckets: [6.0]), previous)
    end
  end

  describe "equal?/2" do
    # Prometheus's TestFloatHistogramEquals.
    test "compares counts, sums and buckets by bit pattern" do
      h1 =
        h(
          schema: 3,
          count: 2.2,
          sum: 9.7,
          zero_threshold: 0.1,
          zero_count: 1.1,
          positive_buckets: [3.0],
          negative_buckets: [4.0]
        )

      assert_equal(h1, h1)

      for changed <- [
            %{h1 | count: :nan},
            %{h1 | zero_count: :nan},
            %{h1 | positive_buckets: [:nan]},
            %{h1 | negative_buckets: [:nan]}
          ] do
        assert_not_equal(h1, changed)
        assert_equal(changed, changed)
      end

      # Custom bounds are ignored for exponential schemas.
      assert_equal(h1, %{h1 | custom_values: [1.0, 2.0, 3.0]})

      cbh1 =
        h(
          schema: -53,
          count: 2.2,
          sum: 9.7,
          positive_spans: [{0, 1}],
          positive_buckets: [3.0],
          custom_values: [1.0, 2.0, 3.0]
        )

      assert_equal(cbh1, cbh1)
      assert_not_equal(cbh1, %{cbh1 | custom_values: [1.0, 2.0, 3.0, 4.0]})
      assert_not_equal(cbh1, %{cbh1 | negative_spans: [{0, 1}], negative_buckets: [1.0]})
      assert_not_equal(cbh1, %{cbh1 | zero_threshold: 0.1, zero_count: 10.0})
    end

    test "ignores zero-length spans but not zero-offset splits" do
      a = h(positive_spans: [{0, 2}], positive_buckets: [1.0, 2.0])

      assert_equal(a, %{a | positive_spans: [{0, 0}, {0, 2}, {3, 0}]})
      assert_not_equal(a, %{a | positive_spans: [{0, 1}, {0, 1}]})
      assert_not_equal(a, %{a | sum: -0.0})
    end
  end

  describe "buckets/1" do
    test "matches the iteration order and boundary rules of Prometheus's JSON marshalling" do
      for {input, expected} <- json_buckets_cases() do
        assert NativeHistogram.buckets(input) == expected, inspect(input)
      end
    end

    test "computes exponential bounds bit-identically to TestGetBoundExponential" do
      for {index, schema, want} <- bound_cases() do
        histogram = h(schema: schema, positive_spans: [{index, 1}], positive_buckets: [1.0])
        assert [{_rule, _lower, ^want, 1.0}] = NativeHistogram.buckets(histogram), "#{index}@#{schema}"
      end
    end

    test "reports custom buckets closed first and left-open after" do
      histogram =
        h(
          schema: -53,
          count: 4.0,
          sum: 5.0,
          custom_values: [5.0, 10.0],
          positive_spans: [{0, 3}],
          positive_buckets: [1.0, 2.0, 1.0]
        )

      assert NativeHistogram.buckets(histogram) == [
               {3, :negative_infinity, 5.0, 1.0},
               {0, 5.0, 10.0, 2.0},
               {0, 10.0, :infinity, 1.0}
             ]
    end
  end

  describe "count/1, sum/1 and avg/1" do
    test "follow native_histograms.test" do
      empty = h()
      assert NativeHistogram.count(empty) == 0.0
      assert NativeHistogram.sum(empty) == 0.0
      assert NativeHistogram.avg(empty) == :nan

      single = h(sum: 5.0, count: 4.0, positive_spans: [{0, 3}], positive_buckets: [1.0, 2.0, 1.0])
      assert NativeHistogram.count(single) == 4.0
      assert NativeHistogram.sum(single) == 5.0
      assert NativeHistogram.avg(single) == 1.25

      assert NativeHistogram.avg(h(sum: -5.0, count: 4.0)) == -1.25
      assert NativeHistogram.avg(h(sum: 0.25, count: 1.0, zero_count: 1.0, zero_threshold: 0.5)) == 0.25
    end
  end

  describe "stddev/1 and stdvar/1" do
    test "follow native_histograms.test's histogram_stddev_stdvar cases" do
      sparse_positive =
        Enum.map(0..54, fn
          i when i in [13, 24, 26, 54] -> 1.0
          _ -> 0.0
        end)

      sparse_negative =
        Enum.map(0..46, fn
          i when i in [24, 46] -> 1.0
          _ -> 0.0
        end)

      mixed =
        h(
          schema: 3,
          count: 7.0,
          sum: 62.0,
          zero_count: 1.0,
          positive_spans: [{0, 55}],
          positive_buckets: sparse_positive,
          negative_spans: [{0, 47}],
          negative_buckets: sparse_negative
        )

      cases = [
        {h(
           schema: 2,
           count: 4.0,
           sum: 10.0,
           positive_spans: [{0, 9}],
           positive_buckets: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0]
         ), 1.0787993180043811, 1.163807968526718},
        {h(schema: 8, count: 10.0, sum: 10.0, positive_spans: [{0, 4}], positive_buckets: [1.0, 2.0, 3.0, 4.0]),
         0.0048960313898237465, 2.3971123370139447e-05},
        {mixed, 42.94723640026, 1844.4651144196398},
        {h(
           count: 10.0,
           sum: -112_946.0,
           negative_spans: [{0, 18}],
           negative_buckets: [0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]
         ), 27_556.344499842, 759_352_122.1939945},
        {h(count: 10.0, sum: -100.0, negative_spans: [{0, 5}], negative_buckets: [0.0, 0.0, 0.0, 0.0, 10.0]),
         1.3137084989848, 1.725830020304794},
        {%{mixed | sum: :nan}, :nan, :nan},
        {%{mixed | sum: :infinity}, :infinity, :infinity}
      ]

      for {histogram, stddev, stdvar} <- cases do
        assert_almost(stddev, NativeHistogram.stddev(histogram))
        assert_almost(stdvar, NativeHistogram.stdvar(histogram))
      end
    end

    test "use arithmetic midpoints for custom buckets" do
      histogram =
        h(
          schema: -53,
          count: 2.0,
          sum: 15.0,
          custom_values: [5.0, 10.0],
          positive_spans: [{1, 1}],
          positive_buckets: [2.0]
        )

      # Both observations sit at the (5, 10] midpoint 7.5, the mean.
      assert NativeHistogram.stdvar(histogram) == 0.0
      assert NativeHistogram.stddev(h()) == :nan
    end
  end

  describe "quantile/2" do
    test "follows native_histograms.test's histogram_quantile cases" do
      positive =
        h(
          count: 12.0,
          sum: 100.0,
          zero_count: 2.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 5}],
          positive_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
        )

      negative = %{
        positive
        | positive_spans: [],
          positive_buckets: [],
          negative_spans: [{0, 5}],
          negative_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
      }

      both = %{
        positive
        | count: 24.0,
          zero_count: 4.0,
          negative_spans: [{0, 5}],
          negative_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
      }

      cases = [
        {positive,
         [
           {1.001, :infinity},
           {1.0, 16.0},
           {0.99, 15.67072476139083},
           {0.9, 12.99603834169977},
           {0.6, 4.594793419988138},
           {0.5, 1.5874010519681994},
           {0.1, 0.0006},
           {0.0, 0.0},
           {-1.0, :negative_infinity},
           {0.08333333333333333, 0.0005},
           {0.6320802083934297, 6.0}
         ]},
        {negative,
         [
           {1.001, :infinity},
           {1.0, 0.0},
           {0.99, -0.00006},
           {0.9, -0.0006},
           {0.5, -1.5874010519681996},
           {0.1, -12.996038341699768},
           {0.0, -16.0},
           {-1.0, :negative_infinity},
           {0.9166666666666666, -0.0005},
           {0.36791979160657035, -6.0}
         ]},
        {both,
         [
           {1.001, :infinity},
           {1.0, 16.0},
           {0.99, 15.34822590920423},
           {0.9, 10.556063286183155},
           {0.7, 1.2030250360821164},
           {0.55, 0.0006},
           {0.5, 0.0},
           {0.45, -0.0006},
           {0.3, -1.2030250360821169},
           {0.1, -10.556063286183155},
           {0.01, -15.34822590920423},
           {0.0, -16.0},
           {-1.0, :negative_infinity},
           {0.5416666666666666, 0.0005},
           {0.4583333333333333, -0.0005}
         ]}
      ]

      for {histogram, expectations} <- cases, {q, expected} <- expectations do
        assert_almost(expected, NativeHistogram.quantile(q, histogram))
      end
    end

    test "interpolates within single buckets of any schema" do
      single = h(sum: 5.0, count: 4.0, positive_spans: [{0, 3}], positive_buckets: [1.0, 2.0, 1.0])
      assert_almost(1.414213562373095, NativeHistogram.quantile(0.5, single))

      assert_almost(
        -1.414213562373095,
        NativeHistogram.quantile(
          0.5,
          h(sum: -5.0, count: 4.0, negative_spans: [{0, 3}], negative_buckets: [1.0, 2.0, 1.0])
        )
      )

      assert NativeHistogram.quantile(0.5, h(zero_count: 1.0, zero_threshold: 0.5, sum: 0.25, count: 1.0)) == 0.0

      balanced =
        h(
          count: 8.0,
          positive_spans: [{0, 3}],
          positive_buckets: [1.0, 2.0, 1.0],
          negative_spans: [{0, 3}],
          negative_buckets: [1.0, 2.0, 1.0]
        )

      assert_almost(0.5, NativeHistogram.quantile(0.5, balanced))

      for {schema, sum, one, two} <- [
            {-1, 6.0, 2.0, 8.0},
            {0, 4.0, 1.4142135623730951, 2.82842712474619},
            {1, 4.0, 1.189207, 1.6817928305074292}
          ] do
        first = h(schema: schema, sum: sum, count: 5.0, positive_spans: [{0, 2}], positive_buckets: [0.0, 5.0])
        second = h(schema: schema, sum: sum, count: 5.0, positive_spans: [{0, 3}], positive_buckets: [0.0, 0.0, 5.0])
        assert_almost(one, NativeHistogram.quantile(0.5, first))
        assert_almost(two, NativeHistogram.quantile(0.5, second))
        assert_almost(-one, NativeHistogram.quantile(0.5, mirror(first)))
        assert_almost(-two, NativeHistogram.quantile(0.5, mirror(second)))
        assert_almost(0.5, NativeHistogram.fraction(0.0, one, first))
        assert_almost(0.5, NativeHistogram.fraction(0.0, two, second))
        assert_almost(0.5, NativeHistogram.fraction(-one, 0.0, mirror(first)))
        assert_almost(0.5, NativeHistogram.fraction(-two, 0.0, mirror(second)))
      end
    end

    test "returns NaN for NaN q or empty histograms" do
      single = h(sum: 5.0, count: 4.0, positive_spans: [{0, 3}], positive_buckets: [1.0, 2.0, 1.0])
      assert NativeHistogram.quantile(:nan, single) == :nan
      assert NativeHistogram.quantile(0.5, h()) == :nan
      assert NativeHistogram.quantile(-0.5, h()) == :negative_infinity
      assert NativeHistogram.quantile(:infinity, h()) == :infinity
    end

    test "interpolates linearly in custom buckets" do
      histogram =
        h(
          schema: -53,
          sum: 5.0,
          count: 4.0,
          custom_values: [5.0, 10.0],
          positive_spans: [{0, 3}],
          positive_buckets: [1.0, 2.0, 1.0]
        )

      assert NativeHistogram.quantile(0.5, histogram) == 7.5
      assert NativeHistogram.fraction(5.0, 10.0, histogram) == 0.5
      # The +Inf bucket answers with its lower bound, the first bucket starts at zero.
      assert NativeHistogram.quantile(1.0, histogram) == 10.0
      assert NativeHistogram.quantile(0.125, histogram) == 2.5
    end

    test "reports NaN observations like native_histograms.test's histogram_nan cases" do
      all_nan = h(count: 3.0, sum: :nan)
      some_nan = h(count: 15.0, sum: :nan, positive_spans: [{0, 1}], positive_buckets: [12.0])

      for q <- [1.0, 0.81] do
        assert NativeHistogram.quantile_with_info(q, all_nan) == {:nan, [:nan_result]}
        assert NativeHistogram.quantile_with_info(q, some_nan) == {:nan, [:nan_result]}
      end

      assert NativeHistogram.quantile_with_info(0.8, all_nan) == {:nan, [:nan_result]}
      assert NativeHistogram.quantile_with_info(0.8, some_nan) == {1.0, [:nan_skew]}
      assert NativeHistogram.quantile_with_info(0.4, all_nan) == {:nan, [:nan_result]}

      assert {value, [:nan_skew]} = NativeHistogram.quantile_with_info(0.4, some_nan)
      assert_almost(0.7071067811865475, value)

      assert NativeHistogram.fraction_with_info(:negative_infinity, 0.7071067811865475, all_nan) ==
               {0.0, [:nan_observations]}

      assert {value, [:nan_observations]} =
               NativeHistogram.fraction_with_info(:negative_infinity, 0.7071067811865475, some_nan)

      assert_almost(0.4, value)
      assert NativeHistogram.fraction_with_info(:negative_infinity, :infinity, all_nan) == {0.0, [:nan_observations]}
      assert NativeHistogram.fraction_with_info(:negative_infinity, :infinity, some_nan) == {0.8, [:nan_observations]}
    end

    test "retains the selected bucket for NaN-sum interpolation like corrected Mimir" do
      positive = h(count: 10.0, sum: :nan, positive_spans: [{0, 2}], positive_buckets: [4.0, 4.0])
      negative = h(count: 10.0, sum: :nan, negative_spans: [{0, 2}], negative_buckets: [4.0, 4.0])

      zero = %{
        positive
        | zero_count: 4.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 1}],
          positive_buckets: [4.0]
      }

      custom =
        h(
          schema: -53,
          count: 3.0,
          sum: :nan,
          positive_spans: [{1, 3}],
          positive_buckets: [1.0, 1.0, 1.0],
          custom_values: [1.0, 2.0, 4.0]
        )

      # Rank 2.5/4 in the first bucket: exponential interpolation on each
      # side, linear interpolation in the zero bucket. Later buckets only
      # contribute to NaN detection, never to these bounds or denominators.
      for {histogram, expected} <- [
            {positive, :math.pow(2, -0.375)},
            {negative, -:math.pow(2, 0.375)},
            {zero, 0.000625}
          ] do
        assert {value, [:nan_skew]} = NativeHistogram.quantile_with_info(0.25, histogram)
        assert_almost(expected, value)
      end

      # NaN in the sum alone does not prove NaN observations. Custom buckets
      # include NaNs in +Inf, so total bucket population still equals count.
      assert {value, []} = NativeHistogram.quantile_with_info(0.2, custom)
      assert_almost(1.6, value)
    end
  end

  describe "fraction/3" do
    test "follows native_histograms.test's histogram_fraction cases" do
      positive =
        h(
          count: 12.0,
          sum: 100.0,
          zero_count: 2.0,
          zero_threshold: 0.001,
          positive_spans: [{0, 5}],
          positive_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
        )

      negative = %{
        positive
        | positive_spans: [],
          positive_buckets: [],
          negative_spans: [{0, 5}],
          negative_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
      }

      both = %{
        positive
        | count: 24.0,
          zero_count: 4.0,
          negative_spans: [{0, 5}],
          negative_buckets: [2.0, 3.0, 0.0, 1.0, 4.0]
      }

      ninf = :negative_infinity
      inf = :infinity

      shared = [
        {42.0, 3.1415, 0.0},
        {0.0, 0.0, 0.0},
        {0.000001, 0.000001, 0.0},
        {42.0, 42.0, 0.0},
        {-3.1, -3.1, 0.0},
        {3.1415, :nan, :nan},
        {:nan, 42.0, :nan},
        {:nan, :nan, :nan},
        {ninf, inf, 1.0}
      ]

      cases = [
        {positive,
         shared ++
           [
             {0.0, inf, 1.0},
             {ninf, 0.0, 0.0},
             {-0.001, 0.0, 0.0},
             {0.0, 0.001, 0.16666666666666666},
             {0.001, inf, 0.8333333333333334},
             {0.0, 0.0005, 0.08333333333333333},
             {ninf, -0.001, 0.0},
             {1.0, 2.0, 0.25},
             {0.0, 1.5, 0.4795739585136224},
             {1.5, 2.0, 0.10375937481971091},
             {1.0, 8.0, 0.3333333333333333},
             {0.0, 6.0, 0.6320802083934297},
             {1.0, 6.0, 0.29874687506009634},
             {1.5, 6.0, 0.15250624987980724},
             {-2.0, -1.0, 0.0},
             {-2.0, -1.5, 0.0},
             {-8.0, -1.0, 0.0},
             {-6.0, -1.0, 0.0},
             {-6.0, -1.5, 0.0}
           ]},
        {negative,
         shared ++
           [
             {0.0, inf, 0.0},
             {ninf, 0.0, 1.0},
             {-0.001, 0.0, 0.16666666666666666},
             {0.0, 0.001, 0.0},
             {-0.0005, 0.0, 0.08333333333333333},
             {ninf, -0.0005, 0.9166666666666666},
             {0.001, inf, 0.0},
             {ninf, -0.001, 0.8333333333333334},
             {1.0, 2.0, 0.0},
             {1.5, 2.0, 0.0},
             {1.0, 8.0, 0.0},
             {1.0, 6.0, 0.0},
             {1.5, 6.0, 0.0},
             {-2.0, -1.0, 0.25},
             {-2.0, -1.5, 0.10375937481971091},
             {-8.0, -1.0, 0.3333333333333333},
             {ninf, -6.0, 0.36791979160657035},
             {-6.0, -1.0, 0.29874687506009634},
             {-6.0, -1.5, 0.15250624987980724}
           ]},
        {both,
         shared ++
           [
             {0.0, inf, 0.5},
             {ninf, 0.0, 0.5},
             {-0.001, 0.0, 0.08333333333333333},
             {0.0, 0.001, 0.08333333333333333},
             {-0.0005, 0.0005, 0.08333333333333333},
             {ninf, 0.0005, 0.5416666666666666},
             {ninf, -0.0005, 0.4583333333333333},
             {0.001, inf, 0.4166666666666667},
             {ninf, -0.001, 0.4166666666666667},
             {1.0, 2.0, 0.125},
             {1.5, 2.0, 0.051879687409855414},
             {1.0, 8.0, 0.16666666666666666},
             {1.0, 6.0, 0.14937343753004825},
             {1.5, 6.0, 0.07625312493990366},
             {-2.0, -1.0, 0.125},
             {-2.0, -1.5, 0.051879687409855456},
             {-8.0, -1.0, 0.16666666666666666},
             {-6.0, -1.0, 0.14937343753004817},
             {-6.0, -1.5, 0.07625312493990362}
           ]}
      ]

      for {histogram, expectations} <- cases, {lower, upper, expected} <- expectations do
        assert_almost(expected, NativeHistogram.fraction(lower, upper, histogram))
      end
    end

    test "interpolates before multiplying large or tiny bucket populations" do
      for {population, width} <- [{1.0e308, 1.0e100}, {1.0e-200, 1.0e-200}] do
        custom =
          h(
            schema: -53,
            count: population,
            custom_values: [width],
            positive_spans: [{0, 1}],
            positive_buckets: [population]
          )

        zero = h(count: population, zero_threshold: width, zero_count: population)

        assert NativeHistogram.fraction(0.0, width / 2, custom) == 0.5
        assert NativeHistogram.fraction(-width, 0.0, zero) == 0.5
        assert NativeHistogram.fraction(0.0, width, zero) == 0.5
      end
    end

    test "is NaN for empty histograms" do
      assert NativeHistogram.fraction(3.1415, 42.0, h()) == :nan
      assert NativeHistogram.fraction(:negative_infinity, :infinity, h()) == :nan

      single = h(sum: 5.0, count: 4.0, positive_spans: [{0, 3}], positive_buckets: [1.0, 2.0, 1.0])
      assert NativeHistogram.fraction(1.0, 2.0, single) == 0.5
      assert NativeHistogram.fraction_with_info(0.0, 8.0, single) == {1.0, []}

      low_res = h(schema: -1, count: 5.0, sum: 8.0, positive_spans: [{1, 1}], positive_buckets: [5.0])
      assert NativeHistogram.fraction(1.0, 4.0, low_res) == 1.0
      assert NativeHistogram.fraction(-0.5, 0.5, h(zero_count: 1.0, zero_threshold: 0.5, sum: 0.25, count: 1.0)) == 1.0
    end
  end

  defp h(fields \\ []), do: struct(Histogram, fields)

  defp mirror(%Histogram{} = histogram) do
    %{
      histogram
      | positive_spans: histogram.negative_spans,
        positive_buckets: histogram.negative_buckets,
        negative_spans: histogram.positive_spans,
        negative_buckets: histogram.positive_buckets
    }
  end

  defp assert_equal(a, b) do
    assert NativeHistogram.equal?(a, b)
    assert NativeHistogram.equal?(b, a)
  end

  defp assert_not_equal(a, b) do
    refute NativeHistogram.equal?(a, b)
    refute NativeHistogram.equal?(b, a)
  end

  # promqltest compares compacted histograms, with the same tolerance for
  # count, sum and zero count.
  defp assert_histogram(actual, expected) do
    {actual, expected} = {NativeHistogram.compact(actual), NativeHistogram.compact(expected)}
    for field <- [:count, :sum, :zero_count], do: assert_almost(Map.fetch!(expected, field), Map.fetch!(actual, field))
    assert Map.drop(actual, [:count, :sum, :zero_count]) == Map.drop(expected, [:count, :sum, :zero_count])
  end

  @min_normal 2.2250738585072014e-308

  # math.MaxFloat64.
  <<max_float::float-64>> = <<0x7FEFFFFFFFFFFFFF::64>>
  @max_float max_float

  # Port of Prometheus's util/almost.Equal with promqltest's 1e-6 epsilon.
  defp assert_almost(expected, actual) when is_atom(expected), do: assert(actual == expected)

  defp assert_almost(expected, actual) do
    assert is_number(actual), "expected #{expected}, got #{inspect(actual)}"
    sum = abs(expected) + abs(actual)
    diff = abs(expected - actual)

    close? =
      cond do
        expected == actual -> true
        expected == 0 or actual == 0 or sum < @min_normal -> diff < 1.0e-6 * @min_normal
        true -> diff / sum < 1.0e-6
      end

    assert close?, "expected #{expected}, got #{actual}"
  end

  # Transcribed from Prometheus v3.5.0 (see the module comment).

  defp add_cases do
    [
      {"same bucket layout",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 5.0, 7.0, 13.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [4.0, 2.0, 9.0, 10.0]
       ), nil},
      {"same bucket layout, defined differently",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {1, 1}, {0, 2}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-2, 2}, {1, 2}, {0, 1}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         negative_spans: [{3, 7}],
         negative_buckets: [1.0, 1.0, 0.0, 0.0, 0.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 2}, {1, 1}, {0, 2}],
         positive_buckets: [1.0, 0.0, 5.0, 7.0, 13.0],
         negative_spans: [{3, 5}, {0, 2}],
         negative_buckets: [4.0, 2.0, 0.0, 0.0, 0.0, 9.0, 10.0]
       ), nil},
      {"non-overlapping spans",
       h(
         zero_threshold: 0.001,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.001,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{0, 2}, {3, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0],
         negative_spans: [{-9, 2}, {3, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.001,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 4}, {0, 6}],
         positive_buckets: [1.0, 0.0, 5.0, 4.0, 3.0, 4.0, 7.0, 2.0, 3.0, 6.0],
         negative_spans: [{-9, 2}, {3, 2}, {5, 2}, {3, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0, 3.0, 1.0, 5.0, 6.0]
       ), nil},
      {"non-overlapping spans inverted order",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{0, 2}, {3, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0],
         negative_spans: [{-6, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 2}, {0, 5}, {0, 3}],
         positive_buckets: [1.0, 0.0, 5.0, 4.0, 3.0, 4.0, 7.0, 2.0, 3.0, 6.0],
         negative_spans: [{-6, 2}, {1, 2}, {4, 2}, {3, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0, 3.0, 1.0, 5.0, 6.0]
       ), nil},
      {"overlapping spans",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 4}, {0, 4}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"overlapping spans inverted order",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"schema change",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 19.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"larger zero bucket in first histogram",
       h(
         zero_threshold: 1.0,
         zero_count: 17.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{1, 2}, {0, 3}],
         positive_buckets: [2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 1.0,
         zero_count: 29.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{1, 2}, {0, 3}],
         positive_buckets: [2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"larger zero bucket in second histogram",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 1.0,
         zero_count: 17.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{1, 2}, {0, 3}],
         positive_buckets: [2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 1.0,
         zero_count: 29.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{1, 5}],
         positive_buckets: [2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"larger zero threshold in first histogram ends up inside a populated bucket of second histogram",
       h(
         zero_threshold: 0.2,
         zero_count: 17.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{1, 2}, {0, 3}],
         positive_buckets: [2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.25,
         zero_count: 29.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-1, 1}, {1, 5}],
         positive_buckets: [0.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"larger zero threshold in second histogram ends up inside a populated bucket of first histogram",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.2,
         zero_count: 17.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{1, 2}, {0, 3}],
         positive_buckets: [2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.25,
         zero_count: 29.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{1, 5}],
         positive_buckets: [2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"schema change combined with larger zero bucket in second histogram",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [2.0, 5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.25,
         zero_count: 12.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-3, 2}, {5, 5}],
         positive_buckets: [1.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         zero_threshold: 0.25,
         zero_count: 22.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-1, 7}],
         positive_buckets: [6.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"schema change combined with larger zero bucket in first histogram",
       h(
         zero_threshold: 0.25,
         zero_count: 8.0,
         count: 21.0,
         sum: 1.234,
         positive_spans: [{-1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         negative_spans: [{4, 2}, {1, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         zero_threshold: 0.25,
         zero_count: 20.0,
         count: 51.0,
         sum: 3.579,
         positive_spans: [{-1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [3.0, 2.0, 1.0, 4.0, 9.0, 6.0]
       ), nil},
      {"same custom bucket layout",
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 1.234,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 26.0,
         sum: 3.579,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 5.0, 7.0, 13.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"same custom bucket layout, defined differently",
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {1, 1}, {0, 2}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 1.234,
         positive_spans: [{0, 2}, {1, 2}, {0, 1}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 26.0,
         sum: 3.579,
         positive_spans: [{0, 2}, {1, 1}, {0, 2}],
         positive_buckets: [1.0, 0.0, 5.0, 7.0, 13.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"non-overlapping spans with custom buckets",
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 20.0,
         sum: 1.234,
         positive_spans: [{2, 2}, {3, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 35.0,
         sum: 3.579,
         positive_spans: [{0, 4}, {0, 6}],
         positive_buckets: [1.0, 0.0, 5.0, 4.0, 3.0, 4.0, 7.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"non-overlapping spans inverted order with custom buckets",
       h(
         schema: -53,
         count: 20.0,
         sum: 1.234,
         positive_spans: [{2, 2}, {3, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 35.0,
         sum: 3.579,
         positive_spans: [{0, 4}, {0, 6}],
         positive_buckets: [1.0, 0.0, 5.0, 4.0, 3.0, 4.0, 7.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"overlapping spans with custom buckets",
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 27.0,
         sum: 1.234,
         positive_spans: [{1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 42.0,
         sum: 3.579,
         positive_spans: [{0, 4}, {0, 4}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"overlapping spans inverted order with custom buckets",
       h(
         schema: -53,
         count: 27.0,
         sum: 1.234,
         positive_spans: [{1, 4}, {0, 3}],
         positive_buckets: [5.0, 4.0, 2.0, 3.0, 6.0, 2.0, 5.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 42.0,
         sum: 3.579,
         positive_spans: [{0, 4}, {0, 4}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 6.0, 10.0, 9.0, 5.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"different custom bucket layout",
       h(
         schema: -53,
         count: 15.0,
         sum: 2.345,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 1.234,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0]
       ),
       h(
         schema: -53,
         count: 26.0,
         sum: 3.579,
         positive_spans: [{0, 1}, {2, 2}],
         positive_buckets: [1.0, 5.0, 20.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"mix exponential and custom buckets histograms",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 59.0,
         sum: 1.234,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [2.0, 5.0, 4.0, 2.0, 3.0, 6.0, 7.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [4.0, 10.0, 1.0, 4.0, 14.0, 7.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 12.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil, :incompatible_schema}
    ]
  end

  defp sub_cases do
    [
      {"same bucket layout",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 21.0,
         sum: 12.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [1.0, 1.0, 4.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 3.0,
         count: 9.0,
         sum: 11.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 1.0, 1.0, 1.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [2.0, 0.0, 1.0, 2.0]
       ), nil},
      {"schema change",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 59.0,
         sum: 1.234,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [2.0, 5.0, 4.0, 2.0, 3.0, 6.0, 7.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [4.0, 10.0, 1.0, 4.0, 14.0, 7.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 2.0,
         count: 19.0,
         sum: 0.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 1.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 6.0,
         count: 40.0,
         sum: 0.889,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [1.0, 5.0, 4.0, 2.0, 2.0, 2.0, 0.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [1.0, 9.0, 1.0, 4.0, 9.0, 1.0]
       ), nil},
      {"same custom bucket layout",
       h(
         schema: -53,
         count: 15.0,
         sum: 23.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 12.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 4.0,
         sum: 11.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 1.0, 1.0, 1.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"different custom bucket layout",
       h(
         schema: -53,
         count: 15.0,
         sum: 23.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 12.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0]
       ),
       h(
         schema: -53,
         count: 4.0,
         sum: 11.0,
         positive_spans: [{0, 1}, {2, 2}],
         positive_buckets: [1.0, 1.0, 2.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil},
      {"mix exponential and custom buckets histograms",
       h(
         zero_threshold: 0.01,
         zero_count: 8.0,
         count: 59.0,
         sum: 1.234,
         positive_spans: [{-2, 5}, {0, 3}],
         positive_buckets: [2.0, 5.0, 4.0, 2.0, 3.0, 6.0, 7.0, 5.0],
         negative_spans: [{3, 3}, {1, 3}],
         negative_buckets: [4.0, 10.0, 1.0, 4.0, 14.0, 7.0]
       ),
       h(
         schema: -53,
         count: 11.0,
         sum: 12.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.0, 0.0, 2.0, 3.0, 6.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), nil, :incompatible_schema}
    ]
  end

  defp mul_cases do
    [
      {"zero value", h(), 3.1415, h()},
      {"zero multiplier",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), 0.0,
       h(
         zero_threshold: 0.01,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [0.0, 0.0, 0.0, 0.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [0.0, 0.0, 0.0, 0.0]
       )},
      {"no-op",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), 1.0,
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       )},
      {"double",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), 2.0,
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 6986.6,
         sum: 4_698_418.648,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [2.0, 6.6, 8.4, 0.2],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [6.2, 6.0, 246_800.0, 2000.0]
       )},
      {"triple",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ), 3.0,
       h(
         zero_threshold: 0.01,
         zero_count: 33.0,
         count: 90.0,
         sum: 69.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [3.0, 0.0, 9.0, 12.0, 21.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [9.0, 3.0, 15.0, 18.0]
       )},
      {"negation",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ), -1.0,
       h(
         zero_threshold: 0.01,
         zero_count: -11.0,
         count: -30.0,
         sum: -23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [-1.0, 0.0, -3.0, -4.0, -7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [-3.0, -1.0, -5.0, -6.0]
       )},
      {"negative multiplier",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ), -2.0,
       h(
         zero_threshold: 0.01,
         zero_count: -22.0,
         count: -60.0,
         sum: -46.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [-2.0, 0.0, -6.0, -8.0, -14.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [-6.0, -2.0, -10.0, -12.0]
       )},
      {"no-op with custom buckets",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       ), 1.0,
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       )},
      {"triple with custom buckets",
       h(
         schema: -53,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), 3.0,
       h(
         schema: -53,
         count: 90.0,
         sum: 69.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [3.0, 0.0, 9.0, 12.0, 21.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       )}
    ]
  end

  defp div_cases do
    [
      {"zero value", h(), 3.1415, h()},
      {"zero divisor",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), 0.0, h(zero_threshold: 0.01, zero_count: :infinity, count: :infinity, sum: :infinity)},
      {"no-op",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), 1.0,
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       )},
      {"half",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ), 2.0,
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 15.0,
         sum: 11.5,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [0.5, 0.0, 1.5, 2.0, 3.5],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [1.5, 0.5, 2.5, 3.0]
       )},
      {"negation",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), -1.0,
       h(
         zero_threshold: 0.01,
         zero_count: -5.5,
         count: -3493.3,
         sum: -2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [-1.0, -3.3, -4.2, -0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [-3.1, -3.0, -123_400.0, -1000.0]
       )},
      {"negative half",
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       ), -2.0,
       h(
         zero_threshold: 0.01,
         zero_count: -5.5,
         count: -15.0,
         sum: -11.5,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [-0.5, 0.0, -1.5, -2.0, -3.5],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [-1.5, -0.5, -2.5, -3.0]
       )},
      {"no-op with custom buckets",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       ), 1.0,
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       )},
      {"half with custom buckets",
       h(
         schema: -53,
         count: 30.0,
         sum: 23.0,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), 2.0,
       h(
         schema: -53,
         count: 15.0,
         sum: 11.5,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [0.5, 0.0, 1.5, 2.0, 3.5],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       )}
    ]
  end

  defp compact_cases do
    [
      {"empty histogram", h(), h()},
      {"nothing should happen",
       h(
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       )},
      {"eliminate zero offsets",
       h(
         positive_spans: [{-2, 1}, {0, 3}, {0, 1}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {0, 2}, {2, 1}, {0, 1}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       ),
       h(
         positive_spans: [{-2, 5}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 4}, {2, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"eliminate zero length",
       h(
         positive_spans: [{-2, 2}, {2, 0}, {3, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {0, 0}, {2, 0}, {1, 4}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       ),
       h(
         positive_spans: [{-2, 2}, {5, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 4}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"eliminate multiple zero length spans",
       h(positive_spans: [{-2, 2}, {2, 0}, {2, 0}, {2, 0}, {3, 3}], positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3]),
       h(positive_spans: [{-2, 2}, {9, 3}], positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3])},
      {"cut empty buckets at start or end",
       h(
         positive_spans: [{-4, 4}, {5, 3}],
         positive_buckets: [0.0, 0.0, 1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 5}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0, 0.0]
       ),
       h(
         positive_spans: [{-2, 2}, {5, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 4}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"cut empty buckets at start and end",
       h(
         positive_spans: [{-4, 4}, {5, 6}],
         positive_buckets: [0.0, 0.0, 1.0, 3.3, 4.2, 0.1, 3.3, 0.0, 0.0, 0.0],
         negative_spans: [{-2, 4}, {3, 5}],
         negative_buckets: [0.0, 0.0, 3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0, 0.0]
       ),
       h(
         positive_spans: [{-2, 2}, {5, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 4}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"cut empty buckets in the middle", h(positive_spans: [{5, 4}], positive_buckets: [1.0, 3.0, 0.0, 2.0]),
       h(positive_spans: [{5, 2}, {1, 1}], positive_buckets: [1.0, 3.0, 2.0])},
      {"cut empty buckets at start or end of spans, even in the middle",
       h(
         positive_spans: [{-4, 6}, {3, 6}],
         positive_buckets: [0.0, 0.0, 1.0, 3.3, 0.0, 0.0, 4.2, 0.1, 3.3, 0.0, 0.0, 0.0],
         negative_spans: [{0, 2}, {2, 6}],
         negative_buckets: [3.1, 3.0, 0.0, 123_400.0, 1000.0, 3.0, 4.0, 0.0]
       ),
       h(
         positive_spans: [{-2, 2}, {5, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 4}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"cut empty buckets from the middle of a span",
       h(
         positive_spans: [{-4, 6}, {3, 3}],
         positive_buckets: [0.0, 0.0, 1.0, 0.0, 0.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 5}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 0.0, 3.0, 4.0]
       ),
       h(
         positive_spans: [{-2, 1}, {2, 1}, {3, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         negative_spans: [{0, 2}, {3, 2}, {1, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0, 3.0, 4.0]
       )},
      {"cut out a span containing only empty buckets",
       h(positive_spans: [{-4, 3}, {2, 2}, {3, 4}], positive_buckets: [0.0, 0.0, 1.0, 0.0, 0.0, 3.3, 4.2, 0.1, 3.3]),
       h(positive_spans: [{-2, 1}, {7, 4}], positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3])},
      {"multiple spans of only empty buckets",
       h(
         positive_spans: [{-10, 2}, {2, 1}, {3, 3}],
         positive_buckets: [0.0, 0.0, 0.0, 0.0, 2.0, 3.0],
         negative_spans: [{-10, 2}, {2, 1}, {3, 3}],
         negative_buckets: [2.0, 3.0, 0.0, 0.0, 0.0, 0.0]
       ),
       h(
         positive_spans: [{-1, 2}],
         positive_buckets: [2.0, 3.0],
         negative_spans: [{-10, 2}],
         negative_buckets: [2.0, 3.0]
       )},
      {"nothing should happen with custom buckets",
       h(
         schema: -53,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       ),
       h(
         schema: -53,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       )},
      {"eliminate zero offsets with custom buckets",
       h(
         schema: -53,
         positive_spans: [{0, 1}, {0, 3}, {0, 1}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         positive_spans: [{0, 5}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       )},
      {"eliminate multiple zero length spans with custom buckets",
       h(
         schema: -53,
         positive_spans: [{0, 2}, {2, 0}, {2, 0}, {2, 0}, {3, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         positive_spans: [{0, 2}, {9, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       )},
      {"cut empty buckets at start and end with custom buckets",
       h(
         schema: -53,
         positive_spans: [{0, 4}, {5, 6}],
         positive_buckets: [0.0, 0.0, 1.0, 3.3, 4.2, 0.1, 3.3, 0.0, 0.0, 0.0],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
       ),
       h(
         schema: -53,
         positive_spans: [{2, 2}, {5, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1, 3.3],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
       )}
    ]
  end

  defp detect_reset_cases do
    [
      {"zero values", h(), h(), false},
      {"no buckets to some buckets",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), h(), false},
      {"some buckets to no buckets", h(),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"one bucket appears, nothing else changes",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"one bucket disappears, nothing else changes",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"an unpopulated bucket disappears, nothing else changes",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"an unpopulated bucket at the end disappears, nothing else changes",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {1, 2}],
         positive_buckets: [1.0, 3.3, 4.2],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 1}, {1, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"an unpopulated bucket disappears in a histogram with nothing else", h(),
       h(positive_spans: [{23, 1}], positive_buckets: [0.0]), false},
      {"zero count goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.6,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"zero count goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.4,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"count goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.4,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"count goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.2,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"sum goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_210.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"sum goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_200.0,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"one positive bucket goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.3, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"one positive bucket goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.1, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"one negative bucket goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.1, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"one negative bucket goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 2.9, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"zero threshold decreases",
       h(
         zero_threshold: 0.009,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"zero threshold increases without touching any existing buckets",
       h(
         zero_threshold: 0.011,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"zero threshold increases enough to cover existing buckets",
       h(
         zero_threshold: 1.0,
         zero_count: 7.73,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{1, 3}],
         positive_buckets: [3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), false},
      {"zero threshold increases into the middle of an existing buckets",
       h(
         zero_threshold: 0.3,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"schema increases without any other changes",
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-5, 4}, {2, 6}],
         positive_buckets: [0.4, 0.6, 1.0, 0.23, 2.0, 1.3, 1.2, 3.0, 0.05, 0.05],
         negative_spans: [{5, 4}, {6, 4}],
         negative_buckets: [2.0, 1.1, 2.0, 1.0, 23_400.0, 100_000.0, 500.0, 500.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ), true},
      {"schema decreases without any other changes",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-5, 4}, {2, 6}],
         positive_buckets: [0.4, 0.6, 1.0, 0.23, 2.0, 1.3, 1.2, 3.0, 0.05, 0.05],
         negative_spans: [{5, 4}, {6, 4}],
         negative_buckets: [2.0, 1.1, 2.0, 1.0, 23_400.0, 100_000.0, 500.0, 500.0]
       ), false},
      {"schema decreases and a bucket goes up",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 4.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-5, 4}, {2, 6}],
         positive_buckets: [0.4, 0.6, 1.0, 0.23, 2.0, 1.3, 1.2, 3.0, 0.05, 0.05],
         negative_spans: [{5, 4}, {6, 4}],
         negative_buckets: [2.0, 1.1, 2.0, 1.0, 23_400.0, 100_000.0, 500.0, 500.0]
       ), false},
      {"schema decreases and a bucket goes down",
       h(
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-2, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 2.3, 4.2, 0.1],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.1, 3.0, 123_400.0, 1000.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 5.5,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{-5, 4}, {2, 6}],
         positive_buckets: [0.4, 0.6, 1.0, 0.23, 2.0, 1.3, 1.2, 3.0, 0.05, 0.05],
         negative_spans: [{5, 4}, {6, 4}],
         negative_buckets: [2.0, 1.1, 2.0, 1.0, 23_400.0, 100_000.0, 500.0, 500.0]
       ), true},
      {"no buckets to some buckets with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       ), h(schema: -53, custom_values: [1.0, 2.0, 3.0]), false},
      {"some buckets to no buckets with custom bounds", h(schema: -53, custom_values: [1.0, 2.0, 3.0]),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0]
       ), true},
      {"one bucket appears, nothing else changes with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), false},
      {"one bucket disappears, nothing else changes with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 1.23, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), true},
      {"an unpopulated bucket disappears, nothing else changes with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 1}, {2, 3}],
         positive_buckets: [1.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), false},
      {"one positive bucket goes up with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.3, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), false},
      {"one positive bucket goes down with custom bounds",
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.1, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ),
       h(
         schema: -53,
         count: 3493.3,
         sum: 2_349_209.324,
         positive_spans: [{0, 2}, {1, 3}],
         positive_buckets: [1.0, 0.0, 3.3, 4.2, 0.1],
         custom_values: [1.0, 2.0, 3.0, 4.0]
       ), true}
    ]
  end

  defp copy_to_schema_cases do
    [
      {"no schema change", 1,
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       )},
      {"schema change", 0,
       h(
         schema: 1,
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-4, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         negative_spans: [{6, 3}, {6, 4}],
         negative_buckets: [3.0, 0.5, 0.5, 2.0, 3.0, 2.0, 4.0]
       ),
       h(
         zero_threshold: 0.01,
         zero_count: 11.0,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{-2, 2}, {2, 3}],
         positive_buckets: [1.0, 0.0, 3.0, 4.0, 7.0],
         negative_spans: [{3, 2}, {3, 2}],
         negative_buckets: [3.0, 1.0, 5.0, 6.0]
       )},
      {"no schema change for custom buckets", -53,
       h(
         schema: -53,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{0, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
       ),
       h(
         schema: -53,
         count: 30.0,
         sum: 2.345,
         positive_spans: [{0, 3}, {5, 5}],
         positive_buckets: [1.0, 0.0, 0.0, 3.0, 2.0, 2.0, 3.0, 4.0],
         custom_values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
       )}
    ]
  end

  defp reduce_resolution_cases do
    [
      {h(
         positive_spans: [{0, 4}, {0, 0}, {3, 2}],
         positive_buckets: [1.0, 3.0, 1.0, 2.0, 1.0, 1.0],
         negative_spans: [{0, 4}, {0, 0}, {3, 2}],
         negative_buckets: [1.0, 3.0, 1.0, 2.0, 1.0, 1.0]
       ),
       h(
         schema: -1,
         positive_spans: [{0, 3}, {1, 1}],
         positive_buckets: [1.0, 4.0, 2.0, 2.0],
         negative_spans: [{0, 3}, {1, 1}],
         negative_buckets: [1.0, 4.0, 2.0, 2.0]
       )}
    ]
  end

  defp json_buckets_cases do
    [
      {h(
         schema: 1,
         zero_threshold: 0.001,
         zero_count: 102.0,
         count: 405.0,
         sum: 1008.4,
         positive_spans: [{0, 4}, {1, 0}, {3, 3}, {3, 0}, {2, 0}, {5, 3}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0, 3.0, 63.0, 2.0, 54.0, 235.0, 33.0],
         negative_spans: [{0, 3}, {1, 0}, {3, 0}, {3, 4}, {2, 0}, {5, 3}],
         negative_buckets: [10.0, 34.0, 1230.0, 54.0, 67.0, 63.0, 2.0, 554.0, 235.0, 33.0]
       ),
       [
         {1, -2896.3093757400984, -2048.0, 33.0},
         {1, -2048.0, -1448.1546878700492, 235.0},
         {1, -1448.1546878700492, -1024.0, 554.0},
         {1, -90.50966799187808, -64.0, 2.0},
         {1, -64.0, -45.25483399593904, 63.0},
         {1, -45.25483399593904, -32.0, 67.0},
         {1, -32.0, -22.62741699796952, 54.0},
         {1, -2.0, -1.414213562373095, 1230.0},
         {1, -1.414213562373095, -1.0, 34.0},
         {1, -1.0, -0.7071067811865475, 10.0},
         {3, -0.001, 0.001, 102.0},
         {0, 0.7071067811865475, 1.0, 100.0},
         {0, 1.0, 1.414213562373095, 344.0},
         {0, 1.414213562373095, 2.0, 123.0},
         {0, 2.0, 2.82842712474619, 55.0},
         {0, 11.31370849898476, 16.0, 3.0},
         {0, 16.0, 22.62741699796952, 63.0},
         {0, 22.62741699796952, 32.0, 2.0},
         {0, 1024.0, 1448.1546878700492, 54.0},
         {0, 1448.1546878700492, 2048.0, 235.0},
         {0, 2048.0, 2896.3093757400984, 33.0}
       ]},
      {h(
         schema: 1,
         zero_threshold: 0.001,
         zero_count: 102.0,
         count: 405.0,
         sum: 1008.4,
         negative_spans: [{0, 3}, {1, 0}, {3, 0}, {3, 4}, {2, 0}, {5, 3}],
         negative_buckets: [10.0, 34.0, 1230.0, 54.0, 67.0, 63.0, 2.0, 554.0, 235.0, 33.0]
       ),
       [
         {1, -2896.3093757400984, -2048.0, 33.0},
         {1, -2048.0, -1448.1546878700492, 235.0},
         {1, -1448.1546878700492, -1024.0, 554.0},
         {1, -90.50966799187808, -64.0, 2.0},
         {1, -64.0, -45.25483399593904, 63.0},
         {1, -45.25483399593904, -32.0, 67.0},
         {1, -32.0, -22.62741699796952, 54.0},
         {1, -2.0, -1.414213562373095, 1230.0},
         {1, -1.414213562373095, -1.0, 34.0},
         {1, -1.0, -0.7071067811865475, 10.0},
         {3, -0.001, 0.001, 102.0}
       ]},
      {h(
         schema: 1,
         zero_threshold: 0.001,
         zero_count: 102.0,
         count: 405.0,
         sum: 1008.4,
         positive_spans: [{0, 4}, {1, 0}, {3, 3}, {3, 0}, {2, 0}, {5, 3}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0, 3.0, 63.0, 2.0, 54.0, 235.0, 33.0]
       ),
       [
         {3, -0.001, 0.001, 102.0},
         {0, 0.7071067811865475, 1.0, 100.0},
         {0, 1.0, 1.414213562373095, 344.0},
         {0, 1.414213562373095, 2.0, 123.0},
         {0, 2.0, 2.82842712474619, 55.0},
         {0, 11.31370849898476, 16.0, 3.0},
         {0, 16.0, 22.62741699796952, 63.0},
         {0, 22.62741699796952, 32.0, 2.0},
         {0, 1024.0, 1448.1546878700492, 54.0},
         {0, 1448.1546878700492, 2048.0, 235.0},
         {0, 2048.0, 2896.3093757400984, 33.0}
       ]},
      {h(schema: 1, zero_threshold: 0.001, zero_count: 102.0, count: 405.0, sum: 1008.4), [{3, -0.001, 0.001, 102.0}]},
      {h(
         schema: 1,
         zero_threshold: 0.001,
         count: 405.0,
         sum: 1008.4,
         positive_spans: [{0, 4}, {1, 0}, {3, 3}, {3, 0}, {2, 0}, {5, 3}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0, 3.0, 63.0, 2.0, 54.0, 235.0, 33.0],
         negative_spans: [{0, 3}, {1, 0}, {3, 0}, {3, 4}, {2, 0}, {5, 3}],
         negative_buckets: [10.0, 34.0, 1230.0, 54.0, 67.0, 63.0, 2.0, 554.0, 235.0, 33.0]
       ),
       [
         {1, -2896.3093757400984, -2048.0, 33.0},
         {1, -2048.0, -1448.1546878700492, 235.0},
         {1, -1448.1546878700492, -1024.0, 554.0},
         {1, -90.50966799187808, -64.0, 2.0},
         {1, -64.0, -45.25483399593904, 63.0},
         {1, -45.25483399593904, -32.0, 67.0},
         {1, -32.0, -22.62741699796952, 54.0},
         {1, -2.0, -1.414213562373095, 1230.0},
         {1, -1.414213562373095, -1.0, 34.0},
         {1, -1.0, -0.7071067811865475, 10.0},
         {0, 0.7071067811865475, 1.0, 100.0},
         {0, 1.0, 1.414213562373095, 344.0},
         {0, 1.414213562373095, 2.0, 123.0},
         {0, 2.0, 2.82842712474619, 55.0},
         {0, 11.31370849898476, 16.0, 3.0},
         {0, 16.0, 22.62741699796952, 63.0},
         {0, 22.62741699796952, 32.0, 2.0},
         {0, 1024.0, 1448.1546878700492, 54.0},
         {0, 1448.1546878700492, 2048.0, 235.0},
         {0, 2048.0, 2896.3093757400984, 33.0}
       ]},
      {h(
         zero_threshold: 0.5,
         zero_count: 42.0,
         count: 447.0,
         sum: 1008.4,
         positive_spans: [{0, 4}, {1, 0}, {3, 3}, {3, 0}, {2, 0}, {5, 3}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0, 3.0, 63.0, 2.0, 54.0, 235.0, 33.0],
         negative_spans: [{0, 3}, {1, 0}, {3, 0}, {3, 4}, {2, 0}, {5, 3}],
         negative_buckets: [10.0, 34.0, 1230.0, 54.0, 67.0, 63.0, 2.0, 554.0, 235.0, 33.0]
       ),
       [
         {1, -8_388_608.0, -4_194_304.0, 33.0},
         {1, -4_194_304.0, -2_097_152.0, 235.0},
         {1, -2_097_152.0, -1_048_576.0, 554.0},
         {1, -8192.0, -4096.0, 2.0},
         {1, -4096.0, -2048.0, 63.0},
         {1, -2048.0, -1024.0, 67.0},
         {1, -1024.0, -512.0, 54.0},
         {1, -4.0, -2.0, 1230.0},
         {1, -2.0, -1.0, 34.0},
         {1, -1.0, -0.5, 10.0},
         {3, -0.5, 0.5, 42.0},
         {0, 0.5, 1.0, 100.0},
         {0, 1.0, 2.0, 344.0},
         {0, 2.0, 4.0, 123.0},
         {0, 4.0, 8.0, 55.0},
         {0, 128.0, 256.0, 3.0},
         {0, 256.0, 512.0, 63.0},
         {0, 512.0, 1024.0, 2.0},
         {0, 1_048_576.0, 2_097_152.0, 54.0},
         {0, 2_097_152.0, 4_194_304.0, 235.0},
         {0, 4_194_304.0, 8_388_608.0, 33.0}
       ]},
      {h(
         zero_threshold: 0.6,
         zero_count: 42.0,
         count: 447.0,
         sum: 1008.4,
         positive_spans: [{0, 4}, {1, 0}, {3, 3}, {3, 0}, {2, 0}, {5, 3}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0, 3.0, 63.0, 2.0, 54.0, 235.0, 33.0],
         negative_spans: [{0, 3}, {1, 0}, {3, 0}, {3, 4}, {2, 0}, {5, 3}],
         negative_buckets: [10.0, 34.0, 1230.0, 54.0, 67.0, 63.0, 2.0, 554.0, 235.0, 33.0]
       ),
       [
         {1, -8_388_608.0, -4_194_304.0, 33.0},
         {1, -4_194_304.0, -2_097_152.0, 235.0},
         {1, -2_097_152.0, -1_048_576.0, 554.0},
         {1, -8192.0, -4096.0, 2.0},
         {1, -4096.0, -2048.0, 63.0},
         {1, -2048.0, -1024.0, 67.0},
         {1, -1024.0, -512.0, 54.0},
         {1, -4.0, -2.0, 1230.0},
         {1, -2.0, -1.0, 34.0},
         {1, -1.0, -0.6, 10.0},
         {3, -0.6, 0.6, 42.0},
         {0, 0.6, 1.0, 100.0},
         {0, 1.0, 2.0, 344.0},
         {0, 2.0, 4.0, 123.0},
         {0, 4.0, 8.0, 55.0},
         {0, 128.0, 256.0, 3.0},
         {0, 256.0, 512.0, 63.0},
         {0, 512.0, 1024.0, 2.0},
         {0, 1_048_576.0, 2_097_152.0, 54.0},
         {0, 2_097_152.0, 4_194_304.0, 235.0},
         {0, 4_194_304.0, 8_388_608.0, 33.0}
       ]},
      {h(
         schema: -53,
         count: 622.0,
         sum: 10_008.4,
         positive_spans: [{0, 2}, {1, 1}, {1, 1}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0],
         custom_values: [10.0, 25.0, 50.0, 100.0, 500.0]
       ),
       [
         {3, :negative_infinity, 10.0, 100.0},
         {0, 10.0, 25.0, 344.0},
         {0, 50.0, 100.0, 123.0},
         {0, 500.0, :infinity, 55.0}
       ]},
      {h(
         schema: -53,
         count: 622.0,
         sum: 10_008.4,
         positive_spans: [{0, 2}, {1, 1}, {1, 1}],
         positive_buckets: [100.0, 344.0, 123.0, 55.0],
         custom_values: [-10.0, -5.0, 0.0, 10.0, 25.0]
       ),
       [
         {3, :negative_infinity, -10.0, 100.0},
         {0, -10.0, -5.0, 344.0},
         {0, 0.0, 10.0, 123.0},
         {0, 25.0, :infinity, 55.0}
       ]}
    ]
  end

  defp bound_cases do
    [
      {-1, -1, 0.25},
      {0, -1, 1.0},
      {1, -1, 4.0},
      {512, -1, @max_float},
      {513, -1, :infinity},
      {-1, 0, 0.5},
      {0, 0, 1.0},
      {1, 0, 2.0},
      {1024, 0, @max_float},
      {1025, 0, :infinity},
      {-1, 2, 0.8408964152537144},
      {0, 2, 1.0},
      {1, 2, 1.189207115002721},
      {4096, 2, @max_float},
      {4097, 2, :infinity}
    ]
  end
end
