defmodule Symptoms.CalibrateTest do
  use ExUnit.Case, async: true

  alias Symptoms.Calibrate
  alias Symptoms.Decision.Platt

  test "the recall gate pages unknown impact only at the probability floor, not known zero" do
    at = ~U[2026-11-16 10:00:00Z]
    row = fn score, impact -> {nil, nil, at, 60, score, impact} end

    replay = %{
      {"high", "bad"} => [row.(9.0, nil)],
      {"low", "bad"} => [row.(7.0, nil)],
      {"zero", "bad"} => [row.(9.0, 0.0)],
      {"fine", "fine"} => [row.(9.0, nil)]
    }

    prices = %{day_price: 600.0, night_price: 27_000.0, floor_rate: 100.0}
    assert Calibrate.gate_counts(replay, Platt.prior(6.0), prices) == %{recall: 1, false_pages: 1}
  end

  test "source weights compare a source's bad share with its phenomenon's, bounded 0.5–2" do
    phenomena = fn sources -> [%{"phenomenon" => "request_errors", "sources" => sources}] end

    labels = [
      {"bad", 1.0, phenomena.(["a", "b"])},
      {"bad", 1.0, phenomena.(["a"])},
      {"fine", 1.0, phenomena.(["b"])},
      {"fine", 1.0, phenomena.(["b"])}
    ]

    weights = Calibrate.source_weights(labels)
    # Phenomenon: (2 + 1)/(4 + 2) = 0.5. a: (2 + 1)/(2 + 2) = 0.75 → 1.5.
    # b: (1 + 1)/(3 + 2) = 0.4 → 0.8.
    assert_in_delta elem(weights[{"request_errors", "a"}], 0), 1.5, 1.0e-12
    assert_in_delta elem(weights[{"request_errors", "b"}], 0), 0.8, 1.0e-12
  end

  test "the replay gate counts recall and false pages" do
    prices = %{day_price: 600.0, night_price: 27_000.0, floor_rate: 100.0}
    # Monday 10:00 UTC: day, 60 minutes until review.
    at = ~U[2026-11-16 10:00:00Z]
    row = fn score, impact -> {nil, nil, at, 60, score, impact} end

    replay = %{
      # P(8 − 6) = 0.881; 0.881 · 50 · 60 = 2642 > 600: pages.
      {"bad1", "bad"} => [row.(8.0, 50.0)],
      # P(4 − 6) = 0.119; 0.119 · 50 · 60 = 358 < 600: does not page.
      {"bad2", "bad"} => [row.(4.0, 50.0)],
      {"fine1", "fine"} => [row.(8.0, 50.0)]
    }

    assert Calibrate.gate_counts(replay, Platt.prior(6.0), prices) == %{recall: 1, false_pages: 1}
    # Moving the intercept +0.5 (P(4) = sigmoid(−1.5) = 0.182 → 546 < 600) changes nothing.
    assert Calibrate.gate_counts(replay, %{a: -5.5, b: 1.0}, prices) == %{recall: 1, false_pages: 1}
  end
end
