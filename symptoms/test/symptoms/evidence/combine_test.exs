defmodule Symptoms.Evidence.CombineTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Combine

  describe "source weights" do
    test "equal raw weights give equal normalized weights" do
      weights = Combine.source_weights(%{}, [:a, :b, :c, :d])

      for {_source, weight} <- weights, do: assert_in_delta(weight, 0.25, 1.0e-9)
    end

    test "weights are bounded to 0.5–2× the equal weight" do
      # k = 3: bounds [1/6, 2/3]. c caps at 2/3, a and b share 1/3.
      weights = Combine.source_weights(%{a: 1, b: 1, c: 10}, [:a, :b, :c])

      assert_in_delta weights.a, 1 / 6, 1.0e-9
      assert_in_delta weights.b, 1 / 6, 1.0e-9
      assert_in_delta weights.c, 2 / 3, 1.0e-9
    end

    test "a zero raw weight is raised to the lower bound" do
      # k = 2: bounds [1/4, 1].
      weights = Combine.source_weights(%{a: 0, b: 1}, [:a, :b])

      assert_in_delta weights.a, 0.25, 1.0e-9
      assert_in_delta weights.b, 0.75, 1.0e-9
    end

    test "proportions inside the bounds are kept" do
      # 1:1.5 over k = 2 → 0.4 and 0.6, both inside [0.25, 1].
      weights = Combine.source_weights(%{a: 1, b: 1.5}, [:a, :b])

      assert_in_delta weights.a, 0.4, 1.0e-9
      assert_in_delta weights.b, 0.6, 1.0e-9
    end
  end

  describe "phenomenon e-value" do
    test "is the weighted mean of the sources' e-values" do
      assert_in_delta Combine.phenomenon_e([{:a, 4}, {:b, 1}], %{}), 2.5, 1.0e-9
      # 20/6 + 1/6 + 2 · 2/3
      assert_in_delta Combine.phenomenon_e([{:a, 20}, {:b, 1}, {:c, 2}], %{a: 1, b: 1, c: 10}),
                      20 / 6 + 1 / 6 + 4 / 3,
                      1.0e-9

      assert Combine.phenomenon_e([], %{}) == 1.0
    end
  end

  describe "log-evidence" do
    test "adds the phenomena's logs, each capped at ln 20" do
      # ln 20 + min(ln 400, ln 20) + ln 0.5
      assert_in_delta Combine.log_evidence(%{a: 20, b: 400, c: 0.5}),
                      2 * :math.log(20) - :math.log(2),
                      1.0e-12

      assert_in_delta Combine.log_evidence(%{a: 0}), -:math.log(20), 1.0e-12
      assert_in_delta Combine.log_evidence(%{a: 400}, cap_nats: 1.0), 1.0, 1.0e-12
    end

    test "scores evidence records by phenomenon" do
      records = [
        %{phenomenon: :request_errors, source: "trace.errors", e: 4.0},
        %{phenomenon: :request_errors, source: "log.errors", e: 1.0},
        %{phenomenon: :latency, source: "trace.latency_p95", e: 0.5}
      ]

      score = Combine.score(records)

      # ln 2.5 + ln 0.5 = ln 1.25
      assert_in_delta score.log_evidence, :math.log(1.25), 1.0e-12

      assert [%{phenomenon: :latency}, %{phenomenon: :request_errors, sources: ["log.errors", "trace.errors"]}] =
               score.phenomena
    end
  end

  describe "CUSUM" do
    test "accumulates log-evidence minus drift, floored at zero" do
      # 0 + 1 - 0.5 = 0.5; 0.5 + 2 - 0.5 = 2; 2 - 4 - 0.5 < 0 → 0; 0 + 3 - 0.5 = 2.5; 2.5 + 2.5 = 5
      assert Combine.cusum([1, 2, -4, 3, 3], 0.5) == [0.5, 2.0, 0.0, 2.5, 5.0]
      assert Combine.cusum_step(1.0, -0.2, 0.0) == 0.8
    end
  end
end
