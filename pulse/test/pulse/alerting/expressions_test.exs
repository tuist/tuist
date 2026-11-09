defmodule Pulse.Alerting.ExpressionsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.Expressions
  alias Pulse.Alerting.Expressions.Math

  defp source(ref), do: %{"refId" => ref, "datasourceUid" => "native", "model" => %{}}

  defp math(text),
    do: %{"refId" => "C", "datasourceUid" => "__expr__", "model" => %{"type" => "math", "expression" => text}}

  defp graph(text), do: %{"data" => [math(text), source("A"), source("B")], "condition" => "C"}
  # Results here must not depend on scheduler load; deadlines are tested
  # explicitly. Production callers always pass their own deadline.
  defp execute(graph, inputs, opts \\ []),
    do:
      Expressions.execute(graph, inputs, Keyword.put_new(opts, :deadline, System.monotonic_time(:millisecond) + 60_000))

  defp numbers(values), do: {:numbers, Enum.map(values, fn {labels, value} -> %{labels: labels, value: value} end)}

  test "math syntax is bounded and has Grafana rather than PromQL precedence" do
    for text <- ["$A > 2.5 && $B > 100", "${executions} >= ${threshold}", "$A - $B", "2**3**2", "-2**2", "1+2*3"] do
      assert {:ok, _, _, _} = Math.parse(text)
    end

    for text <- [
          "foo($A)",
          "$A and $B",
          "$A +",
          "$A; File.read!(\"secret\")",
          String.duplicate("(", 65) <> "$A" <> String.duplicate(")", 65),
          String.duplicate("1+", 256) <> "1"
        ] do
      assert {:error, :invalid_expression} = Math.parse(text)
    end

    for {text, expected} <- [{"2**3**2", 64.0}, {"-2**2", 4.0}, {"1+2*3", 7.0}] do
      assert {:ok, %{terminal: {:scalar, ^expected}}} =
               execute(graph(text), %{"A" => {:numbers, []}, "B" => {:numbers, []}})
    end
  end

  test "subset label union and label-free scalars broadcast without PromQL matching" do
    inputs = %{
      "A" =>
        numbers([
          {%{"region" => "eu", "pod" => "one"}, 8.0},
          {%{"region" => "eu", "pod" => "two"}, 12.0},
          {%{"region" => "us", "pod" => "three"}, 6.0}
        ]),
      "B" => numbers([{%{"region" => "eu"}, 2.0}])
    }

    assert {:ok, %{terminal: {:numbers, frames}, notices: [%{ref: "C", dropped: 1}]}} =
             execute(graph("$A / $B"), inputs)

    assert Enum.map(frames, &{&1.labels["pod"], &1.value}) == [{"one", 4.0}, {"two", 6.0}]
    assert {:ok, %{terminal: {:numbers, frames}}} = execute(graph("$A / 2"), inputs)
    assert Enum.map(frames, & &1.value) == [4.0, 6.0, 3.0]
  end

  test "single unmatched input on each side joins without labels and reports dropped input labels" do
    inputs = %{"A" => numbers([{%{"pod" => "one"}, 8.0}]), "B" => numbers([{%{"zone" => "two"}, 2.0}])}

    assert {:ok, %{terminal: {:numbers, [%{labels: %{}, value: 6.0}]}, notices: [%{dropped: 2}]}} =
             execute(graph("$A - $B"), inputs)
  end

  test "empty input sets remain empty and unknown/missing source inputs fail closed" do
    inputs = %{"A" => {:numbers, []}, "B" => numbers([{%{}, 1.0}])}
    assert {:ok, %{terminal: {:numbers, []}}} = execute(graph("$A && $B"), inputs)
    assert {:error, :invalid_expression_inputs} = execute(graph("$A && $B"), Map.delete(inputs, "B"))

    assert {:error, :invalid_expression_inputs} =
             execute(graph("$A && $B"), Map.put(inputs, "extra", {:scalar, 1.0}))
  end

  test "math NaN/null and short-circuit behavior are separate from threshold predicates" do
    for {op, a, b, expected} <- [
          {">", :nan, 1.0, :nan},
          {"!=", :nan, 1.0, :nan},
          {"&&", 0.0, :nan, 0.0},
          {"&&", :nan, 0.0, :nan},
          {"||", :nan, 0.0, 1.0},
          {"||", 0.0, :nan, :nan},
          {"||", 1.0, nil, nil},
          {"/", 1.0, -0.0, :negative_infinity}
        ] do
      assert {:ok, %{terminal: {:scalar, ^expected}}} =
               execute(graph("$A #{op} $B"), %{"A" => {:scalar, a}, "B" => {:scalar, b}})
    end

    threshold = %{
      "refId" => "C",
      "datasourceUid" => "__expr__",
      "model" => %{
        "type" => "threshold",
        "expression" => "A",
        "conditions" => [%{"evaluator" => %{"type" => "gt", "params" => [0]}, "reducer" => %{"type" => "avg"}}]
      }
    }

    rule = %{"data" => [source("A"), threshold], "condition" => "C"}

    assert {:ok, %{terminal: {:numbers, [%{value: +0.0}, %{value: nil}, %{value: 1.0}]}}} =
             execute(rule, %{"A" => numbers([{%{}, :nan}, {%{}, nil}, {%{}, :infinity}])})
  end

  test "last reduction ignores legacy reducer fields and retains last null/NaN semantics" do
    reduce = %{
      "refId" => "C",
      "datasourceUid" => "__expr__",
      "model" => %{
        "type" => "reduce",
        "expression" => "A",
        "reducer" => "last",
        "conditions" => [%{"reducer" => %{"type" => "avg"}}]
      }
    }

    rule = %{"data" => [source("A"), reduce], "condition" => "C"}

    inputs = %{
      "A" =>
        {:series,
         [
           %{labels: %{"pod" => "one"}, points: [{1, :nan}, {2, 10.0}]},
           %{labels: %{}, points: [{1, 2.0}, {2, nil}]},
           %{labels: %{}, points: []}
         ]}
    }

    assert {:ok, %{terminal: {:numbers, frames}}} = execute(rule, inputs)
    assert Enum.map(frames, & &1.value) == [10.0, nil, :nan]

    assert {:error, {:expression_node, "C", :unsupported_reduce_mode}} =
             Expressions.compile(
               put_in(rule, ["data"], [source("A"), put_in(reduce, ["model", "settings"], %{"mode" => "dropNN"})])
             )
  end

  test "raw series math, stale markers, unsafe frames and nonascending times fail explicitly" do
    for input <- [
          {:scalar, :stale},
          {:numbers, [%{labels: %{}, value: 1.0, secret: String.duplicate("x", 100)}]},
          {:series, [%{labels: %{}, points: [{2, 1.0}, {1, 1.0}]}]}
        ] do
      assert {:error, :expression_input_limit} =
               execute(graph("$A+1"), %{"A" => input, "B" => {:numbers, []}})
    end

    assert {:error, :unsupported_series_math} =
             execute(graph("$A+1"), %{
               "A" => {:series, [%{labels: %{}, points: [{1, 2.0}]}]},
               "B" => {:numbers, []}
             })

    assert {:error, :expression_timeout} =
             execute(graph("$A+1"), %{"A" => {:scalar, 1.0}, "B" => {:numbers, []}},
               deadline: System.monotonic_time(:millisecond) - 1
             )
  end

  test "Cartesian matches debit shared work/result budgets before returning any result" do
    frames = numbers(List.duplicate({%{}, 1.0}, 400))
    # Exercise work exhaustion independently of scheduler load; expired deadlines
    # are asserted separately above. Production's default deadline is unchanged.
    assert {:error, :expression_work_limit} =
             execute(graph("$A + $B"), %{"A" => frames, "B" => frames},
               deadline: System.monotonic_time(:millisecond) + 30_000
             )
  end

  test "Grafana integer inputs and threshold params normalize to float64 before calculation" do
    inputs = %{"A" => {:scalar, 9_007_199_254_740_993}, "B" => {:scalar, 9_007_199_254_740_992}}
    assert {:ok, %{terminal: {:scalar, +0.0}}} = execute(graph("$A - $B"), inputs)
    assert {:ok, %{terminal: {:scalar, +0.0}}} = execute(graph("$A > $B"), inputs)

    threshold = %{
      "refId" => "C",
      "datasourceUid" => "__expr__",
      "model" => %{
        "type" => "threshold",
        "expression" => "A",
        "conditions" => [%{"evaluator" => %{"type" => "gt", "params" => [9_007_199_254_740_992]}}]
      }
    }

    rule = %{"data" => [source("A"), threshold], "condition" => "C"}
    assert {:ok, %{terminal: {:scalar, +0.0}}} = execute(rule, Map.take(inputs, ["A"]))
  end

  test "malformed optional record metadata uses the graph validator's alert terminal; malformed conditions never crash" do
    for record <- [%{}, "invalid", 4, true, []] do
      assert {:ok, %{terminal: {:scalar, 2.0}}} =
               execute(Map.put(graph("2"), "record", record), %{
                 "A" => {:numbers, []},
                 "B" => {:numbers, []}
               })
    end

    for condition <- [nil, false, "invalid", 123, []] do
      node = %{
        "refId" => "C",
        "datasourceUid" => "__expr__",
        "model" => %{"type" => "threshold", "expression" => "A", "conditions" => [condition]}
      }

      assert {:error, _} = Expressions.compile(%{"data" => [source("A"), node], "condition" => "C"})
    end

    for opts <- [nil, %{}, [deadline: nil], [deadline: "forever"], [:unexpected], [bogus: true]] do
      assert {:error, _} = Expressions.execute(graph("1"), %{"A" => {:numbers, []}, "B" => {:numbers, []}}, opts)
    end
  end

  test "all inventoried expression models compile without enabling their source graphs" do
    snapshot = Pulse.JSON.decode!(File.read!("plans/alerting/grafana-rule-inventory.json"))

    for rule <- snapshot["rules"] do
      assert {:ok, _} = Expressions.compile(rule)
    end
  end
end
