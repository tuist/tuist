defmodule Pulse.LogQL.NativeRangeParityTest do
  # The native range scan must answer exactly like the Elixir pipeline.
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.MetricEval
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.QueryValidation
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.MetricEvalReference
  alias Pulse.Test.NativeQueryStorage

  @second 1_000_000_000

  setup do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: NativeQueryStorage)
    tenant = "native-range-#{System.unique_integer([:positive])}"

    records =
      for i <- 1..400 do
        ts = Enum.random(0..120) * @second
        dur = Enum.random(["#{Enum.random(1..900)}", "#{Enum.random(1..900)}.5", "oops", "", nil])
        quoted = Enum.random(["", ~s( msg="hello \\"x\\" world")])

        body =
          "level=info " <>
            if(dur, do: "dur=#{dur} ", else: "") <> "code=#{Enum.random([200, 404, 503])}#{quoted} n=#{i}"

        %Log{
          timestamp_ns: ts,
          service: Enum.random(["api", "web", nil]),
          severity_text: Enum.random(["info", "error", nil]),
          body: body,
          trace_id: Enum.random([nil, "", "t#{rem(i, 3)}"]),
          span_id: Enum.random([nil, "", "s#{rem(i, 7)}"]),
          attributes: Enum.random([%{}, %{"trace" => "t#{rem(i, 5)}"}, %{"trace_id" => "attribute", "span_id" => ""}]),
          resource: %{"app" => Enum.random(["a", "b"]), "pod" => Enum.random(["p1", "p2", "p3"])}
        }
      end

    :ok = Storage.append(:logs, tenant, records)
    {:ok, tenant: tenant}
  end

  defp query do
    unwrap? = :rand.uniform(2) == 1

    op =
      Enum.random(
        if(unwrap?,
          do: ~w(sum_over_time avg_over_time min_over_time max_over_time stddev_over_time quantile_over_time rate),
          else: ~w(count_over_time rate bytes_over_time bytes_rate)
        )
      )

    stages =
      Enum.random([
        ~s/| logfmt/,
        ~s/|= "level" | logfmt | code=~"5.." or dur > 300/,
        ~s/| regexp "dur=(?P<d>[0-9.]+)(?P<rest> .*)?" | d != ""/,
        ~s/!~ "n=1[0-9]" | logfmt | code != "404" and pod != "p3"/,
        ~s/| logfmt | msg =~ "hello.*" or level="info"/,
        ~s/| trace_id!="" | logfmt/,
        ~s/| span_id=~"s.*" | logfmt | trace_id=~".+"/,
        ~s/| logfmt | keep app, code, dur, trace_id | code != "404"/,
        ~s/| logfmt | __error__="" | keep pod, dur/
      ])

    unwrap =
      if unwrap?,
        do: Enum.random([" | unwrap dur", " | logfmt | unwrap dur", ~s/ | unwrap dur | __error__=""/]),
        else: ""

    selector = Enum.random([~s/{app=~"a|b"}/, ~s/{app="a", service_name="api"}/, ~s/{pod!="p2"}/])
    param = if op == "quantile_over_time", do: "0.75, ", else: ""

    grouping =
      if op in ~w(avg_over_time min_over_time max_over_time stddev_over_time quantile_over_time),
        do: Enum.random(["", " by (pod)", " without (n, msg, trace)"]),
        else: ""

    inner = "#{op}(#{param}#{selector} #{stages}#{unwrap} [#{Enum.random(~w(10s 30s 1m))}])#{grouping}"
    if :rand.uniform(2) == 1, do: "sum by (app) (#{inner})", else: inner
  end

  # Both evaluators default to the 10 s query deadline, which the reference
  # can exceed under CI contention and then answer :query_timeout instead of a
  # comparable result. Give each evaluation a deadline the test cannot hit.
  defp evaluate(module, ast, tenant, opts) do
    Process.delete(:promql_budget)
    Process.delete(:promql_deadline_ms)
    Process.put(:query_deadline_ms, System.monotonic_time(:millisecond) + 120_000)
    module.evaluate(ast, tenant, opts)
  end

  # The frozen reference predates post-unwrap filters: compare those with the
  # Elixir pipeline over the same records (the memory adapter never scans natively).
  defp expected(ast, text, tenant, opts) do
    if String.contains?(text, ~s/unwrap dur | __error__=""/) do
      Pulse.Runtime.put_env(:pulse, Storage, adapter: Memory)

      try do
        evaluate(MetricEval, ast, tenant, opts)
      after
        Pulse.Runtime.put_env(:pulse, Storage, adapter: NativeQueryStorage)
      end
    else
      evaluate(MetricEvalReference, ast, tenant, opts)
    end
  end

  defp canonical({:ok, {kind, series}}),
    do: {:ok, kind, series |> Enum.map(fn {labels, samples} -> {labels, approx(samples)} end) |> Enum.sort()}

  defp canonical(other), do: other
  defp approx(samples) when is_list(samples), do: Enum.map(samples, fn {ts, v} -> {ts, approx(v)} end)
  defp approx({ts, v}), do: {ts, approx(v)}
  defp approx(v) when is_float(v), do: Float.round(v, 9)
  defp approx(v), do: v

  # Keep all 120 native/reference comparisons, including multi-step windows,
  # without applying the ordinary one-minute test budget under CI contention.
  @tag timeout: 300_000
  test "random native range scans match the materializing evaluator", %{tenant: tenant} do
    for _ <- 1..120 do
      text = query()
      {:ok, ast} = Parser.parse(text)
      assert :ok = QueryValidation.validate(ast)

      opts =
        Enum.random([
          %{start_ts_ns: 10 * @second, end_ts_ns: 120 * @second, step_ns: Enum.random([5, 15]) * @second},
          %{end_ts_ns: Enum.random(30..130) * @second}
        ])

      expected = expected(ast, text, tenant, opts)
      actual = evaluate(MetricEval, ast, tenant, opts)

      assert canonical(actual) == canonical(expected), """
      #{text} #{inspect(opts)}
      expected: #{inspect(canonical(expected))}
      actual: #{inspect(canonical(actual))}
      """
    end

    native = Stream.repeatedly(fn -> receive do: (:native_log_metric_scan -> 1), after: (0 -> nil) end)
    native_scans = native |> Enum.take_while(& &1) |> length()
    # Most queries must take the native path rather than fall back.
    assert native_scans >= 80
  end

  @tag :correlation_labels_batch
  test "native correlation metadata preserves both IDs, attribute ownership and stream collisions" do
    tenant = "native-correlation-#{System.unique_integer([:positive])}"
    resource = %{"app" => "correlation"}

    # The first three records share every old cache-key field, but differ
    # independently in span and trace ID inside the same native input batch.
    records = [
      %Log{trace_id: "t1", span_id: "s1"},
      %Log{trace_id: "t1", span_id: "s2"},
      %Log{trace_id: "t2", span_id: "s1"},
      %Log{trace_id: "", span_id: ""},
      %Log{},
      %Log{trace_id: "dedicated", span_id: "dedicated-span", attributes: %{"trace_id" => "attribute", "span_id" => ""}},
      %Log{
        trace_id: "dedicated",
        span_id: "dedicated-span",
        resource: %{
          "app" => "correlation",
          "trace_id" => "stream",
          "trace_id_extracted" => "reserved",
          "span_id" => "stream-span"
        }
      }
    ]

    records =
      Enum.map(records, fn record ->
        %{record | timestamp_ns: 5 * @second, body: "line", resource: Map.merge(resource, record.resource)}
      end)

    assert :ok = Storage.append(:logs, tenant, records)
    end_ts = 30 * @second

    expected = %{
      %{"app" => "correlation", "trace_id" => "t1", "span_id" => "s1"} => 1.0,
      %{"app" => "correlation", "trace_id" => "t1", "span_id" => "s2"} => 1.0,
      %{"app" => "correlation", "trace_id" => "t2", "span_id" => "s1"} => 1.0,
      %{"app" => "correlation"} => 2.0,
      %{"app" => "correlation", "trace_id" => "attribute", "span_id" => ""} => 1.0,
      %{
        "app" => "correlation",
        "trace_id" => "stream",
        "trace_id_extracted" => "reserved",
        "span_id" => "stream-span",
        "span_id_extracted" => "dedicated-span"
      } => 1.0
    }

    assert {:ok, ast} = Parser.parse(~s'count_over_time({app="correlation"}[1m])')

    for module <- [MetricEvalReference, MetricEval] do
      assert {:ok, {:vector, series}} = evaluate(module, ast, tenant, %{end_ts_ns: end_ts})
      assert Map.new(series, fn {labels, {^end_ts, value}} -> {labels, value} end) == expected
    end

    assert_received :native_log_metric_scan
  end

  test "failed unwrap replaces an earlier typed-filter error before metric validation" do
    tenant = "native-error-order-#{System.unique_integer([:positive])}"

    assert :ok =
             Storage.append(:logs, tenant, [
               %Log{timestamp_ns: 5 * @second, body: "code=200 dur=oops", resource: %{"app" => "error-order"}}
             ])

    # Loki streamLabelSampleExtractor.Process runs conversion after pre-stages
    # and SetErr replaces the previous error/details, before metric validation.
    for filter <- [~s(dur > 300), ~s(code=~"5.." or dur > 300)],
        module <- [MetricEvalReference, MetricEval] do
      {:ok, ast} = Parser.parse(~s/min_over_time({app="error-order"} | logfmt | #{filter} | unwrap dur [1m]) by (app)/)
      assert {:error, :sample_extraction_error} = evaluate(module, ast, tenant, %{end_ts_ns: 30 * @second})
    end
  end

  test "native literal line filters preserve contains and not-contains results", %{tenant: tenant} do
    records =
      for body <- ["hello", "world", "hello world"] do
        %Log{timestamp_ns: 5 * @second, body: body, resource: %{"app" => "literal-filter"}}
      end

    assert :ok = Storage.append(:logs, tenant, records)

    end_ts = 30 * @second

    for {filter, expected} <- [{~s/|= "hello"/, 2.0}, {~s/!= "hello"/, 1.0}] do
      {:ok, ast} = Parser.parse(~s/count_over_time({app="literal-filter"} #{filter} [1m])/)

      assert {:ok, {:vector, [{%{"app" => "literal-filter"}, {^end_ts, ^expected}}]}} =
               evaluate(MetricEval, ast, tenant, %{end_ts_ns: end_ts})

      assert_received :native_log_metric_scan
    end
  end

  test "native logfmt preserves recovery, escapes and first normalized nonempty values" do
    tenant = "native-logfmt-#{System.unique_integer([:positive])}"

    records =
      for body <- [
            "n=1 n=2",
            "a-b=3 a_b=4 n=3",
            "n= n=5 bare= bare",
            "bad=bu=zz n=7",
            ~S/bad="\q" n=11/,
            ~S/n=13 msg="a\nb"/,
            "noise=skip\0n=17",
            ~S/prefix="ok"n=19/,
            ~S/n=23 bad="unterminated/
          ] do
        %Log{timestamp_ns: 5 * @second, body: body, resource: %{"app" => "logfmt"}}
      end

    assert :ok = Storage.append(:logs, tenant, records)
    end_ts = 30 * @second

    for {expression, expected} <- [
          {~s/sum(sum_over_time({app="logfmt"} | logfmt | unwrap n [1m]))/, 99.0},
          {~s/sum(count_over_time({app="logfmt"} | logfmt [1m]))/, 9.0},
          {~s/sum(count_over_time({app="logfmt"} | logfmt | a_b="3" [1m]))/, 1.0},
          {~s/sum(count_over_time({app="logfmt"} | logfmt | n="1" [1m]))/, 1.0},
          {~S/sum(count_over_time({app="logfmt"} | logfmt | msg="a\nb" [1m]))/, 1.0}
        ] do
      assert {:ok, ast} = Parser.parse(expression)

      assert {:ok, {:vector, [{%{}, {^end_ts, ^expected}}]}} =
               evaluate(MetricEval, ast, tenant, %{end_ts_ns: end_ts})

      assert_received :native_log_metric_scan

      assert {:ok, {:vector, [{%{}, {^end_ts, ^expected}}]}} =
               evaluate(MetricEvalReference, ast, tenant, %{end_ts_ns: end_ts})
    end
  end

  test "native scans stop at the retained log sample budget", %{tenant: tenant} do
    config = Pulse.Runtime.get_env(:pulse, Evaluator, [])
    Pulse.Runtime.put_env(:pulse, Evaluator, Keyword.put(config, :max_log_samples, 10))
    {:ok, ast} = Parser.parse(~s/count_over_time({app=~"a|b"} [2m])/)

    assert evaluate(MetricEval, ast, tenant, %{end_ts_ns: 130 * @second}) == {:error, :query_sample_limit}
  end

  test "rows the native scan cannot reproduce fall back to the Elixir pipeline" do
    tenant = "native-fallback-#{System.unique_integer([:positive])}"

    :ok =
      Storage.append(:logs, tenant, [
        %Log{timestamp_ns: 5 * @second, body: "dur=10", resource: %{"app" => "a", "replicas" => 3}},
        %Log{timestamp_ns: 6 * @second, body: "dur=0x10", resource: %{"app" => "a"}}
      ])

    for text <- [~s/count_over_time({app="a"} | logfmt [1m])/, ~s/sum_over_time({app="a"} | logfmt | unwrap dur [1m])/] do
      {:ok, ast} = Parser.parse(text)
      opts = %{end_ts_ns: 30 * @second}

      assert canonical(evaluate(MetricEval, ast, tenant, opts)) ==
               canonical(evaluate(MetricEvalReference, ast, tenant, opts))
    end

    refute_received :native_log_metric_scan
  end

  test "keep and post-unwrap error filters of Tuist's web-vitals alerts run natively" do
    tenant = "native-keep-#{System.unique_integer([:positive])}"

    :ok =
      Storage.append(:logs, tenant, [
        %Log{
          timestamp_ns: 1 * @second,
          body: "kind=m env=prod session=s1 lcp=1200",
          resource: %{"app" => "w", "pod" => "p1"}
        },
        %Log{
          timestamp_ns: 2 * @second,
          body: "kind=m env=prod session=s1 lcp=oops",
          resource: %{"app" => "w", "pod" => "p1"}
        },
        %Log{
          timestamp_ns: 3 * @second,
          body: "kind=m env=dev session=s2 lcp=3400",
          resource: %{"app" => "w", "pod" => "p2"}
        },
        %Log{
          timestamp_ns: 4 * @second,
          body: "kind=x env=prod session=s3 lcp=9000",
          resource: %{"app" => "w", "pod" => "p2"}
        }
      ])

    opts = %{end_ts_ns: 30 * @second}

    for {text, expected} <- [
          # keep drops the stream labels and every unlisted parsed label.
          {~s/count by (env) (sum by (env, session) (count_over_time({app="w"} | logfmt | kind="m" | __error__="" | keep env, session [1m])))/,
           [{%{"env" => "dev"}, 1.0}, {%{"env" => "prod"}, 1.0}]},
          {~s/sum(count_over_time({app="w"} | logfmt | keep env [1m])) by (pod)/, [{%{}, 4.0}]},
          # The unconvertible lcp is dropped, not an extraction error.
          {~s/max_over_time({app="w"} | logfmt | kind="m" | unwrap lcp | __error__="" [1m]) by (env)/,
           [{%{"env" => "dev"}, 3400.0}, {%{"env" => "prod"}, 1200.0}]}
        ] do
      {:ok, ast} = Parser.parse(text)
      assert {:ok, {:vector, series}} = evaluate(MetricEval, ast, tenant, opts), text
      assert series |> Enum.map(fn {labels, {_, v}} -> {labels, v} end) |> Enum.sort() == expected, text
      assert_received :native_log_metric_scan, text
    end
  end
end
