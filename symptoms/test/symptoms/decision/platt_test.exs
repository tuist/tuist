defmodule Symptoms.Decision.PlattTest do
  use ExUnit.Case, async: true

  alias Symptoms.Decision.Platt

  test "the prior maps the threshold to P = 0.5" do
    prior = Platt.prior(3.0)

    assert prior == %{a: -3.0, b: 1.0}
    assert_in_delta Platt.probability(prior, 3.0), 0.5, 1.0e-12
    # sigmoid(1) = 1 / (1 + e^-1)
    assert_in_delta Platt.probability(prior, 4.0), 1 / (1 + :math.exp(-1)), 1.0e-12
  end

  test "recovers known parameters from synthetic labels" do
    :rand.seed(:exsss, {1, 2, 3})
    truth = %{a: -3.0, b: 0.8}

    samples =
      for _ <- 1..20_000 do
        score = :rand.uniform() * 10
        {score, :rand.uniform() < Platt.probability(truth, score)}
      end

    fit = Platt.fit(samples)

    assert_in_delta fit.a, -3.0, 0.15
    assert_in_delta fit.b, 0.8, 0.03
  end

  test "weights act as repeated samples" do
    weighted = [{1.0, true, 2}, {2.0, false}, {3.0, true}, {0.0, false}]
    repeated = [{1.0, true}, {1.0, true}, {2.0, false}, {3.0, true}, {0.0, false}]

    a = Platt.fit(weighted)
    b = Platt.fit(repeated)
    assert_in_delta a.a, b.a, 1.0e-8
    assert_in_delta a.b, b.b, 1.0e-8
  end

  test "the L2 prior keeps separable labels finite and near the prior" do
    fit = Platt.fit([{0.0, false}, {5.0, true}], prior: Platt.prior(2.5), lambda: 1.0)

    assert is_float(fit.a) and is_float(fit.b)
    assert Platt.probability(fit, 0.0) < 0.5
    assert Platt.probability(fit, 5.0) > 0.5
  end

  describe "bounded refit" do
    test "moves only the intercept, to its maximum-likelihood value when within 0.5 logit" do
      # 6 of 10 degraded at score 3 with slope 1: sigmoid(a + 3) = 0.6 → a = -3 + ln 1.5.
      samples = for i <- 1..10, do: {3.0, i <= 6}
      refit = Platt.bounded_refit(Platt.prior(3.0), samples, lambda: 0.0)

      assert_in_delta refit.a, -3.0 + :math.log(1.5), 1.0e-9
      assert refit.b == 1.0
    end

    test "clamps the intercept move to 0.5 logit" do
      missed = for _ <- 1..50, do: {0.0, true}
      fine = for _ <- 1..50, do: {3.0, false}

      assert Platt.bounded_refit(Platt.prior(3.0), missed).a == -2.5
      assert Platt.bounded_refit(Platt.prior(3.0), fine).a == -3.5
    end
  end
end
