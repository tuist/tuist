defmodule Pulse.Traces.MetricsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Traces.Metrics

  @s 1_000_000_000

  setup do
    tenant = "trace-metrics-#{System.unique_integer([:positive])}"
    trace = "0af7651916cd43dd8448eb211c80319c"

    span = fn id, parent, start_s, duration_ms, status, route ->
      %{
        "traceId" => trace,
        "spanId" => id,
        "parentSpanId" => parent,
        "name" => "GET #{route}",
        "kind" => 2,
        "startTimeUnixNano" => Integer.to_string(start_s * @s),
        "endTimeUnixNano" => Integer.to_string(start_s * @s + duration_ms * 1_000_000),
        "attributes" => [%{"key" => "http.route", "value" => %{"stringValue" => route}}],
        "status" => %{"code" => status}
      }
    end

    resource = fn service, spans ->
      %{
        "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => service}}]},
        "scopeSpans" => [%{"scope" => %{"name" => "test"}, "spans" => spans}]
      }
    end

    payload = %{
      "resourceSpans" => [
        resource.("api", [
          span.("00f067aa0ba902b7", "", 1001, 100, 1, "/a"),
          span.("00f067aa0ba902b8", "00f067aa0ba902b7", 1002, 300, 2, "/b")
        ]),
        resource.("web", [
          span.("00f067aa0ba902b9", "", 1015, 2000, 0, "/a"),
          span.("00f067aa0ba902ba", "", 1100, 10, 0, "/a")
        ])
      ]
    }

    {:ok, spans, 0} = Traces.decode(payload)
    :ok = Storage.append(:traces, tenant, spans)
    {:ok, tenant: tenant}
  end

  defp range(ctx, query) do
    {:ok, json} = Metrics.query(ctx.tenant, query, {1000 * @s, 1060 * @s, 10 * @s}, false)
    json |> Pulse.JSON.decode!() |> Map.fetch!("series") |> Map.new(&{labels(&1), points(&1)})
  end

  defp labels(series),
    do: Map.new(series["labels"], fn %{"key" => k, "value" => v} -> {k, v |> Map.values() |> hd()} end)

  defp points(series), do: Map.new(series["samples"], &{div(String.to_integer(&1["timestampMs"]), 1000), &1["value"]})

  defp zeros(overrides), do: Map.merge(Map.new(1000..1060//10, &{&1, 0}), overrides)

  test "legacy spans cannot invent original attribute groupings or silently omit values" do
    {:ok, spans} = Storage.query(:traces, ctx().tenant, [])
    span = Enum.min_by(spans, & &1.timestamp_ns)
    tenant = ctx().tenant <> "-legacy"
    assert :ok = Storage.append(:traces, tenant, [%{span | otlp: nil}])
    window = {1000 * @s, 1060 * @s, 10 * @s}

    for query <- [
          "{} | count_over_time() by (resource.service.name)",
          "{} | avg_over_time(span.x)",
          ~s'{resource.service.name="api"} | count_over_time()'
        ] do
      assert {:error, :trace_metadata_unknown} = Metrics.query(tenant, query, window, false)
    end

    assert {:ok, json} = Metrics.query(tenant, "{} | count_over_time() by (name)", window, false)
    assert [_] = Pulse.JSON.decode!(json)["series"]

    assert {:ok, json} = Metrics.query(tenant, "{} | count_over_time() by (span:id)", window, false)

    assert [%{"labels" => [%{"key" => "span:id", "value" => %{"stringValue" => "00f067aa0ba902b7"}}]}] =
             Pulse.JSON.decode!(json)["series"]
  end

  test "span-ID grouping fails whole above the series ceiling rather than truncating" do
    {:ok, stored} = Storage.query(:traces, ctx().tenant, [])
    span = Enum.min_by(stored, & &1.timestamp_ns)
    tenant = ctx().tenant <> "-series-limit"

    spans =
      for id <- 1..10_000 do
        %{span | span_id: Base.encode16(<<id::64>>, case: :lower)}
      end

    assert :ok = Storage.append(:traces, tenant, spans)
    window = {1000 * @s, 1060 * @s, nil}
    assert {:ok, json} = Metrics.query(tenant, "{} | count_over_time() by (span:id)", window, true)
    assert length(Pulse.JSON.decode!(json)["series"]) == 10_000

    assert :ok = Storage.append(:traces, tenant, [%{span | span_id: "0000000000002711"}])
    assert {:ok, json} = Metrics.query(tenant, "{} | count_over_time()", window, true)
    assert [%{"value" => 10_001}] = Pulse.JSON.decode!(json)["series"]
    assert {:error, :trace_group_limit} = Metrics.query(tenant, "{} | count_over_time() by (span:id)", window, true)
  end

  @tag :trace_math_batch
  test "metric branches share the series ceiling before the final arithmetic" do
    {:ok, stored} = Storage.query(:traces, ctx().tenant, [])
    span = Enum.min_by(stored, & &1.timestamp_ns)
    tenant = ctx().tenant <> "-expression-limit"
    spans = for id <- 1..5000, do: %{span | span_id: Base.encode16(<<id::64>>, case: :lower)}
    assert :ok = Storage.append(:traces, tenant, spans)
    window = {1000 * @s, 1060 * @s, nil}
    query = "({} | count_over_time() by (span:id)) + ({} | sum_over_time(duration) by (span:id))"

    assert {:ok, json} = Metrics.query(tenant, query, window, true)
    series = Pulse.JSON.decode!(json)["series"]
    assert length(series) == 5000
    assert Enum.all?(series, &(abs(&1["value"] - 1.1) < 1.0e-12))

    filtered =
      "({} | count_over_time() by (span:id) > 10000 | topk(1)) + " <>
        "({} | sum_over_time(duration) by (span:id) > 10000 | bottomk(1))"

    assert {:ok, json} = Metrics.query(tenant, filtered, window, true)
    assert Pulse.JSON.decode!(json) == %{"series" => []}

    assert :ok = Storage.append(:traces, tenant, [%{span | span_id: "0000000000001389"}])
    assert {:error, :trace_group_limit} = Metrics.query(tenant, query, window, true)
    assert {:error, :trace_group_limit} = Metrics.query(tenant, filtered, window, true)
  end

  test "negative, noninteger and overflowing windows reject before native decoding" do
    for instant <- [true, false], window <- [{-1, @s, @s}, {0.5, @s, @s}, {0, 9_223_372_036_854_775_808, @s}] do
      assert {:error, :unsupported_parameters} = Metrics.window(window, instant)
    end

    assert {:error, :unsupported_parameters} = Metrics.window({0, @s, 0}, false)
    assert {:error, :unsupported_parameters} = Metrics.window({0, @s, -1}, false)
  end

  test "rate and count_over_time fill every aligned interval, keyed by span start" do
    assert range(ctx(), "{} | rate()") == %{%{"__name__" => "rate"} => zeros(%{1010 => 0.2, 1020 => 0.1})}

    assert range(ctx(), ~s'{resource.service.name="api"} | count_over_time() by (span.http.route)') == %{
             %{"span.http.route" => "/a"} => zeros(%{1010 => 1}),
             %{"span.http.route" => "/b"} => zeros(%{1010 => 1})
           }
  end

  test "empty ungrouped counts and rates return zeros without inventing grouped or numeric observations" do
    empty = %{ctx() | tenant: ctx().tenant <> "-empty"}
    window = {1000 * @s, 1060 * @s, 10 * @s}

    for context <- [ctx(), empty],
        selector <- [~s'{span.missing="none"}', "{duration>10s}"],
        op <- ["count_over_time", "rate"] do
      query = "#{selector} | #{op}()"
      labels = [%{"key" => "__name__", "value" => %{"stringValue" => op}}]
      assert range(context, query) == %{%{"__name__" => op} => zeros(%{})}
      assert {:ok, json} = Metrics.query(context.tenant, query, window, true)
      assert Pulse.JSON.decode!(json) == %{"series" => [%{"labels" => labels, "value" => 0}]}

      assert range(context, query <> " by (name)") == %{}
    end

    for op <- ["min", "max", "sum", "avg", "histogram"], context <- [ctx(), empty] do
      assert range(context, ~s'{span.missing="none"} | #{op}_over_time(duration)') == %{}
    end

    assert range(empty, "{} | count_over_time()") == %{%{"__name__" => "count_over_time"} => zeros(%{})}

    assert {:ok, json} = Metrics.query(ctx().tenant, "{} | rate()", {2000 * @s, 2060 * @s, 10 * @s}, false)
    assert [%{"samples" => samples}] = Pulse.JSON.decode!(json)["series"]
    assert points(%{"samples" => samples}) == Map.new(2000..2060//10, &{&1, 0})
  end

  test "range interval admission uses the requested window, not the aligned output" do
    tenant = ctx().tenant <> "-interval-limit"
    query = "{} | count_over_time()"
    start = 1000 * @s
    finish = start + 10 * @s
    step = 1_000_000

    for {extra_ns, expected_points, last_ms} <- [{0, 10_001, 1_010_000}, {999_999, 10_002, 1_010_001}] do
      assert {:ok, json} = Metrics.query(tenant, query, {start, finish + extra_ns, step}, false)
      assert [%{"samples" => samples}] = Pulse.JSON.decode!(json)["series"]
      assert length(samples) == expected_points
      assert hd(samples) == %{"timestampMs" => "1000000", "value" => 0}
      assert List.last(samples) == %{"timestampMs" => to_string(last_ms), "value" => 0}
    end

    assert {:error, {:trace_metrics_step_too_small, ^step, 1_000_100}} =
             Metrics.query(tenant, query, {start, finish + step, step}, false)

    # Preserve upstream integer division, not a ceil or an alignment-derived minimum.
    assert {:error, {:trace_metrics_step_too_small, 1000, 1001}} =
             Metrics.query(tenant, query, {start, start + 10_010_999, 1000}, false)

    assert {:error, :unsupported_parameters} =
             Metrics.query(tenant, query, {9_223_372_036_854_775_800, 9_223_372_036_854_775_807, 10}, false)

    assert {:ok, json} = Metrics.query(tenant, query, {start, finish + step, step}, true)
    assert [%{"value" => 0}] = Pulse.JSON.decode!(json)["series"]
  end

  test "root spans, status selectors and missing group values" do
    assert range(ctx(), "{nestedSetParent<0 && true} | count_over_time() by (resource.service.name)") == %{
             %{"resource.service.name" => "api"} => zeros(%{1010 => 1}),
             %{"resource.service.name" => "web"} => zeros(%{1020 => 1})
           }

    assert range(ctx(), "{status=error} | rate()") == %{%{"__name__" => "rate"} => zeros(%{1010 => 0.1})}

    assert range(ctx(), "{} | count_over_time() by (span.missing)") == %{
             %{"span.missing" => "nil"} => zeros(%{1010 => 2, 1020 => 1})
           }
  end

  test "duration aggregations report seconds, only where spans exist" do
    assert range(ctx(), "{} | avg_over_time(duration) by (resource.service.name)") == %{
             %{"resource.service.name" => "api"} => %{1010 => 0.2},
             %{"resource.service.name" => "web"} => %{1020 => 2}
           }

    assert range(ctx(), "{} | max_over_time(duration)") == %{
             %{"__name__" => "max_over_time"} => %{1010 => 0.3, 1020 => 2}
           }
  end

  test "quantiles and histograms use power-of-two duration buckets" do
    assert range(ctx(), "{} | quantile_over_time(duration, 0.5) by (resource.service.name)") == %{
             %{"resource.service.name" => "api", "p" => 0.5} => zeros(%{1010 => 0.134217728}),
             %{"resource.service.name" => "web", "p" => 0.5} => zeros(%{1020 => 2.147483648})
           }

    assert range(ctx(), "{} | histogram_over_time(duration)") == %{
             %{"__bucket" => 0.134217728} => zeros(%{1010 => 1}),
             %{"__bucket" => 0.536870912} => zeros(%{1010 => 1}),
             %{"__bucket" => 2.147483648} => zeros(%{1020 => 1})
           }
  end

  test "topk and bottomk keep the k extreme series per interval" do
    # Ties (the empty intervals) go to the series first in label order.
    query = "{} | count_over_time() by (resource.service.name) | topk(1)"

    assert range(ctx(), query) == %{
             %{"resource.service.name" => "api"} => %{1000 => 0, 1010 => 2, 1030 => 0, 1040 => 0, 1050 => 0, 1060 => 0},
             %{"resource.service.name" => "web"} => %{1020 => 1}
           }

    assert {:ok, %{second: {"bottomk", 2}}} = Metrics.parse("{} | rate() by (name) | bottomk(2) with(sample=true)")
    assert {:error, _} = Metrics.parse("{} | rate() | topk(0)")
  end

  test "native prefilter ranking agrees with BEAM scalar filters and per-interval selection" do
    source = "{} | count_over_time() by (resource.service.name)"

    for filter <- ["= 0", "!= 0", "< 1", "<= 1", "> 1", ">= 1"],
        rank <- ["topk", "bottomk"],
        k <- [1, 2, 3] do
      # The existing bounded BEAM scalar-filter path is the reference for
      # retained slots; this authored reduction independently selects winners.
      filtered = range(ctx(), source <> " " <> filter)

      expected =
        for ts <- 1000..1060//10,
            {labels, value} <-
              filtered
              |> Enum.flat_map(fn {labels, points} ->
                if Map.has_key?(points, ts), do: [{labels, points[ts]}], else: []
              end)
              |> Enum.sort(fn {a, av}, {b, bv} ->
                cond do
                  av == bv -> if(rank == "topk", do: a <= b, else: a >= b)
                  rank == "topk" -> av > bv
                  true -> av < bv
                end
              end)
              |> Enum.take(k),
            reduce: %{} do
          result -> Map.update(result, labels, %{ts => value}, &Map.put(&1, ts, value))
        end

      query = source <> " " <> filter <> " | #{rank}(#{k})"
      assert range(ctx(), query) == expected, query
      assert range(ctx(), "(#{query}) + 0") == expected, query
    end

    # Numeric aggregations have absent intervals, unlike count's zero slots.
    query = "{} | min_over_time(duration) by (resource.service.name) > 0 | bottomk(1)"

    assert range(ctx(), query) == %{
             %{"resource.service.name" => "api"} => %{1010 => 0.1},
             %{"resource.service.name" => "web"} => %{1020 => 2}
           }
  end

  test "native ranking independently rejects malformed prefilter schemas" do
    for second <- [
          {"bottomk", 1, {"unknown", 1.0}},
          {"bottomk", 0, {">", 1.0}},
          {"unknown", 1, {">", 1.0}},
          {"bottomk", 1, {">", "1"}},
          {"bottomk", 1, [{">", 1.0}]},
          {"bottomk", 1, {">", 1.0}, :extra},
          :malformed
        ] do
      assert :fallback =
               NIF.trace_metrics_new(
                 nil,
                 false,
                 "count_over_time",
                 [],
                 nil,
                 [],
                 {0, @s, @s, false},
                 second
               )
    end
  end

  test "instant queries return one value per series over the closed window" do
    {:ok, json} = Metrics.query(ctx().tenant, "{} | count_over_time()", {1000 * @s, 1060 * @s, nil}, true)

    assert Pulse.JSON.decode!(json) == %{
             "series" => [
               %{"labels" => [%{"key" => "__name__", "value" => %{"stringValue" => "count_over_time"}}], "value" => 3}
             ]
           }
  end

  @tag :trace_math_batch
  test "metric scalar math keeps operand order and integer versus float constant folding" do
    leaf = "({} | count_over_time() by (resource.service.name))"

    assert range(ctx(), "20 - 2 * (#{leaf} + 3)") == %{
             %{"resource.service.name" => "api"} => Map.put(Map.new(1000..1060//10, &{&1, 14}), 1010, 10),
             %{"resource.service.name" => "web"} => Map.new(1000..1060//10, &{&1, if(&1 == 1020, do: 12, else: 14)})
           }

    assert range(ctx(), leaf <> " * (3/2)") == %{
             %{"resource.service.name" => "api"} => zeros(%{1010 => 2}),
             %{"resource.service.name" => "web"} => zeros(%{1020 => 1})
           }

    assert range(ctx(), leaf <> " * (3.0/2)") == %{
             %{"resource.service.name" => "api"} => zeros(%{1010 => 3}),
             %{"resource.service.name" => "web"} => zeros(%{1020 => 1.5})
           }

    assert range(ctx(), leaf <> " * (-9223372036854775808 + 9223372036854775807)") == %{
             %{"resource.service.name" => "api"} => zeros(%{1010 => -2}),
             %{"resource.service.name" => "web"} => zeros(%{1020 => -1})
           }

    for literal <- [
          "9223372036854775808",
          "12345678901234567890",
          "-9223372036854775809",
          "(-9223372036854775808 / -1)",
          "(9223372036854775807 + 1)"
        ] do
      assert {:error, _} = Metrics.parse(leaf <> " * " <> literal)
    end
  end

  @tag :trace_math_batch
  test "metric joins broadcast only ungrouped operands and preserve arithmetic names" do
    grouped = "({} | count_over_time() by (resource.service.name))"
    total = "({} | count_over_time())"

    expected = %{
      %{"resource.service.name" => "api"} => %{1010 => 1, 1020 => 0},
      %{"resource.service.name" => "web"} => %{1010 => 0, 1020 => 1}
    }

    assert range(ctx(), "#{grouped} / #{total}") == expected

    assert range(ctx(), "#{total} / #{grouped}") == %{
             %{"resource.service.name" => "api"} => %{1010 => 1},
             %{"resource.service.name" => "web"} => %{1020 => 1}
           }

    assert range(ctx(), total <> " + ({} | rate())") == %{
             %{"__name__" => "(count_over_time + rate)"} => zeros(%{1010 => 2.2, 1020 => 1.1})
           }

    assert range(ctx(), grouped <> " + ({} | count_over_time() by (name))") == %{}
  end

  @tag :trace_math_batch
  test "metric joins distinguish typed values, ordered labels and missing groups" do
    spans =
      for {value, id} <- [{%{"intValue" => "123"}, 1}, {%{"stringValue" => "123"}, 2}, {nil, 3}] do
        attributes = [%{"key" => "bar", "value" => %{"stringValue" => "z"}}]
        attributes = if value, do: [%{"key" => "foo", "value" => value} | attributes], else: attributes

        %{
          "traceId" => "0af7651916cd43dd8448eb211c80319c",
          "spanId" => Base.encode16(<<id::64>>, case: :lower),
          "startTimeUnixNano" => to_string(1001 * @s),
          "endTimeUnixNano" => to_string(1002 * @s),
          "attributes" => attributes
        }
      end

    assert {:ok, records, 0} = Traces.decode(%{"resourceSpans" => [%{"scopeSpans" => [%{"spans" => spans}]}]})
    context = %{ctx() | tenant: ctx().tenant <> "-typed-joins"}
    assert :ok = Storage.append(:traces, context.tenant, records)

    # The missing foo is omitted, so that one group has identical bar-only
    # labels in both orders. Groups retaining both keys must not match.
    assert range(context, "({} | count_over_time() by (span.foo, span.bar)) + ({} | rate() by (span.bar, span.foo))") ==
             %{%{"span.bar" => "z"} => zeros(%{1010 => 1.1})}

    assert range(context, "({} | count_over_time() by (span.foo)) + ({} | rate() by (span.bar))") == %{}

    assert range(
             context,
             ~s'({span.foo=123} | count_over_time() by (span.foo)) + ({span.foo="123"} | rate() by (span.foo))'
           ) == %{}

    query = "({} | count_over_time() by (span.foo)) + ({} | rate() by (span.foo))"
    assert {:ok, json} = Metrics.query(context.tenant, query, {1000 * @s, 1060 * @s, 10 * @s}, false)
    series = Pulse.JSON.decode!(json)["series"]
    assert length(series) == 3

    assert MapSet.new(Enum.map(series, & &1["labels"])) ==
             MapSet.new(
               for value <- [%{"stringValue" => "nil"}, %{"intValue" => "123"}, %{"stringValue" => "123"}],
                   do: [%{"key" => "span.foo", "value" => value}]
             )

    assert Enum.all?(series, &(points(&1) == zeros(%{1010 => 1.1})))
  end

  @tag :trace_math_batch
  test "metric filters keep values and propagate masked samples through later arithmetic" do
    leaf = "({} | count_over_time() by (resource.service.name))"
    assert range(ctx(), "(#{leaf} > 1) * 10 != 0") == %{%{"resource.service.name" => "api"} => %{1010 => 20}}
    assert range(ctx(), "(#{leaf} / 0) != 1") == %{}
    assert range(ctx(), "#{leaf} >= 1 < 2") == %{%{"resource.service.name" => "web"} => %{1020 => 1}}
  end

  test "parses Tempo's metrics grammar and rejects what it cannot evaluate" do
    assert {:ok, %{op: "quantile_over_time", quantiles: [0.9, 0.99], value: {"intrinsic", "duration"}}} =
             Metrics.parse("{ } | quantile_over_time(duration, .9, .99) by (.service) with(exemplars=true)")

    assert {:ok, %{root_only: true, program: [_ | _]}} =
             Metrics.parse(~s'{nestedSetParent<0 && resource.service.name="api"} | rate()')

    assert {:error, _} = Metrics.parse("{} | rate(duration)")
    assert {:error, _} = Metrics.parse("{} | topk(5)")
    assert {:error, _} = Metrics.parse("{nestedSetParent<0 || status=error} | rate()")
    assert {:error, _} = Metrics.parse("{} | rate() by (a, b, c, d, e, f)")
  end

  test "aligns ranges like Tempo, with one extra leading interval" do
    assert Metrics.window({1003 * @s, 1057 * @s, 10 * @s}, false) == {:ok, {990 * @s, 1060 * @s, 10 * @s, false}}
    assert Metrics.default_step(0, 3600 * @s) == 15 * @s
    assert Metrics.default_step(0, 60 * @s) == @s
  end

  # The setup context through the process dictionary keeps test bodies short.
  defp ctx, do: Process.get(:ctx)

  setup ctx do
    Process.put(:ctx, ctx)
    :ok
  end
end
