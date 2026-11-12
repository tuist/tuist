defmodule Pulse.LogQL.BinaryBudgetTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.PromQL.Evaluator, as: Budget
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.MetricEvalReference

  setup do
    Memory.reset()

    records =
      for {pod, ts} <- [{"one", 9}, {"one", 10}, {"two", 10}],
          do: %Log{timestamp_ns: ts, service: "api", body: "hello", resource: %{"pod" => pod}}

    assert :ok = Storage.append(:logs, "acme", records)
    :ok
  end

  defp run(query, opts \\ %{end_ts_ns: 10}) do
    with {:ok, ast} <- Parser.parse(query) do
      # The evaluator accepts nanosecond AST windows, even though Loki's
      # public bracket grammar only accepts millisecond-or-larger units.
      {range_ns, opts} = Map.pop(opts, :range_ns)
      ast = if range_ns, do: %{ast | range_ns: range_ns}, else: ast
      Evaluator.evaluate_metric(ast, "acme", opts)
    end
  end

  test "scalar broadcasts work at every matrix step" do
    assert {:ok, {:matrix, series}} =
             run(~s'count_over_time({service="api"}[1m]) / 2', %{start_ts_ns: 10, end_ts_ns: 11, step_ns: 1})

    values = Map.new(series, fn {labels, points} -> {labels["pod"], points} end)
    assert values == %{"one" => [{10, 1.0}, {11, 1.0}], "two" => [{10, 0.5}, {11, 0.5}]}

    assert {:ok, {:matrix, [{%{}, [{10, 3.0}, {11, 3.0}]}]}} =
             run("1 + 2", %{start_ts_ns: 10, end_ts_ns: 11, step_ns: 1})
  end

  test "set unions retain unmatched right values and do not manufacture boolean ones" do
    assert {:ok, {:vector, series}} =
             run(~s'count_over_time({service="absent"}[1m]) or count_over_time({service="api"}[1m])')

    assert Map.new(series, fn {labels, {ts, value}} -> {labels["pod"], {ts, value}} end) == %{
             "one" => {10, 2.0},
             "two" => {10, 1.0}
           }

    assert {:ok, {:vector, both}} =
             run(~s'count_over_time({service="api"}[1m]) and count_over_time({service="api"}[1m])')

    assert Map.new(series) == Map.new(both)
  end

  test "empty-label aggregation is a vector and ambiguous matching rejects, never overwrites" do
    # LogQL now retains the indexed side for HTTP diagnostics. The frozen
    # reference shares matching, not error formatting, and must retain it too.
    one = ~s'sum(count_over_time({service="api"}[1m]))'
    many = ~s'count_over_time({service="api"}[1m])'

    for {query, side} <- [
          {one <> " + on () " <> many, :right},
          {many <> " + on () group_right " <> one, :left}
        ] do
      assert {:error, {:many_to_many_matching, ^side}} = run(query)
      assert {:ok, ast} = Parser.parse(query)

      assert {:error, {:many_to_many_matching, ^side}} =
               MetricEvalReference.evaluate(ast, "acme", %{end_ts_ns: 10})
    end
  end

  test "empty matrix windows are missing, not zero samples" do
    assert {:ok, {:matrix, series}} =
             run(~s'count_over_time({service="api"}[1ms])', %{start_ts_ns: 10, end_ts_ns: 12, step_ns: 1, range_ns: 1})

    assert Enum.all?(series, fn {_, points} -> points == [{10, 1.0}] end)
  end

  test "absence reports one only when the whole window is empty" do
    assert {:ok, {:vector, [{%{"service" => "missing"}, {10, 1.0}}]}} =
             run(~s'absent_over_time({service="missing", pod=~".*"}[1m])')

    assert {:ok, {:vector, []}} = run(~s'absent_over_time({service="api"}[1m])')

    assert {:ok, {:matrix, [{%{"service" => "api"}, [{11, 1.0}, {12, 1.0}]}]}} =
             run(~s'absent_over_time({service="api"}[1ms])', %{start_ts_ns: 10, end_ts_ns: 12, step_ns: 1, range_ns: 1})
  end

  test "invalid unwrapped points fail the whole query instead of averaging a valid subset" do
    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 10, service: "value", body: "x=1"},
               %Log{timestamp_ns: 10, service: "value", body: "x=invalid"}
             ])

    assert {:error, :sample_extraction_error} =
             run(~s'quantile_over_time(0.5, {service="value"} | logfmt | unwrap x [1m]) by ()')

    assert {:ok, {:vector, [{_, {10, 1.0}}]}} =
             run(~s'quantile_over_time(0.5, {service="value"} | logfmt | unwrap x | __error__="" [1m])')

    assert {:error, :unsupported_post_unwrap_stage} =
             run(~s'quantile_over_time(0.5, {service="value"} | logfmt | unwrap x | json [1m])')

    assert {:error, :invalid_range_duration} = run(~s'count_over_time({service="api"}[0s])')
  end

  test "nonfinite extracted values propagate through range and vector folds without arithmetic crashes" do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "special", body: "x=NaN"}])

    for operation <- ~w(sum_over_time avg_over_time min_over_time max_over_time stddev_over_time stdvar_over_time) do
      assert {:ok, {:vector, [{_, {10, :nan}}]}} = run(~s'#{operation}({service="special"} | logfmt | unwrap x [1m])')
    end

    for operation <- ~w(sum avg min max stddev stdvar) do
      assert {:ok, {:vector, [{%{}, {10, :nan}}]}} =
               run(~s'#{operation}(quantile_over_time(0.5, {service="special"} | logfmt | unwrap x [1m]))')
    end
  end

  test "rank and sort put NaNs last, preserve matrix series and reject fractional ranks" do
    records =
      for value <- ["NaN", "1", "+Inf", "-Inf"],
          do: %Log{timestamp_ns: 10, service: "rank", body: "x=#{value}", resource: %{"pod" => value}}

    assert :ok = Storage.append(:logs, "acme", records)
    inner = ~s'sum_over_time({service="rank"} | logfmt | unwrap x [1m])'
    assert {:ok, {:vector, top}} = run("topk(3, #{inner})")
    assert Enum.map(top, fn {_, {_, value}} -> value end) == [:infinity, 1.0, :negative_infinity]
    assert {:ok, {:vector, sorted}} = run("sort(#{inner})")
    assert Enum.map(sorted, fn {_, {_, value}} -> value end) == [:negative_infinity, 1.0, :infinity, :nan]
    assert {:ok, {:matrix, matrix}} = run("sort(#{inner})", %{start_ts_ns: 10, end_ts_ns: 11, step_ns: 1})
    assert length(matrix) == 4
    assert {:ok, {:vector, []}} = run("topk(-1, #{inner})")
    assert {:error, :invalid_aggregation_parameter} = run("topk(1.5, #{inner})")
  end

  test "unwrap number grammar follows Go ParseFloat, not query integer literals" do
    for {text, expected} <- [{"1_000", 1000.0}, {"0x1_0p0", 16.0}] do
      assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: text, body: "x=#{text}"}])

      assert {:ok, {:vector, [{_, {10, ^expected}}]}} =
               run(~s'sum_over_time({service="#{text}"} | logfmt | unwrap x [1m])')
    end

    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "hex_integer", body: "x=0x10"}])
    assert {:error, :sample_extraction_error} = run(~s'sum_over_time({service="hex_integer"} | logfmt | unwrap x [1m])')
  end

  @tag :template_functions_batch
  test "template amplification fails whole above 16 MiB even with explicit error preservation" do
    line = String.duplicate("x", 524_288)
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "template-limit", body: line}])

    template = String.duplicate("{{__line__}}", 32)
    expression = ~s/{service="template-limit"} | line_format / <> Pulse.JSON.encode!(template)
    assert {:ok, ast} = Parser.parse(expression)
    assert {:ok, [{_labels, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    assert byte_size(output) == 16_777_216
    assert output == String.duplicate("x", 16_777_216)

    for stage <- ["line_format ", "label_format out="] do
      oversized = stage <> Pulse.JSON.encode!(template <> "!")
      expression = ~s/{service="template-limit"} | / <> oversized <> ~s/ | __error__!=""/
      assert {:ok, ast} = Parser.parse(expression)

      # Both materialized and top-k fold paths must return the budget failure,
      # never an empty success or a preservable TemplateFormatErr.
      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end
  end

  @tag :template_count_batch
  test "regex counting shares the work ceiling across entries and actions and fails whole" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 32))
    line = String.duplicate("a", 12)
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "count-limit", body: line}])
    template = ~s'{{count "a" (__line__)}}'
    expression = ~s/{service="count-limit"} | line_format / <> Pulse.JSON.encode!(template)
    assert {:ok, ast} = Parser.parse(expression)
    assert {:ok, [{_, [{10, "12"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    for stage <- ["line_format ", "label_format out="] do
      expression = ~s/{service="count-limit"} | / <> stage <> Pulse.JSON.encode!(String.duplicate(template, 3))
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
      assert {:error, :query_work_limit} = run(~s'bytes_over_time(#{expression} | __error__!="" [1m])')
    end

    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 11, service: "count-limit", body: line},
               %Log{timestamp_ns: 12, service: "count-limit", body: line}
             ])

    assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 12})
  end

  @tag :template_json_batch
  test "template JSON decoding shares preallocation work and fails whole on nesting exhaustion" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 32))
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "json-limit", body: "[1,2,3]"}])
    selector = ~s/{service="json-limit"}/
    decode = ~s'{{len (fromJson (__line__))}}'
    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(decode))
    assert {:ok, [{_, [{10, "3"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    for template <- [
          String.duplicate(decode, 5),
          ~s'{{len (fromJson (repeat 33 "x"))}}',
          ~s'{{len (fromJson (__line__))}}{{range 26}}{{end}}',
          ~s'{{range 26}}{{end}}{{len (fromJson (__line__))}}',
          ~s'{{len (fromJson (__line__))}}{{count "" (__line__)}}{{len (fromJson (__line__))}}{{count "" (__line__)}}{{range 1}}{{end}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = selector <> " | " <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
    end

    assert :ok =
             Storage.append(
               :logs,
               "acme",
               for(ts <- 11..14, do: %Log{timestamp_ns: ts, service: "json-limit", body: "[1,2,3]"})
             )

    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(decode))
    assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 14})

    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 1000))

    for depth <- [64, 65], stage <- ["line_format ", "label_format out="] do
      json = String.duplicate("[", depth) <> "0" <> String.duplicate("]", depth)
      template = "{{len (fromJson " <> Pulse.JSON.encode!(json) <> ")}}"
      expression = selector <> " | " <> stage <> Pulse.JSON.encode!(template)
      assert {:ok, ast} = Parser.parse(expression)

      if depth == 64 do
        assert {:ok, [{labels, [{10, line}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
        assert if(stage == "line_format ", do: line, else: labels["out"]) == "1"
      else
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
        assert {:error, :query_result_limit} = run(~s'bytes_over_time(#{expression} | __error__!="" [1m])')
      end
    end
  end

  @tag :template_json_batch
  test "template JSON input normalization and rendered values retain the byte ceiling" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 67_108_864))
    max_bytes = 16_777_216
    content = String.duplicate("a", max_bytes - 2)
    json = "\"" <> content <> "\""
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "json-bytes", body: json}])
    selector = ~s/{service="json-bytes"}/
    template = ~s'{{fromJson (__line__)}}xx'
    expression = selector <> " | line_format " <> Pulse.JSON.encode!(template)
    assert {:ok, ast} = Parser.parse(expression)
    assert {:ok, [{_, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    assert output == content <> "xx"

    # Normalization must prove replacement growth before allocating it, even
    # when a later field access or explicit error selection would hide output.
    invalid = "\"" <> :binary.copy(<<255>>, div(max_bytes - 2, 3) + 1) <> "\""

    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 11, service: "json-raw-overflow", body: json <> " "},
               %Log{timestamp_ns: 12, service: "json-normalized-overflow", body: invalid}
             ])

    for service <- ["json-raw-overflow", "json-normalized-overflow"], stage <- ["line_format ", "label_format out="] do
      template = ~s'{{len (fromJson (__line__))}}'
      expression = ~s/{service="#{service}"} | / <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)
      assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 12})
      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])", %{end_ts_ns: 12})
    end
  end

  @tag :template_array_slice_batch
  test "sliced array views retain shared loop work and complete rendered-output admission" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 32))
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "array-limit", body: "[1,2,3]"}])
    selector = ~s/{service="array-limit"}/
    template = ~s'{{$a:=fromJson (__line__)}}{{range 7}}{{range (slice $a 1 3)}}{{end}}{{end}}ok'
    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(template))
    assert {:ok, [{_, [{10, "ok"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    template = ~s'{{$a:=fromJson (__line__)}}{{range 9}}{{range (slice $a 1 3)}}{{continue}}{{end}}{{end}}'

    for stage <- ["line_format ", "label_format out="] do
      expression = selector <> " | " <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
    end

    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 67_108_864))
    max_bytes = 16_777_216
    content = String.duplicate("a", max_bytes - 4)
    json = ~s'["#{content}"]'
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 11, service: "array-bytes", body: json}])
    selector = ~s/{service="array-bytes"}/
    template = ~s'{{slice (fromJson (__line__)) 0 1}}xx'
    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(template))
    assert {:ok, [{_, [{11, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 11})
    assert output == "[" <> content <> "]xx"

    for template <- [
          ~s'{{slice (fromJson (__line__)) 0 1}}xxx',
          ~s'{{trunc 1 (print (slice (fromJson (__line__)) 0 1) "xxx")}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = selector <> " | " <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 11}, %{end_ts_ns: 11, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])", %{end_ts_ns: 11})
    end
  end

  @tag :template_range_batch
  test "template iterations share work across entries, actions and regex helpers even without output" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 32))
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "range-limit", body: "aaaaaaaa"}])

    template = ~s'{{range 24}}{{end}}ok'
    selector = ~s/{service="range-limit"}/
    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(template))
    assert {:ok, [{_, [{10, "ok"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    # Charge actual iterations, not the potential int64 cardinality.
    early_break = ~s'{{range 9223372036854775807}}{{.}}{{break}}{{end}}'
    assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(early_break))
    assert {:ok, [{_, [{10, "0"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    for template <- [
          ~s'{{range 33}}{{continue}}{{end}}',
          String.duplicate(~s'{{range 17}}{{end}}', 2),
          ~s'{{range 24}}{{end}}{{count "a" (__line__)}}',
          ~s'{{count "a" (__line__)}}{{range 24}}{{end}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = selector <> " | " <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
    end

    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 11, service: "range-limit", body: "second"},
               %Log{timestamp_ns: 12, service: "range-limit", body: "third"}
             ])

    expression = selector <> " | line_format " <> Pulse.JSON.encode!(~s'{{range 12}}{{end}}')
    assert {:ok, ast} = Parser.parse(expression)
    assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 12})
  end

  @tag :template_regex_replace_batch
  test "regex replacement shares counting work and rejects oversized intermediate output" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 32))
    line = String.duplicate("a", 12)
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "replace-limit", body: line}])

    for function <- ["regexReplaceAll", "regexReplaceAllLiteral"] do
      replacement = ~s/{{#{function} "a" (__line__) "x"}}/
      expression = ~s/{service="replace-limit"} | line_format / <> Pulse.JSON.encode!(replacement)
      assert {:ok, ast} = Parser.parse(expression)
      assert {:ok, [{_, [{10, "xxxxxxxxxxxx"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

      # Each action alone fits. Their combined counting/replacement work must
      # share the same request budget, regardless of order or error selection.
      for template <- [~s/{{count "a" (__line__)}}/ <> replacement, replacement <> ~s/{{count "a" (__line__)}}/],
          stage <- ["line_format ", "label_format out="] do
        expression = ~s/{service="replace-limit"} | / <> stage <> Pulse.JSON.encode!(template)
        assert {:ok, ast} = Parser.parse(expression)

        for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
          assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", opts)
        end

        assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
        assert {:error, :query_work_limit} = run(~s'bytes_over_time(#{expression} | __error__!="" [1m])')
      end

      # Prove the exact output boundary and reject before a later truncation
      # could conceal an amplified intermediate, including literal replacement.
      template = ~s/{{#{function} "a" "aa" (repeat 8388608 "x")}}/
      assert {:ok, ast} = Parser.parse(~s/{service="replace-limit"} | line_format / <> Pulse.JSON.encode!(template))
      assert {:ok, [{_, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
      assert output == String.duplicate("x", 16_777_216)

      template = ~s/{{#{function} "a" "aa" (repeat 8388609 "x") | trunc 1}}/

      for stage <- ["line_format ", "label_format out="] do
        expression = ~s/{service="replace-limit"} | / <> stage <> Pulse.JSON.encode!(template) <> ~s/ | __error__!=""/
        assert {:ok, ast} = Parser.parse(expression)
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
        assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
      end
    end

    # Unknown references can expand to no bytes, but scanning them is still
    # work. An output ceiling alone cannot bound that amplification.
    template = ~s/{{regexReplaceAll "a" "a" (repeat 20 "$missing")}}/
    assert {:ok, ast} = Parser.parse(~s/{service="replace-limit"} | line_format / <> Pulse.JSON.encode!(template))
    assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    # A single long unknown name must spend its parsing work too. Each pass
    # probes one match and EOF, leaving fourteen name bytes under this cap.
    for size <- [14, 15] do
      template = ~s/{{regexReplaceAll "a" "a" "$#{String.duplicate("x", size)}"}}/
      assert {:ok, ast} = Parser.parse(~s/{service="replace-limit"} | line_format / <> Pulse.JSON.encode!(template))
      result = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

      if size == 14 do
        assert {:ok, [{_, [{10, ""}]}]} = result
      else
        assert {:error, :query_work_limit} = result
      end
    end

    # Every unmatched duplicate is lookup work even when no bytes result.
    # Each pass needs a match/EOF, one name byte and size-1 extra candidates.
    for size <- [14, 15], stage <- ["line_format ", "label_format out="] do
      pattern = String.duplicate("(?P<x>b)?", size) <> "a"
      template = ~s/{{regexReplaceAll "#{pattern}" "a" "$x"}}/
      expression = ~s/{service="replace-limit"} | / <> stage <> Pulse.JSON.encode!(template)
      assert {:ok, ast} = Parser.parse(expression)
      result = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

      if size == 14 do
        assert {:ok, [{labels, [{10, output}]}]} = result
        assert output == if(stage == "line_format ", do: "", else: line)
        if stage == "label_format out=", do: assert(labels["out"] == "")
      else
        assert {:error, :query_work_limit} = result
        assert {:error, :query_work_limit} = run("bytes_over_time(#{expression} [1m])")
        assert {:error, :query_work_limit} = run(~s'bytes_over_time(#{expression} | __error__!="" [1m])')
      end
    end

    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 11, service: "replace-limit", body: line},
               %Log{timestamp_ns: 12, service: "replace-limit", body: line}
             ])

    for function <- ["regexReplaceAll", "regexReplaceAllLiteral"] do
      template = ~s/{{#{function} "a" (__line__) "x"}}/
      assert {:ok, ast} = Parser.parse(~s/{service="replace-limit"} | line_format / <> Pulse.JSON.encode!(template))
      assert {:error, :query_work_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 12})
    end
  end

  @tag :template_integer_math_batch
  test "arithmetic expansion counts retain the same fail-whole output cap" do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "math-limit", body: "%"}])
    template = "{{repeat (mul 4096 4096) (__line__)}}"
    assert {:ok, ast} = Parser.parse(~s/{service="math-limit"} | line_format / <> Pulse.JSON.encode!(template))
    assert {:ok, [{_labels, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    assert output == String.duplicate("%", 16_777_216)

    template = "{{repeat (add (mul 4096 4096) 1) (__line__)}}"

    for stage <- ["line_format ", "label_format out="] do
      expression = ~s/{service="math-limit"} | / <> stage <> Pulse.JSON.encode!(template) <> ~s/ | __error__!=""/
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end
  end

  @tag :template_conditionals_batch
  test "conditional branches share one output cap and skipped expressions cannot consume it" do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "conditional-limit", body: "%"}])
    prefix = "{{repeat 8388608 (__line__)}}"
    body = prefix <> "{{if true}}" <> prefix <> "{{else}}unused{{end}}"
    assert {:ok, ast} = Parser.parse(~s/{service="conditional-limit"} | line_format / <> Pulse.JSON.encode!(body))
    assert {:ok, [{_labels, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    assert output == String.duplicate("%", 16_777_216)

    for stage <- ["line_format ", "label_format out="] do
      expression =
        ~s/{service="conditional-limit"} | / <> stage <> Pulse.JSON.encode!(body <> "!") <> ~s/ | __error__!=""/

      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end

    for template <- [
          ~s'{{if false}}{{repeat 9223372036854775807 (__line__)}}{{else}}safe{{end}}',
          ~s'{{or "safe" (repeat 9223372036854775807 (__line__))}}'
        ] do
      assert {:ok, ast} = Parser.parse(~s/{service="conditional-limit"} | line_format / <> Pulse.JSON.encode!(template))
      assert {:ok, [{_, [{10, "safe"}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    end

    template = ~s'{{if repeat 16777217 (__line__)}}safe{{end}}'
    assert {:ok, ast} = Parser.parse(~s/{service="conditional-limit"} | line_format / <> Pulse.JSON.encode!(template))
    assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
  end

  @tag :template_whitespace_batch
  test "delimiter trimming cannot erase rendered spaces or hide output overflow" do
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "trim-limit", body: " "}])
    body = "{{/* {{repeat 9223372036854775807 (__line__)}} */}}{{- repeat 16777216 (__line__) -}}"
    template = body <> " \t{{- \"\" -}}\n"
    assert {:ok, ast} = Parser.parse(~s/{service="trim-limit"} | line_format / <> Pulse.JSON.encode!(template))
    assert {:ok, [{_labels, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    assert output == String.duplicate(" ", 16_777_216)

    for stage <- ["line_format ", "label_format out="] do
      expression =
        ~s/{service="trim-limit"} | / <>
          stage <> Pulse.JSON.encode!(body <> " \n{{- \"!\" -}}\n") <> ~s/ | __error__!=""/

      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end
  end

  @tag :template_index_batch
  test "root map rendering enforces the output cap before later labels are dropped" do
    value = String.duplicate("x", 16_777_215)
    record = %Log{timestamp_ns: 10, service: "index-limit", body: "original", resource: %{"large" => value}}
    assert :ok = Storage.append(:logs, "acme", [record])

    assert {:ok, control} = Parser.parse(~s/{service="index-limit"} | line_format "{{len .}}" | drop large/)
    assert {:ok, [{_labels, [{10, "3"}]}]} = Evaluator.evaluate_log(control, "acme", %{end_ts_ns: 10})

    for stage <- ["line_format ", "label_format out="] do
      expression = ~s/{service="index-limit"} | / <> stage <> ~s/"{{index .}}" | drop large | __error__!=""/
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end
  end

  @tag :template_integer_functions_batch
  test "integer formatters check expanded byte sizes before allocation or an outer trim" do
    cap = 16_777_216
    pad = String.duplicate(" ", 5_592_403)

    cases = [
      {"repeat", "%", "{{repeat 16777216 (__line__)}}", "{{repeat 16777217 (__line__)}}", String.duplicate("%", cap)},
      {"indent", "a\nbcd\n!", "{{indent 5592403 (__line__)}}", "{{indent 5592404 (__line__)}}",
       pad <> "a\n" <> pad <> "bcd\n" <> pad <> "!"},
      {"nindent", "a\nbc\n!", "{{nindent 5592403 (__line__)}}", "{{nindent 5592404 (__line__)}}",
       "\n" <> pad <> "a\n" <> pad <> "bc\n" <> pad <> "!"},
      {"left", "é", "{{alignLeft 16777215 (__line__)}}", "{{alignLeft 16777216 (__line__)}}",
       "é" <> String.duplicate(" ", cap - 2)},
      {"right", "é", "{{alignRight 16777215 (__line__)}}", "{{alignRight 16777216 (__line__)}}",
       String.duplicate(" ", cap - 2) <> "é"},
      {"counted", String.duplicate("%", 524_288), ~s'{{Replace "................................" "." (__line__) 32}}',
       ~s'{{Replace "................................." "." (__line__) 33}}', String.duplicate("%", cap)}
    ]

    for {service, line, fits, oversized, expected} <- cases do
      assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: service, body: line}])
      selector = ~s/{service="#{service}"}/
      assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(fits))
      assert {:ok, [{_labels, [{10, ^expected}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
      assert byte_size(expected) == cap

      oversized = String.replace_suffix(oversized, "}}", ~S' | trimAll " %éabcd!\n"}}')

      for stage <- ["line_format ", "label_format out="] do
        expression = selector <> " | " <> stage <> Pulse.JSON.encode!(oversized) <> ~s' | __error__!=""'
        assert {:ok, ast} = Parser.parse(expression)

        for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
          assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
        end

        assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
      end
    end

    # Count bounds are not output bounds: empty repeats with a maximum count
    # succeed, but a maximum count over a nonempty value must reject immediately.
    for template <- [
          "{{repeat 9223372036854775807 (__line__)}}",
          "{{indent 9223372036854775807 (__line__)}}",
          "{{alignLeft 9223372036854775807 (__line__)}}"
        ] do
      assert {:ok, ast} = Parser.parse(~s/{service="repeat"} | line_format / <> Pulse.JSON.encode!(template))
      assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    end
  end

  @tag :template_string_transforms_batch
  @tag :template_with_batch
  @tag :template_variables_batch
  @tag :template_nested_bindings_batch
  @tag :template_field_chains_batch
  @tag :template_range_batch
  test "replacement and encoders bound intermediate output before an outer trim can hide it" do
    cases = [
      {"replacement", String.duplicate("%", 524_288), ~s'{{replace "." (__line__) "................................"}}',
       String.duplicate("%", 16_777_216)},
      {"base64", String.duplicate("%", 12_582_912), "{{__line__ | b64enc}}", String.duplicate("JSUl", 4_194_304)},
      {"url", String.duplicate("%", 5_592_405) <> "x", "{{__line__ | urlencode}}",
       String.duplicate("%25", 5_592_405) <> "x"},
      {"html", String.duplicate("&", 3_355_443) <> "x", "{{__line__ | html}}",
       String.duplicate("&amp;", 3_355_443) <> "x"},
      {"js", String.duplicate("&", 2_796_202) <> "xxxx", "{{__line__ | js}}",
       String.duplicate("\\u0026", 2_796_202) <> "xxxx"},
      {"urlquery", String.duplicate("%", 5_592_405) <> "x", "{{__line__ | urlquery}}",
       String.duplicate("%25", 5_592_405) <> "x"},
      {"print", String.duplicate("x", 8_388_608), "{{print (__line__) (__line__)}}", String.duplicate("x", 16_777_216)},
      {"println", String.duplicate("x", 8_388_607), "{{println (__line__) (__line__)}}",
       String.duplicate("x", 8_388_607) <> " " <> String.duplicate("x", 8_388_607) <> "\n"}
    ]

    for {service, line, template, expected} <- cases do
      assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: service, body: line}])
      selector = ~s/{service="#{service}"}/
      assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(template))
      assert {:ok, [{_labels, [{10, ^expected}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

      # Add one source byte, then shrink the potential output below the cap.
      # The intermediate still must fail, even if errors are kept.
      template =
        String.replace_suffix(
          template,
          "}}",
          ~s' | trimAll "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%+/=!"}}'
        )

      for stage <- ["line_format ", "label_format out="] do
        expression =
          selector <>
            ~s' | line_format "{{__line__}}!" | ' <>
            stage <>
            Pulse.JSON.encode!(template) <> ~s' | __error__!=""'

        assert {:ok, ast} = Parser.parse(expression)

        for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
          assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
        end

        assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
      end
    end

    template = ~s'{{replace "" (__line__) "................................" | trimAll "%."}}'

    expression =
      ~s'{service="replacement"} | line_format ' <> Pulse.JSON.encode!(template)

    assert {:ok, ast} = Parser.parse(expression)
    assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})

    # Branches and bindings share the surrounding output counter. A later
    # formatter cannot conceal overflow, nor can an unused initializer.
    for template <- [
          "{{__line__}}{{with (__line__)}}{{.}}{{end}}",
          "{{$x := __line__}}{{$x}}{{if $y := $x}}{{$y}}{{end}}",
          "{{print ($x := __line__) $x}}",
          "{{range 2}}{{__line__}}{{end}}"
        ] do
      selector = ~s/{service="print"}/
      assert {:ok, ast} = Parser.parse(selector <> " | line_format " <> Pulse.JSON.encode!(template))
      assert {:ok, [{_, [{10, output}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
      assert output == String.duplicate("x", 16_777_216)

      for stage <- ["line_format ", "label_format out="] do
        expression =
          selector <>
            ~s' | line_format "{{__line__}}!" | ' <>
            stage <>
            Pulse.JSON.encode!(template) <>
            " | line_format " <> Pulse.JSON.encode!(~s'{{__line__ | trimAll "x!"}}') <> ~s' | __error__!=""'

        assert {:ok, ast} = Parser.parse(expression)

        for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
          assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
        end

        assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
      end
    end

    for template <- [
          ~s'{{$unused := repeat 16777217 "x"}}ok',
          ~s'{{default "ok" (and ($unused := repeat 16777217 "x") false)}}',
          ~s'{{($unused := repeat 16777217 "x").field}}'
        ],
        stage <- ["line_format ", "label_format out="] do
      expression = ~s'{service="print"} | ' <> stage <> Pulse.JSON.encode!(template) <> ~s' | __error__!=""'
      assert {:ok, ast} = Parser.parse(expression)

      for opts <- [%{end_ts_ns: 10}, %{end_ts_ns: 10, limit: 1}] do
        assert {:error, :query_result_limit} = Evaluator.evaluate_log(ast, "acme", opts)
      end

      assert {:error, :query_result_limit} = run("bytes_over_time(#{expression} [1m])")
    end

    # Admission sees the declaration, but lazy execution must not allocate it.
    for {template, expected} <- [
          {~s'{{or true ($unused := repeat 16777217 "x")}}', "true"},
          {~s'{{(and nil true).field (repeat 16777217 "x")}}', "<no value>"}
        ] do
      expression = ~s'{service="print"} | line_format ' <> Pulse.JSON.encode!(template)
      assert {:ok, ast} = Parser.parse(expression)
      assert {:ok, [{_, [{10, ^expected}]}]} = Evaluator.evaluate_log(ast, "acme", %{end_ts_ns: 10})
    end
  end

  test "selectors share retained log sample and work quotas, not the PromQL sample quota" do
    config = Runtime.get_env(:pulse, Budget, [])
    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_samples, 1))
    assert {:ok, _} = run(~s'count_over_time({service="api"}[1m])')

    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_log_samples, 5))

    assert {:error, :query_sample_limit} =
             run(~s'count_over_time({service="api"}[1m]) + count_over_time({service="api"}[1m])')

    Runtime.put_env(:pulse, Budget, Keyword.put(config, :max_work, 8))

    assert {:error, :query_work_limit} =
             run(~s'count_over_time({service="api"}[1m])', %{start_ts_ns: 10, end_ts_ns: 12, step_ns: 1})
  end
end
