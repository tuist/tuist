# Optional development oracle runner. Tests read its pinned output and never
# require an external runtime. The supplied reference binary must use the
# documented pinned Grafana parser and IEEE/union semantics, not Pulse code.
[oracle, output] = System.argv()
values = ["-Inf", "-1", "-0", "0", "1", "+Inf", "NaN", nil]
scalar = fn value -> %{"kind" => "scalar", "frames" => [%{"labels" => %{}, "value" => value}]} end

binary =
  for op <- ~w(+ - * / % ** == != < > <= >= && ||), a <- values, b <- values do
    %{
      "name" => "#{inspect(a)} #{op} #{inspect(b)}",
      "expression" => "$A #{op} $B",
      "inputs" => %{"A" => scalar.(a), "B" => scalar.(b)}
    }
  end

unary =
  for op <- ["-", "!"], a <- values do
    %{"name" => "#{op}#{inspect(a)}", "expression" => "#{op}$A", "inputs" => %{"A" => scalar.(a)}}
  end

syntax =
  for expr <- [
        "1+2*3",
        "2**3**2",
        "-2**2",
        "(-2)**2",
        "010",
        "08",
        ".5",
        "1.",
        "1.e2",
        "$A > 2.5 && $B > 100",
        "$A > 10 && $B > 300 && $D >= 10",
        "${executions} >= ${threshold}"
      ] do
    inputs = %{
      "A" => scalar.("11"),
      "B" => scalar.("400"),
      "D" => scalar.("10"),
      "executions" => scalar.("3"),
      "threshold" => scalar.("2")
    }

    %{"name" => expr, "expression" => expr, "inputs" => inputs}
  end

set = fn items ->
  %{"kind" => "numbers", "frames" => Enum.map(items, fn {labels, value} -> %{"labels" => labels, "value" => value} end)}
end

joins =
  for {a, b} <- [
        {[
           {%{"pod" => "one", "region" => "eu"}, "8"},
           {%{"pod" => "two", "region" => "eu"}, "12"},
           {%{"pod" => "three", "region" => "us"}, "6"}
         ], [{%{"region" => "eu"}, "2"}]},
        {[{%{"pod" => "one"}, "8"}], [{%{"zone" => "two"}, "2"}]},
        {[{%{}, "8"}], [{%{"pod" => "one"}, "2"}, {%{"pod" => "two"}, "3"}]},
        {[{%{"pod" => "one"}, "8"}, {%{"pod" => "two"}, "2"}], [{%{"pod" => "one"}, "2"}, {%{"pod" => "three"}, "3"}]},
        {[], [{%{}, "1"}]},
        {[{%{}, "1"}], []},
        {[{%{"a" => "1"}, "8"}, {%{"b" => "2"}, "9"}], [{%{"a" => "1", "b" => "2"}, "2"}]},
        {[{%{}, "2"}, {%{}, "3"}], [{%{}, "4"}, {%{}, "5"}]}
      ],
      op <- ["+", "-", ">", "&&"] do
    %{
      "name" => "union #{op} #{inspect({a, b})}",
      "expression" => "$A #{op} $B",
      "inputs" => %{"A" => set.(a), "B" => set.(b)}
    }
  end

int64 = fn value ->
  %{"kind" => "scalar", "frames" => [%{"labels" => %{}, "value" => nil, "int64" => Integer.to_string(value)}]}
end

precision =
  for {a, b} <- [
        {9_007_199_254_740_993, 9_007_199_254_740_992},
        {9_223_372_036_854_775_807, 9_223_372_036_854_775_806},
        {-9_223_372_036_854_775_808, -9_223_372_036_854_775_807},
        {576_460_752_303_423_553, 576_460_752_303_423_552}
      ],
      op <- ["-", ">", "=="] do
    %{"name" => "i64 #{a} #{op} #{b}", "expression" => "$A #{op} $B", "inputs" => %{"A" => int64.(a), "B" => int64.(b)}}
  end

cases = binary ++ unary ++ syntax ++ joins ++ precision
input = Path.join(System.tmp_dir!(), "pulse-expression-cases-#{System.unique_integer([:positive])}.json")

try do
  File.write!(input, Pulse.JSON.encode!(cases))
  {json, 0} = System.cmd(Path.expand(oracle), [input], stderr_to_stdout: true)
  generated = Pulse.JSON.decode!(json)

  File.write!(
    output,
    Pulse.JSON.encode!(%{
      "reference" => "Grafana v12.3.0 parser with extracted IEEE operators and label-union reference",
      "cases" => generated
    })
  )

  IO.puts("Wrote #{length(generated)} independent reference cases; not deployed Grafana 13.3 acceptance.")
after
  File.rm(input)
end
