defmodule Symptoms.Evidence.VersionTestTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.VersionTest

  test "extreme windows retain finite log evidence in both directions" do
    # With equal traffic and all 1200 errors on one version, the dominant
    # component is ψ=10 (regression) or ψ=1.5 (improvement).
    positive = VersionTest.window_log_e(1200, 2000, 0, 2000)
    negative = VersionTest.window_log_e(0, 2000, 1200, 2000)
    assert_in_delta positive, 1200 * :math.log(20 / 11) - :math.log(5), 1.0e-9
    assert_in_delta negative, 1200 * :math.log(0.8) - :math.log(5), 1.0e-9
    assert is_float(VersionTest.window_e(1200, 2000, 0, 2000))
  end

  test "underflow retains a finite log statistic rather than logging zero" do
    # Even the largest component is exp(4000 ln 0.8) < the float range.
    assert_in_delta VersionTest.window_log_e(0, 4000, 4000, 4000), 4000 * :math.log(0.8) - :math.log(5), 1.0e-9
    assert VersionTest.window_e(0, 4000, 4000, 4000) == 0.0
  end

  test "170 sustained updates retain the mixture in log space" do
    weights = Enum.reduce(1..170, VersionTest.initial(), fn _, w -> VersionTest.update(w, 10, 100, 1, 100) end)
    # Dominant ψ=10 component: 170 * (10 ln(20/11) + ln(2/11)) − ln 5.
    expected = 170 * (10 * :math.log(20 / 11) + :math.log(2 / 11)) - :math.log(5)
    assert_in_delta VersionTest.log_e_value(weights), expected, 1.0e-8
    assert is_float(VersionTest.e_value(weights))
  end

  test "a window without errors or traffic is uninformative" do
    assert VersionTest.window_e(0, 100, 0, 100) == 1.0
    assert VersionTest.window_e(5, 0, 1, 100) == 1.0
  end

  test "one component's likelihood ratio matches the closed form" do
    # Equal traffic: π₀ = 1/2. ψ = 3: θ = 1.5 / 2 = 0.75. All k = 4 errors on
    # the new version: LR = (0.75 / 0.5)^4 = 5.0625.
    [_, _, log_lr3 | _] = VersionTest.window_log_lrs(4, 100, 0, 100)
    assert_in_delta log_lr3, :math.log(5.0625), 1.0e-12
  end

  test "the mixture has mean 1 under the null (exact sum over the binomial)" do
    # k = 6 errors split with π₀ = 1/3 (new serves 100 of 300 requests).
    # E[e] = Σ_x C(6, x) π₀^x (1 − π₀)^(6 − x) · e(x) must be 1.
    pi0 = 1 / 3

    mean =
      Enum.sum(
        for x <- 0..6 do
          binomial =
            Enum.reduce(1..6//1, 1, &(&1 * &2)) /
              (Enum.reduce(1..x//1, 1, &(&1 * &2)) * Enum.reduce(1..(6 - x)//1, 1, &(&1 * &2)))

          binomial * :math.pow(pi0, x) * :math.pow(1 - pi0, 6 - x) * VersionTest.window_e(x, 100, 6 - x, 200)
        end
      )

    assert_in_delta mean, 1.0, 1.0e-12
  end

  test "accumulates over windows and rejects a regressed version" do
    weights = Enum.reduce(1..5, VersionTest.initial(), fn _, w -> VersionTest.update(w, 10, 100, 1, 100) end)
    assert VersionTest.e_value(weights) > 20
  end
end
