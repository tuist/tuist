defmodule Pulse.Alerting.NativeThresholdTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.{Lifecycle, Rule}

  defp rule(extra \\ %{}) do
    input =
      Map.merge(
        %{
          "kind" => "logql_threshold",
          "name" => "API errors",
          "query" => ~s'sum(count_over_time({service="api"} |= "error" [1m]))',
          "threshold" => %{"op" => "gt", "value" => 0},
          "cadence_ms" => 1000
        },
        extra
      )

    assert {:ok, rule} = Rule.validate(input)
    rule
  end

  defp samples(value), do: [%{"metric" => %{"service" => "api"}, "value" => [0, to_string(value)]}]

  test "native LogQL thresholds are closed, metric-producing and disabled by default" do
    validated = rule()
    assert validated["enabled"] == false
    assert validated["no_data_policy"] == "keep_last"
    assert rule(%{"query" => ~s'rate_counter({service="api"} | unwrap n [1m])'})["enabled"] == false

    for change <- [
          %{"query" => ~s'{service="api"}'},
          %{"query" => ~s'rate_counter({service="api"}[1m])'},
          %{"query" => String.duplicate("1", 16_385)},
          %{"no_data_policy" => "alerting"},
          %{"base_url" => "https://not-contacted.invalid"},
          %{"threshold" => %{"op" => "gte", "value" => 0}}
        ] do
      assert {:error, :invalid_rule} = Rule.validate(Map.merge(validated, change))
    end
  end

  test "default empty-result policy preserves firing and pending state and exposes no-data" do
    for for_ms <- [0, 1000] do
      rule = rule(%{"for_ms" => for_ms})
      assert {:ok, prior, _, "ok"} = Lifecycle.step(rule, %{}, samples(1), 1_000_000_000)
      assert {:ok, ^prior, [], "no_data"} = Lifecycle.step(rule, prior, [], 10_000_000_000)
    end
  end

  test "explicit OK on empty results honors the durable hold and re-trigger state" do
    rule = rule(%{"no_data_policy" => "ok", "keep_firing_ms" => 1000})
    assert {:ok, firing, _, "ok"} = Lifecycle.step(rule, %{}, samples(1), 1_000_000_000)
    assert {:ok, recovering, [%{"type" => "recovering"}], "no_data"} = Lifecycle.step(rule, firing, [], 2_000_000_000)
    assert [%{"hold_until_ns" => "3000000000"}] = Map.values(recovering)

    assert {:ok, retriggered, [%{"type" => "retriggered"}], "ok"} =
             Lifecycle.step(rule, recovering, samples(1), 2_500_000_000)

    assert [%{"status" => "firing", "firing_since_ns" => "1000000000", "hold_until_ns" => nil}] =
             Map.values(retriggered)

    assert {:ok, %{}, [%{"type" => "resolved"}], "no_data"} = Lifecycle.step(rule, recovering, [], 3_000_000_000)
  end

  test "explicit OK on empty cancels pending; NaN is an evaluation error, never emptiness" do
    rule = rule(%{"no_data_policy" => "ok", "for_ms" => 1000})
    assert {:ok, pending, _, "ok"} = Lifecycle.step(rule, %{}, samples(1), 1_000_000_000)
    assert {:error, :invalid_evaluation} = Lifecycle.step(rule, pending, samples("NaN"), 2_000_000_000)
    assert {:ok, %{}, [%{"type" => "resolved"}], "no_data"} = Lifecycle.step(rule, pending, [], 2_000_000_000)
    promql = Map.merge(rule, %{"kind" => "promql_threshold", "query" => "up"})
    assert {:ok, validated} = Rule.validate(promql)
    assert validated["no_data_policy"] == "ok"
  end
end
