defmodule Pulse.LogQL.PatternFilterTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.Pipeline.Pattern
  alias Pulse.LogQL.QueryValidation
  alias Pulse.Record.Log
  alias Pulse.Storage

  defp matches?(pattern, line) do
    {:ok, parts} = Pattern.compile_filter(pattern)
    Pattern.filter_match?(parts, line)
  end

  test "matches as Loki's pattern line filter does" do
    refute matches?("<_> bar", "foo bar baz")
    assert matches?("<_> baz", "foo bar baz")
    assert matches?("foo <_>", "foo bar baz")
    refute matches?("<_> bar <_>", " bar ")
    assert matches?("<_>bar<_>", " bar ")
    assert matches?("<_> level=error <_>", "ts=1 level=error msg=x")
    refute matches?("<_> level=error <_>", "ts=1 level=info msg=x")
    refute matches?("foo", "foo bar")
    assert matches?("", "")
    refute matches?("<_>", "")
    assert matches?("a <b c> d", "a <b c> d")
  end

  test "rejects named and consecutive wildcards" do
    assert Pattern.compile_filter("<name> x") == {:error, :named_capture}
    assert Pattern.compile_filter("<_><_> x") == {:error, :consecutive_captures}

    assert {:error, {:invalid_pattern, :line_filter, :named_capture}} =
             Parser.parse(~s({app="a"} |> "<x>")) |> validate()
  end

  defp validate({:ok, ast}), do: QueryValidation.validate(ast)

  test "parses |> and !> and evaluates them in log and metric queries" do
    assert {:ok, %AST.LogQuery{stages: [first, second]}} =
             Parser.parse(~s({app="a"} |> "<_> error <_>" !> "<_> ignored <_>"))

    assert {first.op, second.op} == {:match_pattern, :not_match_pattern}

    tenant = "pattern-#{System.unique_integer([:positive])}"

    :ok =
      Storage.append(:logs, tenant, [
        %Log{timestamp_ns: 1_000, body: "a error b", service: "api", resource: %{}, attributes: %{}},
        %Log{timestamp_ns: 2_000, body: "a error ignored b", service: "api", resource: %{}, attributes: %{}},
        %Log{timestamp_ns: 3_000, body: "a info b", service: "api", resource: %{}, attributes: %{}}
      ])

    {:ok, query} = Parser.parse(~s({service_name="api"} |= "a" |> "<_> error <_>" !> "<_> ignored <_>"))

    assert {:ok, [{_labels, [{1_000, "a error b"}]}]} =
             Evaluator.evaluate_log(query, tenant, %{start_ts_ns: 0, end_ts_ns: 10_000})

    {:ok, metric} = Parser.parse(~s'count_over_time({service_name="api"} |> "<_> error <_>" [1m])')

    assert {:ok, {:vector, [{_labels, {_ts, 2.0}}]}} =
             Evaluator.evaluate_metric(metric, tenant, %{start_ts_ns: 10_000, end_ts_ns: 10_000})
  end
end
