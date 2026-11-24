defmodule Symptoms.Evidence.BurstTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Burst

  @week 7 * 288

  test "one large window is a candidate without accumulating sustained evidence" do
    baseline = %{mean: 2.0, alpha: 0.5, n: @week}
    assert {:ok, %{candidate: false}} = Burst.evaluate(2, baseline)
    assert {:ok, %{candidate: true, observed: 995, expected: 2.0}} = Burst.evaluate(995, baseline)
    # No state or previous crossing is needed for the next burst.
    assert {:ok, %{candidate: true}} = Burst.evaluate(743, baseline)
  end

  test "the bound uses overdispersion rather than treating every count as Poisson" do
    assert {:ok, poisson} = Burst.evaluate(30, %{mean: 2.0, alpha: 0.0, n: @week})
    assert {:ok, dispersed} = Burst.evaluate(30, %{mean: 2.0, alpha: 5.0, n: @week})
    assert poisson.candidate
    refute dispersed.candidate
    assert poisson.log_tail_bound < dispersed.log_tail_bound
  end

  test "the Poisson Chernoff bound matches its closed form" do
    assert {:ok, result} = Burst.evaluate(4, %{mean: 1.0, alpha: 0.0, n: @week})
    # exp(4 - 1) * (1/4)^4 bounds P(Poisson(1) >= 4).
    assert_in_delta result.log_tail_bound, 3 - 4 * :math.log(4), 1.0e-12
    exact_tail = 1 - :math.exp(-1) * (1 + 1 + 1 / 2 + 1 / 6)
    assert :math.exp(result.log_tail_bound) >= exact_tail
  end

  test "the negative-binomial bound matches its closed form" do
    assert {:ok, result} = Burst.evaluate(6, %{mean: 2.0, alpha: 0.5, n: @week})
    # NB(shape=2, p=1/2): the optimum MGF bound is 2^8 / 3^6;
    # the exact tail at 6 is 8/128.
    assert_in_delta result.log_tail_bound, 8 * :math.log(2) - 6 * :math.log(3), 1.0e-12
    assert :math.exp(result.log_tail_bound) >= 8 / 128
  end

  test "vanishing dispersion approaches the Poisson limit without cancellation" do
    baseline = %{mean: 2.0, alpha: 0.0, n: @week}
    assert {:ok, poisson} = Burst.evaluate(30, baseline)
    assert {:ok, near_poisson} = Burst.evaluate(30, %{baseline | alpha: 1.0e-16})
    assert_in_delta near_poisson.log_tail_bound, poisson.log_tail_bound, 1.0e-10
  end

  test "a billion events stays in log space" do
    for alpha <- [0.0, 0.5] do
      assert {:ok, result} = Burst.evaluate(1_000_000_000, %{mean: 2.0, alpha: alpha, n: @week})
      assert result.candidate
      assert result.log_tail_bound < -1000
    end
  end

  test "extreme dispersion does not manufacture evidence through subtracting large logarithms" do
    assert {:ok, result} = Burst.evaluate(1_000_000_000, %{mean: 0.0005, alpha: 1.0e12, n: @week})
    # Independent 80-digit Decimal evaluation of the NB Chernoff formula.
    assert_in_delta result.log_tail_bound, -1.9999999979706758, 1.0e-12
    refute result.candidate
  end

  test "missing input and short history are unknown, not quiet or zero" do
    assert {:unknown, :missing_observation} = Burst.evaluate(nil, %{mean: 2.0, alpha: 0.0, n: @week})
    assert {:unknown, :missing_baseline} = Burst.evaluate(995, nil)
    assert {:unknown, :insufficient_history} = Burst.evaluate(995, %{mean: 2.0, alpha: 0.0, n: @week - 1})
  end

  test "exposure is a week of windows, not the number of nonempty buckets" do
    assert {:unknown, :insufficient_history} =
             Burst.evaluate(995, %{mean: 2.0, alpha: 0.0, n: @week}, window_seconds: 60)

    assert {:ok, _} = Burst.evaluate(995, %{mean: 2.0, alpha: 0.0, n: 7 * 1440}, window_seconds: 60)
  end

  test "known quiet history uses a finite rate floor; known zero observations are quiet" do
    baseline = %{mean: 0.0, alpha: 0.0, n: @week}
    assert {:ok, quiet} = Burst.evaluate(0, baseline)
    refute quiet.candidate
    assert quiet.log_tail_bound == 0.0
    assert {:ok, %{candidate: true}} = Burst.evaluate(995, baseline)
  end

  test "the nominal daily budget is divided among all windows of one service" do
    baseline = %{mean: 2.0, alpha: 0.0, n: 7 * 1440}
    assert {:ok, minute} = Burst.evaluate(0, baseline, window_seconds: 60)
    assert {:ok, five_minutes} = Burst.evaluate(0, baseline, window_seconds: 300)
    assert_in_delta minute.log_cutoff, :math.log(0.001 / 1440), 1.0e-12
    assert_in_delta five_minutes.log_cutoff, :math.log(0.001 / 288), 1.0e-12
    assert minute.log_cutoff < five_minutes.log_cutoff
  end

  test "model-null controls respect the nominal budget, not just a few chosen quiet values" do
    baseline = %{mean: 2.0, alpha: 0.5, n: @week}

    # Exact NB(shape=2, p=1/2) mass: P(X=k) = (k+1)/2^(k+2).
    # The unevaluated tail above 100 is 103/2^102, also counted as crossing.
    false_crossings =
      for count <- 0..100, reduce: 103 / :math.pow(2, 102) do
        sum ->
          {:ok, result} = Burst.evaluate(count, baseline)
          sum + if(result.candidate, do: (count + 1) / :math.pow(2, count + 2), else: 0.0)
      end

    assert false_crossings <= 0.001 / 288
  end

  test "both sides of a known tail boundary change the candidate decision" do
    baseline = %{mean: 1.0, alpha: 0.0, n: 7}
    # The bound at 4 is exp(3)/256, between 0.01 and 0.1.
    assert {:ok, %{candidate: true}} =
             Burst.evaluate(4, baseline, window_seconds: 86_400, crossings_per_service_day: 0.1)

    assert {:ok, %{candidate: false}} =
             Burst.evaluate(4, baseline, window_seconds: 86_400, crossings_per_service_day: 0.01)
  end
end
