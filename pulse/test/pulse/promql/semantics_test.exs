defmodule Pulse.PromQL.SemanticsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Parser
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.Memory

  setup do
    Memory.reset()
    :ok
  end

  defp append(name, labels, points) do
    records =
      Enum.map(points, fn {second, value} ->
        %MetricSample{timestamp_ns: second * 1_000_000_000, value: value, labels: Map.put(labels, "__name__", name)}
      end)

    :ok = Memory.append(:metrics, "semantics", records, [])
  end

  defp query(expr, time \\ 30), do: Evaluator.query(expr, "semantics", %{end_ts_ns: time * 1_000_000_000})

  defp entries(expr, time \\ 30) do
    assert {:ok, result} = query(expr, time)
    result["data"]["result"]
  end

  defp numbers(expr, time \\ 30), do: Enum.map(entries(expr, time), &Enum.at(&1["value"], 1))

  test "arithmetic, unary signs, and right-associative power have Prometheus precedence" do
    for {expr, expected} <- [
          {"vector(2 + 3 * 4)", "14"},
          {"vector(2 ^ 3 ^ 2)", "512"},
          {"vector(-2 ^ 2)", "-4"},
          {"vector(2 ^ -2)", "0.25"},
          {"vector(5 % 3)", "2"}
        ] do
      assert numbers(expr) == [expected]
    end

    assert {:ok, result} = query("time()")
    assert result["data"] == %{"resultType" => "scalar", "result" => [30.0, "30"]}
  end

  test "NaN and infinities have IEEE arithmetic and comparison semantics" do
    for {expr, expected} <- [
          {"vector(0 / 0)", "NaN"},
          {"vector(1 / 0)", "+Inf"},
          {"vector(-1 / 0)", "-Inf"},
          {"vector(Inf - Inf)", "NaN"},
          {"vector(NaN != bool NaN)", "1"},
          {"vector(NaN == bool NaN)", "0"},
          {"vector(0 * Inf)", "NaN"},
          {"vector(1 / Inf)", "0"}
        ] do
      assert numbers(expr) == [expected]
    end

    append("special", %{}, [{30, :nan}])
    assert numbers("special") == ["NaN"]
    assert numbers("sum(special)") == ["NaN"]
    assert numbers("clamp_min(special, 1)") == ["NaN"]
    assert numbers("clamp_min(vector(-0), 0)") == ["0"]
    assert numbers("clamp_max(vector(0), -0)") == ["-0"]
  end

  test "clamp preserves IEEE bounds, zero signs and duplicate-label checks" do
    for {expr, expected} <- [
          {"clamp(vector(-Inf), -2, 7)", "-2"},
          {"clamp(vector(Inf), -2, 7)", "7"},
          {"clamp(vector(NaN), -2, 7)", "NaN"},
          {"clamp(vector(-2), -2, 7)", "-2"},
          {"clamp(vector(7), -2, 7)", "7"},
          {"clamp(vector(0), -0, -0)", "-0"},
          {"clamp(vector(-0), 0, 0)", "0"},
          {"clamp(vector(-0), -0, 0)", "-0"},
          {"clamp(vector(0), -0, 0)", "0"},
          {"clamp(vector(-0), 0, -0)", "0"},
          {"clamp(vector(0), -Inf, Inf)", "0"},
          {"clamp(vector(-0), -Inf, Inf)", "-0"},
          {"1 / clamp(vector(-0), 0, -0)", "+Inf"},
          {"clamp(vector(2), Inf, Inf)", "+Inf"},
          {"clamp(vector(2), -Inf, -Inf)", "-Inf"},
          {"clamp(vector(Inf), NaN, -Inf)", "NaN"},
          {"clamp(vector(-Inf), Inf, NaN)", "NaN"}
        ] do
      assert numbers(expr) == [expected], expr
    end

    assert entries("clamp(vector(NaN), 7, -2)") == []
    assert entries("clamp(vector(0), Inf, -Inf)") == []
    assert entries("clamp(missing, -2, 7)") == []

    append("a", %{"job" => "api"}, [{30, 3.0}])
    append("b", %{"job" => "api"}, [{30, 6.0}])
    assert {:error, :duplicate_result_label_sets} = query(~s|clamp({__name__=~"a\|b"}, -2, 7)|)
    assert entries(~s|clamp({__name__=~"a\|b"}, 7, -2)|) == []
  end

  test "basic math preserves IEEE domains, signed zeros and exponential limits" do
    for {expr, expected} <- [
          {"ceil(vector(-1.5))", "-1"},
          {"ceil(vector(1.5))", "2"},
          {"ceil(vector(-0.5))", "-0"},
          {"sqrt(vector(4))", "2"},
          {"sqrt(vector(-1))", "NaN"},
          {"sqrt(vector(-Inf))", "NaN"},
          {"sqrt(vector(Inf))", "+Inf"},
          {"sqrt(vector(-0))", "-0"},
          {"exp(vector(0))", "1"},
          {"exp(vector(-Inf))", "0"},
          {"exp(vector(Inf))", "+Inf"},
          {"exp(vector(710))", "+Inf"},
          {"exp(vector(-1000))", "0"},
          {"exp(vector(-745))", "0"},
          {"exp(vector(-745.1332191019411)) == bool 0", "1"},
          {"exp(vector(-744.8)) == bool 0", "1"},
          {"exp(vector(-744.7)) == bool 0", "0"},
          {"ln(vector(1))", "0"},
          {"log2(vector(8))", "3"},
          {"log2(vector(1.0000000000000002)) > bool 3.5e-16", "1"},
          {"log10(vector(100))", "2"},
          {"log2(vector(5e-324))", "-1074"},
          {"1 / ceil(vector(-0.5))", "-Inf"},
          {"1 / sqrt(vector(-0))", "-Inf"}
        ] do
      assert numbers(expr) == [expected], expr
    end

    for name <- ~w(ceil sqrt exp ln log2 log10) do
      assert numbers("#{name}(vector(NaN))") == ["NaN"]
      assert entries("#{name}(missing)") == []
    end

    for name <- ~w(ln log2 log10) do
      assert numbers("#{name}(vector(Inf))") == ["+Inf"]
      assert numbers("#{name}(vector(-Inf))") == ["NaN"]
      assert numbers("#{name}(vector(-1))") == ["NaN"]
      assert numbers("#{name}(vector(0))") == ["-Inf"]
      assert numbers("#{name}(vector(-0))") == ["-Inf"]
    end
  end

  test "instant selectors stop at stale markers and resume only after a fresh sample" do
    append("up", %{}, [{0, 1.0}, {20, :stale}, {40, 2.0}])
    assert numbers("up", 19) == ["1"]
    assert entries("up", 20) == []
    assert entries("up", 39) == []
    assert numbers("up", 40) == ["2"]
    # Range functions ignore stale markers, not the finite history around them.
    assert numbers("count_over_time(up[1m])", 30) == ["1"]
    assert numbers("count_over_time(up[1m])", 40) == ["2"]
    assert numbers("up offset 20s", 30) == ["1"]
  end

  test "staleness wins conflicting same-timestamp deliveries independently of ordering" do
    append("up", %{}, [{30, 2.0}, {30, :stale}, {30, 1.0}])
    assert {:ok, result} = query("up")
    assert result["data"]["result"] == []
    assert [_] = result["warnings"]
  end

  test "default matching excludes names and treats missing labels as empty" do
    append("a", %{"job" => "api", "optional" => ""}, [{30, 6.0}])
    append("b", %{"job" => "api"}, [{30, 2.0}])
    assert numbers("a / b") == ["3"]
    assert [%{"metric" => %{"job" => "api", "optional" => ""}}] = entries("a / b")
    assert numbers("a > b") == ["6"]
    assert hd(entries("a > b"))["metric"]["__name__"] == "a"
    assert hd(entries("a > bool b"))["metric"]["__name__"] == nil
  end

  test "many-to-one and one-to-many matching preserve labels and reject ambiguous matches" do
    append("a", %{"job" => "api", "instance" => "one"}, [{30, 6.0}])
    append("a", %{"job" => "api", "instance" => "two"}, [{30, 8.0}])
    append("b", %{"job" => "api", "region" => "eu"}, [{30, 2.0}])
    assert numbers("a / on(job) group_left(region) b") == ["3", "4"]
    assert Enum.all?(entries("a / on(job) group_left(region) b"), &(&1["metric"]["region"] == "eu"))
    assert numbers("b < on(job) group_right(region) a") == ["2", "2"]
    assert Enum.all?(entries("b < on(job) group_right(region) a"), &(&1["metric"]["__name__"] == "a"))
    assert {:error, :many_to_many_matching} = query("a / on(job) b")
    append("b", %{"job" => "api", "region" => "us"}, [{30, 4.0}])
    assert {:error, :many_to_many_matching} = query("a / on(job) group_left b")
    assert {:error, :many_to_many_matching} = query("a / on(job) group_right b")

    # Both indexed-side contexts stay private to matching: PromQL's ordinary
    # and batched public evaluators retain the same historical atom.
    for expression <- ["a / on(job) group_left b", "a / on(job) group_right b"] do
      assert {:error, :many_to_many_matching} =
               Evaluator.query_batch(
                 [{"ambiguous", expression, %{end_ts_ns: 30_000_000_000}}],
                 "semantics",
                 fn results, _deadline -> {:ok, results} end
               )
    end
  end

  test "cardinality checks follow pinned Mimir before comparison filtering" do
    append("a", %{"job" => "api", "instance" => "one"}, [{30, 6.0}])
    append("a", %{"job" => "api", "instance" => "two"}, [{30, 8.0}])
    # Prometheus 3.5.0 accepted zero/one surviving matches; PR 17668 fixed this
    # before the Prometheus fork revision used by the pinned Mimir corpus.
    assert {:error, :many_to_many_matching} = query("a > ignoring(job,instance) sum(a)")
    assert {:error, :many_to_many_matching} = query("a < ignoring(job,instance) max(a)")
    assert {:error, :many_to_many_matching} = query("a < ignoring(job,instance) sum(a)")
    append("b", %{"job" => "web"}, [{30, 2.0}])
    assert {:error, :many_to_many_matching} = query("b + on(job) a")
    assert entries(~s|b{job="missing"} + on(job) a|) == []
  end

  test "many-to-many set operators retain the original label sets and values" do
    append("a", %{"job" => "api", "instance" => "one"}, [{30, 6.0}])
    append("a", %{"job" => "api", "instance" => "two"}, [{30, 8.0}])
    append("b", %{"job" => "api", "region" => "eu"}, [{30, 2.0}])
    append("b", %{"job" => "web", "region" => "us"}, [{30, 4.0}])
    assert length(entries("a and on(job) b")) == 2
    assert entries("a unless on(job) b") == []
    assert length(entries("a or on(job) b")) == 3
  end

  test "duplicate output labels are explicit errors rather than duplicate samples" do
    append("a", %{"job" => "api", "instance" => "one"}, [{30, 6.0}])
    append("a", %{"job" => "api", "instance" => "two"}, [{30, 8.0}])
    assert {:error, :duplicate_result_label_sets} = query(~s|label_replace(a, "instance", "", "instance", ".*")|)
  end

  test "label replacement uses Go captures, leaves nonmatches alone, and removes empty replacements" do
    append("a", %{"job" => "api-12"}, [{30, 1.0}])

    assert hd(entries(~s|label_replace(a, "service", "${1}/$2/$$/$missing", "job", "(.*)-([0-9]+)")|))["metric"][
             "service"
           ] == "api/12/$/"

    assert hd(entries(~s|label_replace(a, "job", "", "job", "nomatch")|))["metric"]["job"] == "api-12"
    assert hd(entries(~s|label_replace(a, "job", "", "job", ".*")|))["metric"]["job"] == nil
  end

  test "topk and sort have numeric ordering instead of label ordering" do
    append("a", %{"job" => "a"}, [{30, 1.0}])
    append("a", %{"job" => "b"}, [{30, 9.0}])
    append("a", %{"job" => "c"}, [{30, :nan}])
    assert numbers("topk(2,a)") == ["9", "1"]
    assert numbers("bottomk(2,a)") == ["1", "9"]
    assert numbers("sort_desc(a)") == ["9", "1", "NaN"]
    assert numbers("sort(a)") == ["1", "9", "NaN"]
  end

  test "classic histograms require +Inf, coalesce duplicate boundaries, and repair monotonic counts" do
    for {le, value} <- [{"1", 5.0}, {"2", 4.0}, {"+Inf", 10.0}] do
      append("bucket", %{"le" => le}, [{30, value}])
    end

    assert numbers("histogram_quantile(0.5,bucket)") == ["1"]
    assert numbers("histogram_quantile(0.9,bucket)") == ["2"]
    assert numbers("histogram_quantile(0.5,bucket{le!=\"+Inf\"})") == ["NaN"]
  end

  test "review regressions preserve comparison metric names and ranking errors" do
    append("a", %{"job" => "api", "instance" => "one"}, [{30, 6.0}])
    append("a", %{"job" => "api", "instance" => "two"}, [{30, 8.0}])
    append("b", %{"job" => "api"}, [{30, 2.0}])
    assert Enum.all?(entries("a > on(job) group_left b"), &(&1["metric"]["__name__"] == "a"))
    assert Enum.all?(entries("a == on(__name__,job,instance) a"), &(&1["metric"]["__name__"] == "a"))

    for op <- ["topk", "bottomk"], k <- ["NaN", "scalar(a)"] do
      assert {:error, {:invalid_ranking_parameter, ^op, :nan}} = query("#{op}(#{k}, a)")
    end

    for k <- ["Inf", "1e30"] do
      assert {:error, :invalid_aggregation_parameter} = query("topk(#{k}, a)")
      assert {:error, :invalid_aggregation_parameter} = query("bottomk(#{k}, a)")
    end
  end

  test "negative ranking parameters produce an empty vector even below int64 bounds" do
    append("a", %{}, [{30, 1.0}])

    for k <- ["-Inf", "-1e30", "-1", "0.5"] do
      assert entries("topk(#{k}, a)") == []
      assert entries("bottomk(#{k}, a)") == []
    end
  end

  test "histograms with different metric names cannot be silently combined" do
    for {name, values} <- [{"x_bucket", [1.0, 2.0]}, {"y_bucket", [3.0, 4.0]}],
        {le, value} <- Enum.zip(["1", "+Inf"], values),
        do: append(name, %{"le" => le, "job" => "api"}, [{30, value}])

    assert {:error, :duplicate_result_label_sets} = query(~s/histogram_quantile(0.5,{__name__=~"x_bucket|y_bucket"})/)
    # Combining the histogram inputs is valid when explicitly requested.
    assert numbers(~s/histogram_quantile(0.5,sum by(le,job)({__name__=~"x_bucket|y_bucket"}))/) == ["0.75"]
  end

  test "compensated sums and averages survive catastrophic cancellation and overflow" do
    append("k", %{"i" => "one"}, [{30, 1.0e100}])
    append("k", %{"i" => "two"}, [{30, 1.0}])
    append("k", %{"i" => "three"}, [{30, -1.0e100}])
    append("o", %{}, [{10, 1.0e100}, {20, 1.0}, {30, -1.0e100}])
    assert numbers("sum(k)") == ["1"]
    assert numbers("avg(k)") == ["0.3333333333333333"]
    assert numbers("sum_over_time(o[1m])") == ["1"]
    assert numbers("avg_over_time(o[1m])") == ["0.3333333333333333"]
    append("large", %{}, [{10, 1.0e308}, {20, 1.0e308}])
    assert numbers("avg_over_time(large[1m])") == ["1e+308"]
  end

  test "histogram boundaries accept Go float spelling and IEEE counts remain group-local" do
    for {name, buckets, expected} <- [
          {"decimal", [{".5", 5.0}, {"1", 8.0}, {"+Inf", 10.0}], "0.3"},
          {"lower", [{"0.5", 5.0}, {"inf", 10.0}], "0.3"},
          {"hex", [{"0x1p1", 5.0}, {"Infinity", 10.0}], "1.2"},
          {"bad_first", [{"1", :nan}, {"2", 5.0}, {"+Inf", 10.0}], "NaN"},
          {"bad_last", [{"1", 5.0}, {"+Inf", :nan}], "1"},
          {"inf_last", [{"1", 3.0}, {"+Inf", :infinity}], "1"}
        ] do
      for {le, count} <- buckets, do: append(name, %{"le" => le}, [{30, count}])
      assert numbers("histogram_quantile(0.3, #{name})") == [expected]
    end
  end

  test "scalar literals accept hexadecimal, separators, and lowercase IEEE names" do
    for {literal, expected} <- [
          {"0x10", "16"},
          {"1_000", "1000"},
          {"1e1_0", "10000000000"},
          {"inf", "+Inf"},
          {"nan", "NaN"}
        ] do
      assert numbers("vector(#{literal})") == [expected]
    end
  end

  test "sample and work budgets apply across multiple expression inputs" do
    append("a", %{}, [{30, 1.0}])
    append("b", %{}, [{30, 2.0}])
    Pulse.Runtime.put_env(:pulse, Evaluator, max_samples: 1)
    assert {:error, :query_sample_limit} = query("a + b")
    assert {:error, :query_sample_limit} = query("clamp(a, scalar(b), -1)")
    Pulse.Runtime.put_env(:pulse, Evaluator, max_work: 3)
    assert {:error, :query_work_limit} = query("a + b")
    assert {:error, :query_work_limit} = query("clamp(a, scalar(b), -1)")
  end

  test "invalid operand types, matching modifiers, and excessive expression depth are rejected" do
    for expr <- [
          "sum(1)",
          "1 == 1",
          "a and 1",
          "a + bool b",
          "a + on(job) 1",
          "a and on(job) group_left b",
          "a + on(job) group_left(job) b",
          "histogram_quantile(a,b)",
          "label_replace(a,1,2,3,4)",
          "unknown(a)"
        ] do
      assert {:error, _} = Parser.parse(expr), expr
    end

    assert {:error, :query_expression_limit} = Parser.parse(Enum.map_join(1..130, "+", fn _ -> "a" end))
  end
end
