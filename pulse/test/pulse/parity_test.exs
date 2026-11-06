defmodule Pulse.ParityTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Parity

  defp matrix(series),
    do: %{
      "status" => "success",
      "data" => %{
        "resultType" => "matrix",
        "result" => Enum.map(series, fn {labels, values} -> %{"metric" => labels, "values" => values} end)
      }
    }

  describe "extract/3" do
    test "reads dashboard targets, including nested rows, with their datasource language" do
      dashboard = %{
        "dashboard" => %{
          "panels" => [
            %{"title" => "Rate", "targets" => [%{"expr" => "rate(x[5m])", "datasource" => %{"type" => "prometheus"}}]},
            %{
              "title" => "Row",
              "panels" => [
                %{
                  "title" => "Logs",
                  "datasource" => %{"uid" => "logs"},
                  "targets" => [%{"expr" => ~s({app="a"}), "instant" => true}]
                }
              ]
            },
            %{"title" => "Text"}
          ]
        }
      }

      assert [
               %{expr: "rate(x[5m])", language: :promql, kind: :range, source: "d.json: Rate"},
               %{expr: ~s({app="a"}), language: :logql, kind: :instant, source: "d.json: Logs"}
             ] = Parity.extract(dashboard, "d.json", %{"logs" => "loki"})

      assert Parity.extract(%{"kind" => "Dashboard", "spec" => dashboard["dashboard"]}, "d.json", %{"logs" => "loki"}) ==
               Parity.extract(dashboard, "d.json", %{"logs" => "loki"})
    end

    test "reads Git Sync v2 panels without treating Tempo or SQL as PromQL" do
      panel = fn group, expression, instant ->
        %{
          "kind" => "Panel",
          "spec" => %{
            "title" => group,
            "data" => %{
              "spec" => %{
                "queries" => [
                  %{
                    "spec" => %{"query" => %{"group" => group, "spec" => %{"expr" => expression, "instant" => instant}}}
                  }
                ]
              }
            }
          }
        }
      end

      dashboard = %{
        "kind" => "Dashboard",
        "spec" => %{
          "elements" => %{
            "a" => panel.("loki", ~s({app="api"}), true),
            "b" => panel.("prometheus", "up", false),
            "c" => panel.("tempo", "{}", false),
            "d" => panel.("postgres", "select 1", false)
          }
        }
      }

      assert [
               %{expr: ~s({app="api"}), language: :logql, kind: :instant},
               %{expr: "up", language: :promql, kind: :range}
             ] = Parity.extract(dashboard, "v2.json")
    end

    test "keeps both execution modes in a query corpus" do
      corpus = %{
        "queries" => [
          %{"id" => "p1", "expr" => "up", "language" => "promql", "modes" => "ir"},
          %{"id" => "l1", "expr" => ~s({app="api"}), "language" => "logql", "modes" => "i"}
        ]
      }

      assert [
               %{expr: "up", language: :promql, kind: :instant},
               %{expr: "up", language: :promql, kind: :range},
               %{expr: ~s({app="api"}), language: :logql, kind: :instant}
             ] = Parity.extract(corpus, "corpus.json")
    end

    test "reads alert rule queries, skipping expressions, and plain query lists" do
      rules = %{
        "rules" => [
          %{
            "title" => "High",
            "data" => [
              %{
                "refId" => "A",
                "datasourceUid" => "logs",
                "model" => %{"expr" => ~s<sum(count_over_time({a="b"} |= "x" [5m]))>}
              },
              %{"refId" => "B", "datasourceUid" => "__expr__", "model" => %{"type" => "math", "expression" => "$A > 1"}}
            ]
          }
        ]
      }

      assert [%{language: :logql, kind: :instant, source: "r.json: High (A)"}] = Parity.extract(rules, "r.json", %{})

      plain = [%{"expr" => "up", "kind" => "instant", "tolerance" => 0.01}, %{"expr" => ~s({a="b"} | json)}]

      assert [%{language: :promql, kind: :instant, tolerance: 0.01}, %{language: :logql, kind: :range}] =
               Parity.extract(plain, "q.json", %{})
    end
  end

  test "substitutes Grafana's built-in and named variables, and matches unset ones broadly" do
    expr =
      ~S|sum by (pod) (rate(http{env="$env", pod=~"$pod"}[$__rate_interval])) / $__range_s * $__interval_ms + count_over_time(x[$__interval])|

    assert Parity.substitute(expr, 30, 3600, %{"env" => "prod"}) ==
             ~S|sum by (pod) (rate(http{env="prod", pod=~".+"}[60s])) / 3600 * 30000 + count_over_time(x[30s])|
  end

  test "bounds are step-aligned, leave the lag out and hold about 300 points" do
    assert {start, finish, 15} = Parity.bounds(1_000_000, 3600, 300)
    assert rem(finish, 15) == 0 and finish <= 1_000_000 - 300 and finish - start == 3600
    assert {_, _, 2016} = Parity.bounds(1_000_000, 7 * 86_400, 0)
  end

  test "uses the configured scrape interval on both sides of Grafana's rate-window boundary" do
    assert Parity.substitute("rate(x[$__rate_interval])", 30, 3600, %{}, 60) == "rate(x[240s])"
    assert Parity.substitute("rate(x[$__rate_interval])", 300, 3600, %{}, 60) == "rate(x[360s])"
    assert Parity.substitute("rate(x[$__auto])", 90, 3600, %{}, 60) == "rate(x[90s])"
  end

  @tag :tmp_dir
  test "the command fails closed on an unsupported or empty input instead of reporting parity", %{tmp_dir: directory} do
    file = Path.join(directory, "empty.json")
    File.write!(file, ~s({"unsupported":[]}))

    assert_raise Mix.Error, ~r/No PromQL or LogQL queries extracted/, fn ->
      Mix.Tasks.Pulse.Parity.run([file])
    end
  end

  describe "compare/3" do
    test "matches equal series within the relative tolerance, NaN included" do
      a = Parity.normalize(matrix([{%{"a" => "1"}, [[1, "1.0"], [2, "NaN"]]}]))
      b = Parity.normalize(matrix([{%{"a" => "1"}, [[1, "1.0000000000001"], [2, "NaN"]]}]))
      {:ok, a} = a
      {:ok, b} = b
      assert Parity.compare(a, b, 1.0e-9) == :match
    end

    test "reports missing, extra and differing series" do
      {:ok, a} = Parity.normalize(matrix([{%{"s" => "1"}, [[1, "1"]]}, {%{"s" => "2"}, [[1, "2"]]}]))
      {:ok, b} = Parity.normalize(matrix([{%{"s" => "1"}, [[1, "1.1"]]}, {%{"s" => "3"}, [[1, "3"]]}]))

      assert {:mismatch, details} = Parity.compare(a, b, 1.0e-9)
      assert details.only_in_reference == [%{"s" => "2"}]
      assert details.only_in_candidate == [%{"s" => "3"}]
      assert [%{labels: %{"s" => "1"}, first_difference: {{1.0, 1.0}, {1.0, 1.1}}}] = details.differing
    end

    test "log streams must hold the same entries" do
      streams = fn values ->
        %{
          "status" => "success",
          "data" => %{"resultType" => "streams", "result" => [%{"stream" => %{"app" => "a"}, "values" => values}]}
        }
      end

      {:ok, a} = Parity.normalize(streams.([["2", "b"], ["1", "a"]]))
      {:ok, b} = Parity.normalize(streams.([["1", "a"], ["2", "b"]]))
      {:ok, c} = Parity.normalize(streams.([["1", "a"]]))
      assert Parity.compare(a, b, 0.0) == :match
      assert {:mismatch, _} = Parity.compare(a, c, 0.0)
    end
  end

  test "run sends identical bounds to both sides and classifies failures" do
    query = %{expr: "up", language: :promql, kind: :range, source: "s", tolerance: nil}
    endpoints = %{{:reference, :promql} => {"ref", []}, {:candidate, :promql} => {"cand", []}}
    parent = self()

    fetch = fn {side, _}, :promql, request ->
      send(parent, {side, request})
      if side == "cand", do: {:error, "HTTP 422"}, else: Parity.normalize(matrix([]))
    end

    result = Parity.run(query, endpoints, 3600, now: 1_000_000, fetch: fetch)
    assert result.outcome == {:candidate_error, "HTTP 422"}
    assert_received {"ref", request}
    assert_received {"cand", ^request}
    assert Parity.summary([result, %{result | outcome: :match}]) == %{candidate_error: 1, match: 1}
  end
end
