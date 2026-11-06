defmodule Pulse.PromQL.ParserTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Formatter
  alias Pulse.PromQL.Parser
  alias Pulse.Runtime.Task

  @tag :label_replace_regex_error
  test "label_replace retains bounded rejected regexes after destination validation" do
    assert Parser.parse(~s|label_replace(series, "export", "$1", "label", "[.*")|) ==
             {:error, {:invalid_label_replace_regex, "[.*"}}

    assert Parser.parse(~s|label_replace(series, "", "$1", "label", "[.*")|) ==
             {:error, :invalid_label_replace}

    regex = String.duplicate("a", 1024) <> "["

    assert Parser.parse(~s|label_replace(series, "export", "$1", "label", #{JSON.encode!(regex)})|) ==
             {:error, :invalid_label_replace}
  end

  test "histogram trims share comparison precedence and survive formatter round trips" do
    for query <- [
          "h </ 1 + 2 * 3",
          "h >/ -Inf </ +Inf",
          "h </ 1 == h",
          "h </ (1 < bool 2)",
          "h >/ on(job) group_left(owner) cutoff",
          "h </ ignoring(instance) cutoff",
          "cutoff >/ on(job) group_right(owner) h",
          "histogram_count(last_over_time((h </ 2)[1m:10s]))",
          "h </ (cutoff >/ 1)"
        ] do
      assert {:ok, expression} = Parser.parse(query), query
      assert {:ok, formatted} = Formatter.format(query)
      assert Parser.parse(formatted) == {:ok, expression}, formatted
      assert Formatter.format(formatted) == {:ok, formatted}
    end

    assert Parser.parse("h >/ 1 </ 2") == Parser.parse("(h >/ 1) </ 2")
    assert Parser.parse("h </ 1 + 2 * 3") == Parser.parse("h </ (1 + (2 * 3))")
    assert Parser.parse("h </ 1 == h") == Parser.parse("(h </ 1) == h")

    for query <- ["1 </ 2", "1 >/ 2", "h </ bool 2", "h >/ bool 2", "h </", "h >/ on(job,job) cutoff"],
        do: assert({:error, _} = Parser.parse(query), query)
  end

  test "time modifiers normalize both orders and preserve exact timestamps when formatted" do
    for inner <- ["metric", "sum_over_time(metric[1.25])", "sum_over_time(metric[60:0.25])"],
        anchor <- ["123.000000001", "start()", "end()"] do
      # Apply modifiers to the selector/window rather than its function.
      query = if inner == "metric", do: "metric", else: String.trim_trailing(inner, ")")
      close = if inner == "metric", do: "", else: ")"
      left = query <> " @ #{anchor} offset -0.000000001" <> close
      right = query <> " offset -0.000000001 @ #{anchor}" <> close
      assert {:ok, expression} = Parser.parse(left)
      assert Parser.parse(right) == {:ok, expression}
      assert {:ok, formatted} = Formatter.format(right)
      assert Parser.parse(formatted) == {:ok, expression}
      assert Formatter.format(formatted) == {:ok, formatted}
    end

    for {text, ns} <- [
          {"-9223372036.854775808", -9_223_372_036_854_775_808},
          {"9223372036.854775807", 9_223_372_036_854_775_807},
          {"1790000000.000000001", 1_790_000_000_000_000_001},
          {"1_790_000_000.000_000_001", 1_790_000_000_000_000_001},
          {"0X_10", 16_000_000_000},
          {"-0xA", -10_000_000_000},
          {"0_20", 16_000_000_000},
          {"-0.000000001", -1},
          {"010", 8_000_000_000},
          {"-010", -8_000_000_000},
          {"1e-9", 1}
        ] do
      assert {:ok, {:selector, _, {:at, ^ns, 0}} = expression} = Parser.parse("metric @ #{text}")
      assert {:ok, formatted} = Formatter.format("metric @ #{text}")
      assert Parser.parse(formatted) == {:ok, expression}
    end

    for {text, ns} <- [{"600", 600_000_000_000}, {".25", 250_000_000}, {"1e-9", 1}, {"010", 8_000_000_000}] do
      assert Parser.parse_duration(text) == {:ok, ns}
      assert {:ok, {:selector, _, shift}} = Parser.parse("metric offset -#{text}")
      assert shift == -ns
    end
  end

  test "time modifiers reject duplicates, nonfinite anchors and unbounded durations" do
    for query <- [
          "metric @ 1 @ 2",
          "metric offset 1s offset 2s",
          "metric @ end() offset 1s @ start()",
          "metric @ time()",
          "metric @ (1 + 2)",
          "metric @ NaN",
          "metric @ Inf",
          "metric @ 1e300",
          "metric @ 9223372036.854775808",
          "metric @ -9223372036.854775809",
          "metric @ 0x10_",
          "metric offset --1m",
          "metric offset 31536001",
          "metric offset 1e300",
          "metric offset 0#{String.duplicate("7", 127)}",
          "metric @ #{String.duplicate("0", 129)}",
          "sum_over_time(metric[0])",
          "sum_over_time(metric[-1])",
          "sum_over_time(metric[1:0])",
          "sum_over_time(metric[1:-1])",
          "sum_over_time(metric[1::])",
          "sum(metric) @ 10",
          "vector(1) offset -1s"
        ],
        do: assert({:error, _} = Parser.parse(query), query)

    for value <- ["0", "-1", "0.0000000001", "31536000.000000001", "1e300"],
        do: assert({:error, _} = Parser.parse_duration(value))
  end

  test "quoted label lists and omitted resolutions survive formatting without changing identity" do
    for name <- ["zone😀", "owner name", "instance.id", "a:b", "quote\" slash\\", "job"],
        query <- [
          "sum by (#{Pulse.JSON.encode!(name)},) (x)",
          "count_values without (#{Pulse.JSON.encode!(name)}) (\"value\",x)",
          "x / on (#{Pulse.JSON.encode!(name)},) y",
          "x + ignoring (#{Pulse.JSON.encode!(name)}) y",
          "x * on (key) group_left (#{Pulse.JSON.encode!(name)},) y",
          "x / on (key) group_right (#{Pulse.JSON.encode!(name)}) y"
        ] do
      assert {:ok, expr} = Parser.parse(query)
      assert {:ok, formatted} = Formatter.format(query)
      assert Parser.parse(formatted) == {:ok, expr}
      assert Formatter.format(formatted) == {:ok, formatted}
    end

    for query <- [
          "sum_over_time(x[130:])",
          "sum_over_time(x[step()+10: ] offset -0xA @ end())",
          "sum_over_time(sum_over_time(x[130:])[0xA:])",
          "x offset (1_0+0xA)"
        ] do
      assert {:ok, expr} = Parser.parse(query)
      assert {:ok, formatted} = Formatter.format(query)
      assert Parser.parse(formatted) == {:ok, expr}
      assert Formatter.format(formatted) == {:ok, formatted}
    end

    for value <- ["0x10", "1_0", "(10+20)", "step()"] do
      assert {:error, :invalid_duration} = Parser.parse_duration(value)
    end

    for query <- [
          ~S|sum by ("\x80") (x)|,
          ~S|x + on ("\uD800") y|,
          ~s|x * on (key) group_left ("") y|,
          ~s|sum by ("",) (x)|
        ] do
      assert {:error, _} = Parser.parse(query)
    end
  end

  test "duration expressions and scalar durations retain precedence when formatted" do
    for query <- [
          "1h30m + 2.5",
          "vector(-2m^2)",
          "sum_over_time(x[26m+4m])",
          "sum_over_time(x[1h30m % 1h])",
          "sum_over_time(x[2m*(10+5)])",
          "sum_over_time(x[-5m+35m])",
          "sum_over_time(x[step()+1ms])",
          "sum_over_time(x[min_of(range(),max_of(step(),1s))])",
          "sum_over_time(x[1s+29s:step()/2] offset -(step()+1))",
          "x offset step()^0",
          "x offset (-2^2)",
          "x offset -(2^2)",
          "x offset (2^3^2)",
          "x offset ((-2)^2)",
          "x offset min_of(1s,step())+2",
          "x offset (0.6e-9+0.6e-9) @ start()"
        ] do
      assert {:ok, expression} = Parser.parse(query), query
      assert {:ok, formatted} = Formatter.format(query), query
      assert Parser.parse(formatted) == {:ok, expression}, formatted
      assert Formatter.format(formatted) == {:ok, formatted}
    end

    assert Parser.parse("sum_over_time(x[STep()+RANGE()])") == Parser.parse("sum_over_time(x[step()+range()])")
    assert {:ok, {:scalar, 5400.0}} = Parser.parse("1h30m")
    assert {:ok, _} = Parser.parse("predict_linear(x[1m], 2h)")
  end

  test "duration expressions reject data-dependent syntax and share the query expression ceiling" do
    for duration <- ["time()", "start()", "end()", "scalar(x)", "x", "vector(1)", "1 > 0", "NaN", "Inf", ~s("1")],
        query <- ["sum_over_time(x[#{duration}])", "x offset (#{duration})", "sum_over_time(x[1:#{duration}])"],
        do: assert({:error, _} = Parser.parse(query), query)

    for query <- [
          "sum_over_time(x[" <> Enum.join(List.duplicate("1", 130), "+") <> "])",
          "x offset (" <> Enum.join(List.duplicate("1", 130), "+") <> ")",
          "sum_over_time(x[" <> String.duplicate("step()+(", 70) <> "1" <> String.duplicate(")", 70) <> "])"
        ],
        do: assert({:error, :query_expression_limit} = Parser.parse(query))

    # Request step/lookback values are literal durations, not PromQL programs.
    for duration <- ["1s+2s", "step()", "(1s)", "min_of(1s,2s)"],
        do: assert({:error, :invalid_duration} = Parser.parse_duration(duration))
  end

  test "sampling aggregations require scalar parameters and preserve grouping when formatted" do
    for name <- ~w(limitk limit_ratio),
        query <- [
          "#{name}(scalar(k), metric)",
          "#{name} by(job)(1.5, metric)",
          "#{name}(-0.5, metric) without(instance)"
        ] do
      assert {:ok, expression} = Parser.parse(query)
      assert Parser.type(expression) == :vector
      assert Parser.parse(String.replace(query, name, String.upcase(name))) == {:ok, expression}
      assert {:ok, formatted} = Formatter.format(query)
      assert Parser.parse(formatted) == {:ok, expression}
    end

    for name <- ~w(limitk limit_ratio),
        arguments <- ["", "metric", "1, 2", "metric, metric", ~s("1", metric), "1, metric[1m]", "1, metric, 2"],
        do: assert({:error, _} = Parser.parse("#{name}(#{arguments})"))

    for query <- ["limitk by(job,job)(1, metric)", "limit_ratio by(job)(0.5, metric) without(instance)"],
        do: assert({:error, _} = Parser.parse(query))
  end

  test "dispersion, quantile and value-count aggregations validate their parameter and grouping types" do
    for name <- ~w(stddev stdvar),
        query <- ["#{name}(metric)", "#{name} by (job)(metric)", "#{name}(metric) without(instance)"] do
      assert {:ok, expression} = Parser.parse(query)
      assert Parser.type(expression) == :vector
      assert Parser.parse(String.replace(query, name, String.upcase(name))) == {:ok, expression}
    end

    for query <- [
          "quantile(scalar(q), metric)",
          ~s|count_values(((("值😀"))), metric)|,
          ~s|count_values by(job)("job", metric)|,
          ~s|count_values("__name__", metric) without(instance)|
        ] do
      assert {:ok, expression} = Parser.parse(query)
      assert Parser.type(expression) == :vector
      assert {:ok, formatted} = Formatter.format(query)
      assert {:ok, ^expression} = Parser.parse(formatted)
    end

    for query <- [
          ~s|quantile("q", metric)|,
          "quantile(metric, metric)",
          "quantile(0.5, metric[5m])",
          "count_values(1, metric)",
          ~s|count_values("", metric)|,
          ~s|count_values("v", 1)|,
          "stddev(metric[5m])",
          "stdvar(1)",
          "stddev by(job,job)(metric)",
          ~s("literal" + metric)
        ] do
      assert {:error, _} = Parser.parse(query)
    end
  end

  test "query-context functions and scalar extrema enforce scalar arguments and result types" do
    for name <- ~w(start end step range) do
      assert {:ok, expression} = Parser.parse("#{name}()")
      assert Parser.type(expression) == :scalar

      for argument <- ["1", "metric", ~s("text")],
          do: assert({:error, _} = Parser.parse("#{name}(#{argument})"))
    end

    for name <- ~w(min_of max_of) do
      assert {:ok, expression} = Parser.parse("#{name}(start(), scalar(metric))")
      assert Parser.type(expression) == :scalar

      for arguments <- ["", "1", "1, 2, 3", "metric, 1", "1, metric", "metric[5m], 1", ~s(1, "text")],
          do: assert({:error, _} = Parser.parse("#{name}(#{arguments})"))
    end

    assert {:error, _} = Parser.parse("sum_over_time(step()[5m:1m])")
  end

  test "matcher counts and pattern sizes are bounded before native compilation" do
    matchers = Enum.map_join(1..65, ",", &~s(a#{&1}="x"))
    assert {:error, _} = Parser.parse("m{" <> matchers <> "}")
    assert {:error, _} = Parser.parse(~s(m{job=~"#{String.duplicate("a", 1025)}"}))

    quoted_matchers = Enum.map_join(1..64, ",", &~s("label😀#{&1}"="x"))
    assert {:ok, _} = Parser.parse("{" <> quoted_matchers <> "}")
    assert {:error, _} = Parser.parse(~s({"metric😀",#{quoted_matchers}}))
    assert {:error, _} = Parser.parse(~s({"label😀"=~"#{String.duplicate("a", 1025)}"}))
  end

  test "unclosed nested aggregations cannot backtrack exponentially" do
    supervisor = start_supervised!({Task.Supervisor, []})

    for prefix <- [
          "sum(",
          "topk(1,",
          "stddev(",
          "quantile(0.5,",
          ~s|count_values("v",|,
          "limitk(1,",
          "limit_ratio(0.5,"
        ],
        depth <- [20, 30, 100] do
      task = Task.Supervisor.async_nolink(supervisor, fn -> Parser.parse(String.duplicate(prefix, depth) <> "x") end)
      assert {:ok, {:error, _}} = Task.yield(task, 1000)
    end

    for prefix <- ["(", "min_of(1,"], depth <- [20, 30, 100] do
      query = "sum_over_time(x[" <> String.duplicate(prefix, depth) <> "1"
      task = Task.Supervisor.async_nolink(supervisor, fn -> Parser.parse(query) end)
      assert {:ok, {:error, _}} = Task.yield(task, 1000)
    end
  end

  test "Prometheus keywords are case insensitive while label identifiers retain case" do
    for {upper, lower} <- [
          {"SUM BY(job)(a)", "sum by(job)(a)"},
          {"TOPK(1,a)", "topk(1,a)"},
          {"a AND ON(job) b", "a and on(job) b"},
          {"a > BOOL 1", "a > bool 1"},
          {"a OFFSET 1m", "a offset 1m"},
          {"a / ON(job) GROUP_LEFT(region) b", "a / on(job) group_left(region) b"}
        ] do
      assert Parser.parse(upper) == Parser.parse(lower)
    end

    assert {:ok, {:selector, [_, {"Job", :eq, "API"}], 0}} = Parser.parse(~s|a{Job="API"}|)
  end

  test "mutated untrusted input always returns a parse result" do
    :rand.seed(:exsss, {11, 37, 91})

    seeds = [
      ~s|sum by(job) (rate(m{job=~"api.*"}[5m]))|,
      "m offset 1h",
      "# comment\nm",
      ~S({"metric😀","label😀"="test"})
    ]

    for seed <- seeds, _ <- 1..100 do
      position = :rand.uniform(byte_size(seed)) - 1
      <<prefix::binary-size(^position), _byte, suffix::binary>> = seed
      query = prefix <> <<:rand.uniform(256) - 1>> <> suffix
      assert {status, _} = Parser.parse(query)
      assert status in [:ok, :error]
    end
  end

  test "aggregations ignore case and whitespace may include comments" do
    assert Parser.parse("SUM(m)") == Parser.parse("sum(m)")
    assert Parser.parse("sUm( # aggregate\n m) # trailing") == Parser.parse("sum(m)")
    assert {:ok, _} = Parser.parse(~s(m{job="#literal"}))
  end

  test "named selectors and offsets, grouped nested rate expressions" do
    assert {:ok, {:selector, [{"__name__", :eq, "requests_total"}, {"job", :eq, "api"}], 60_000_000_000}} =
             Parser.parse(~s(requests_total{job="api"} offset 1m))

    assert {:ok, {:aggregate, :sum, {:grouping, :by, ["job"]}, {:function, :rate, {:range, _, 300_000_000_000, 0}}}} =
             Parser.parse("sum by (job) (rate(requests_total[5m]))")

    assert {:ok, {:aggregate, :avg, {:grouping, :without, ["instance"]}, _}} =
             Parser.parse("avg(requests_total) without (instance)")

    assert {:ok, _} = Parser.parse(~s({__name__=~"requests_.+",job!="",}))
    assert {:ok, {:selector, [{"__name__", :eq, ":requests_total"}], 0}} = Parser.parse(":requests_total")
  end

  test "rejects invalid selectors, ranges, and unsupported syntax" do
    for query <- [
          "",
          "{}",
          ~s({job=~".*"}),
          ~s({job=~"["}),
          "rate(x[0s])",
          "rate(x[1m1h])",
          "rate(x[1.5h])",
          "sum by (a) (x) without (b)",
          "x[5m] + x",
          "rate(x[5m]) trailing",
          "rate(x[5m::])",
          "predict_linear(x, 60)",
          "predict_linear(x[5m], x)",
          "sum_over_time(vector(1)[5m:0s])",
          "sum_over_time(time()[5m:1m])",
          "sum(x[5m:1m])",
          "x @ time()",
          "sumby(job)(x)",
          "x offset1m",
          "sum by(a,a)(x)"
        ] do
      assert {:error, _} = Parser.parse(query), query
    end
  end

  test "subqueries have positive explicit or default resolutions and typed range operands" do
    assert {:ok, {:call, "rate", [{:subquery, {:selector, _, 0}, 300_000_000_000, 60_000_000_000, 0}]}} =
             Parser.parse("rate(x[5m:1m])")

    assert {:ok, _} = Parser.parse("predict_linear((max by(job)(x))[3d:30m], 3*86400)")
    assert {:ok, _} = Parser.parse("sum_over_time((x-y)[6h:5m])")
    assert {:error, _} = Parser.parse("predict_linear(x[5m], vector(60))")
  end

  test "basic math functions require exactly one instant vector" do
    for name <- ~w(ceil sqrt exp ln log2 log10 deg rad asin acos atan sin cos tan sinh cosh tanh asinh acosh atanh) do
      assert {:ok, {:call, ^name, [_]}} = Parser.parse("#{name}(x)")
      assert {:ok, _} = Parser.parse("sum(#{name}(vector(2)))")

      for argument <- ["", "1", "x[5m]", "x, 1", ~s("x")] do
        assert {:error, _} = Parser.parse("#{name}(#{argument})")
      end
    end
  end

  test "pi is a zero-argument scalar usable in vector and scalar expressions" do
    assert {:ok, {:call, "pi", []} = expression} = Parser.parse("pi()")
    assert Parser.type(expression) == :scalar
    assert {:ok, _} = Parser.parse("deg(vector(pi()/2))")
    assert {:ok, _} = Parser.parse("pi() + time()")

    for argument <- ["1", "x", "x[5m]", ~s("pi")] do
      assert {:error, _} = Parser.parse("pi(#{argument})")
    end

    assert {:error, _} = Parser.parse("rad(pi())")
  end

  test "calendar functions accept an optional instant vector, never a scalar or range" do
    for name <- ~w(year month day_of_month day_of_week day_of_year days_in_month hour minute) do
      for arguments <- ["", "x", "vector(time())"],
          do: assert({:ok, _} = Parser.parse("#{name}(#{arguments})"))

      for arguments <- ["1", "x[5m]", "x, x", ~s("x")],
          do: assert({:error, _} = Parser.parse("#{name}(#{arguments})"))
    end
  end

  test "label sorting accepts a vector and any number of string label names" do
    for name <- ~w(sort_by_label sort_by_label_desc) do
      for arguments <- ["x", ~s(x, "instance"), ~s(x, "zone", "instance")],
          do: assert({:ok, _} = Parser.parse("#{name}(#{arguments})"))

      for arguments <- ["", "1", "x[5m]", "x, 1", "x, x"],
          do: assert({:error, _} = Parser.parse("#{name}(#{arguments})"))
    end
  end

  test "atan2 shares multiplication precedence and vector matching, with a keyword boundary" do
    assert {:ok, {:binary, "+", _, _, {:binary, "*", _, {:binary, "atan2", _, _, _}, _}}} =
             Parser.parse("1 + 2 atan2 3 * 4")

    assert Parser.parse("x ATAN2 ON(job) GROUP_LEFT(zone) y") ==
             Parser.parse("x atan2 on(job) group_left(zone) y")

    assert {:ok, _} = Parser.parse("x*atan2series")

    for query <- ["x atan2series", "x atan2 bool y", "1 atan2 on(job) x", "x atan2 y[5m]"],
        do: assert({:error, _} = Parser.parse(query))
  end

  test "quantile_over_time requires a scalar followed by a range vector" do
    for arguments <- ["0.75, x[1m] offset 10s", "scalar(q), (x[1m])", "NaN, (x + y)[5m:10s] offset 1m"] do
      assert {:ok, {:call, "quantile_over_time", [_, _]}} = Parser.parse("quantile_over_time(#{arguments})")
    end

    for arguments <- ["", "0.5", "0.5, x", "x, x[1m]", "x[1m], 0.5", "0.5, x[1m], 1", ~s("0.5", x[1m])] do
      assert {:error, _} = Parser.parse("quantile_over_time(#{arguments})")
    end
  end

  test "smoothing and its legacy alias require a range followed by two scalars" do
    for name <- ~w(double_exponential_smoothing holt_winters) do
      for arguments <- ["x[1m], 0.5, 0.25", "(x + y)[1m:2s] offset 10s, time()/40, scalar(tf)", "x[1m], NaN, NaN"] do
        assert {:ok, {:call, ^name, [_, _, _]}} = Parser.parse("#{name}(#{arguments})")
      end

      for arguments <- ["", "x[1m], 0.5", "x, 0.5, 0.25", "x[1m], sf, 0.25", "x[1m], 0.5, tf", "x[1m], 0.5, 0.25, 1"] do
        assert {:error, _} = Parser.parse("#{name}(#{arguments})")
      end
    end
  end

  test "label_join accepts a vector and variadic string sources with nonempty UTF-8 names" do
    for arguments <- [
          ~s(x, "dst", ","),
          ~s(x, "__name__", "", "job"),
          ~s|x, "合成😀", "-", "(source)", "source😀", "(source)"|,
          ~s|sum(x), "dst", "", "job"|
        ] do
      assert {:ok, {:call, "label_join", _}} = Parser.parse("label_join(#{arguments})")
    end

    for arguments <- [
          "",
          "x",
          ~s(x, "dst"),
          ~s(1, "dst", "-"),
          ~s(x[5m], "dst", "-"),
          ~s(x, 1, "-"),
          ~s(x, "dst", 1),
          ~s(x, "dst", "-", 1),
          ~s(x, "", "-", "src"),
          ~s(x, "dst", "-", "src", ""),
          ~S(x, "\x80", "-", "src"),
          ~S(x, "dst", "-", "\x80")
        ] do
      assert {:error, _} = Parser.parse("label_join(#{arguments})")
    end
  end

  test "clamp requires an instant vector and exactly two scalar bounds" do
    assert {:ok, {:call, "clamp", [_, _, _]}} = Parser.parse("clamp(x, -1, 2)")
    assert {:ok, _} = Parser.parse("clamp(x, scalar(low), time())")

    for arguments <- ["", "x", "x, 1", "x, 1, 2, 3", "1, 0, 2", "x[5m], 0, 2", "x, low, 2", "x, 0, high", ~s(x, 0, "2")] do
      assert {:error, :invalid_function_arguments} = Parser.parse("clamp(#{arguments})")
    end
  end

  test "range functions require one range vector or subquery" do
    for function <- [
          :present_over_time,
          :first_over_time,
          :last_over_time,
          :ts_of_first_over_time,
          :ts_of_last_over_time,
          :ts_of_min_over_time,
          :ts_of_max_over_time,
          :changes,
          :resets,
          :deriv,
          :mad_over_time
        ] do
      assert {:ok, {:function, ^function, {:range, _, 60_000_000_000, 10_000_000_000}}} =
               Parser.parse("#{function}(x[1m] offset 10s)")

      name = Atom.to_string(function)

      assert {:ok, {:call, ^name, [{:range, _, 60_000_000_000, 10_000_000_000}]}} =
               Parser.parse("#{function}(( (x[1m] offset 10s) ))")

      assert {:ok, _} = Parser.parse("sum(#{function}(rate(x[1m])[5m:10s]))")
      assert {:ok, _} = Parser.parse("sum(#{function}(rate(x[1m])[5m:]))")

      for argument <- [
            "",
            "1",
            "x",
            "vector(1)",
            "x[5m], 1",
            "(x[5m]) + 1",
            "x[0s]",
            "x[-600]",
            "x[5m] anchored",
            "rate(x[1m])[5m::]",
            ~s("x")
          ] do
        assert {:error, _} = Parser.parse("#{function}(#{argument})")
      end
    end
  end

  test "quoted matcher contents do not become syntax" do
    assert {:ok, {:selector, [_, {"job", :eq, "a\"}b"}], 0}} = Parser.parse(~S(x{job="a\"}b"}))
    assert {:ok, _} = Parser.parse(~S(x{job=~`api\d+`}))
    assert {:error, _} = Parser.parse(~S(x{job="\q"}))
  end

  test "quoted UTF8 metric and label names normalize to existing selector matchers" do
    for query <- [~s({"metric😀"}), ~s({'metric😀'}), "{`metric😀`}", ~S({"metric\U0001f600"})] do
      assert {:ok, {:selector, [{"__name__", :eq, "metric😀"}], 0}} = Parser.parse(query)
    end

    assert {:ok, {:selector, [{"__name__", :eq, "metric😀"}, {"label\"😀", :eq, "test"}], 0}} =
             Parser.parse(~S({"metric😀","label\"😀"="test",}))

    assert {:ok, {:selector, [{"label😀", :re, "te.*"}, {"__name__", :eq, "metric😀"}], 0}} =
             Parser.parse("{ 'label😀' =~ `te.*`, # metric follows\n `metric😀`, }")

    assert Parser.parse(~S(legacy{"label😀"!="other"})) == Parser.parse(~S({__name__="legacy","label😀"!="other"}))

    assert {:ok, {:function, :rate, {:range, [{"__name__", :eq, "metric😀"}], 300_000_000_000, 0}}} =
             Parser.parse(~s|rate({"metric😀"}[5m])|)
  end

  test "quoted names cannot conceal empty names, duplicate bare metrics or malformed selectors" do
    for query <- [
          ~S({""}),
          ~S({"",job="test"}),
          ~S({""="test"}),
          ~S({"metric😀","other"}),
          ~S(legacy{"metric😀"}),
          ~S({"metric😀" job="test"}),
          ~S({"metric😀",label😀="test"}),
          ~S(m{label:name="test"}),
          ~S({"metric😀","label😀"=}),
          ~S({"metric😀","label😀"="test}),
          ~S({"metric😀","label\q"="test"}),
          ~S({"metric😀","label\xff"="test"}),
          ~S({"metric\xff"}),
          ~S({"label😀"=~".*"}),
          "metric😀"
        ] do
      assert {:error, _} = Parser.parse(query), query
    end
  end

  test "escaped bytes and Unicode preserve matcher values without silent transcoding" do
    assert {:ok, {:selector, [_, {"job", :eq, "é"}], 0}} = Parser.parse(~S(x{job="\xc3\xa9"}))
    assert {:ok, {:selector, [_, {"job", :eq, "é"}], 0}} = Parser.parse(~S(x{job="\u00e9"}))
    assert {:ok, {:selector, [_, {"job", :eq, "é"}], 0}} = Parser.parse(~S(x{job="é"}))
    assert {:error, _} = Parser.parse(~S(x{job="\xff"}))
    assert {:error, _} = Parser.parse(~S(x{job="\777"}))
  end

  test "malformed regexes cannot use the anchoring wrapper to become valid" do
    for op <- ["=~", "!~"] do
      assert {:error, :invalid_selector} = Parser.parse(~s/x{job#{op}"a)|.*(?:"}/)
    end
  end

  test "the execution engine rejects unsupported regexes and excessive durations" do
    for op <- ["=~", "!~"] do
      assert {:error, _} = Parser.parse(~s/m{job#{op}"(?!api).*"}/)
      assert {:error, _} = Parser.parse(~S/m{job=~"(a)\\1"}/)
    end

    assert {:error, _} = Parser.parse("rate(m[300y])")
    assert {:error, _} = Parser.parse("m offset 999999999999999999y")
  end
end
