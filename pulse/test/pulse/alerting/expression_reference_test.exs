defmodule Pulse.Alerting.ExpressionReferenceTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.Expressions

  @fixture Path.expand("../../fixtures/alerting/expression-math.json", __DIR__)

  test "bounded math matches pinned independent Grafana-parser/Go-IEEE cases" do
    fixture = Pulse.JSON.decode!(File.read!(@fixture))
    assert length(fixture["cases"]) == 968

    for item <- fixture["cases"] do
      sources = Enum.map(Map.keys(item["inputs"]), &%{"refId" => &1, "datasourceUid" => "test", "model" => %{}})

      expression = %{
        "refId" => "result",
        "datasourceUid" => "__expr__",
        "model" => %{"type" => "math", "expression" => item["expression"]}
      }

      graph = %{"data" => sources ++ [expression], "condition" => "result"}
      inputs = Map.new(item["inputs"], fn {ref, data} -> {ref, frames(data)} end)
      # Numerical conformance is not a one-second scheduler-latency test.
      # Dedicated expression tests cover expired deadlines; keep all work bounds.
      deadline = System.monotonic_time(:millisecond) + 30_000
      assert {:ok, result} = Expressions.execute(graph, inputs, deadline: deadline), item["name"]

      assert :erlang.term_to_binary(result.terminal, [:deterministic]) ==
               :erlang.term_to_binary(frames(item["expected"]), [:deterministic]),
             item["name"]

      drops = Enum.reduce(result.notices, 0, &(&1.dropped + &2))
      assert drops == item["drops"], item["name"]
    end
  end

  defp frames(%{"kind" => "scalar", "frames" => [frame]}), do: {:scalar, frame_value(frame)}

  defp frames(%{"kind" => "numbers", "frames" => frames}),
    do: {:numbers, Enum.map(frames, &%{labels: &1["labels"], value: frame_value(&1)})}

  defp frame_value(%{"int64" => text}), do: String.to_integer(text)
  defp frame_value(frame), do: value(frame["value"])

  defp value(nil), do: nil
  defp value("NaN"), do: :nan
  defp value("+Inf"), do: :infinity
  defp value("-Inf"), do: :negative_infinity

  defp value(text) do
    {float, ""} = Float.parse(text)
    float
  end
end
