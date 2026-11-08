defmodule Pulse.Loki.HTTPParamsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.HTTPParams

  @fixture Path.expand("../../fixtures/logs/loki-upstream/http-parameters.json", __DIR__)
  @external_resource @fixture
  @tables %{
    "TestHttp_defaultQueryRangeStep" => 3,
    "Test_uint32QueryParamBounds" => 8,
    "Test_uint32QueryParamValidValues" => 4,
    "TestHttp_ParseRangeQuery_Step" => 6,
    "Test_interval" => 5,
    "Test_parseTimestamp" => 7,
    "Test_determineBounds" => 9,
    "TestParseRangeQuery" => 10,
    "TestParseInstantQuery" => 4
  }
  @rows @fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("rows")
  @selected Enum.filter(@rows, &Map.has_key?(@tables, &1["table"]))
  @year_one -62_135_596_800_000_000_000
  # Primitive parser defaults, not endpoint admission ceilings.
  @uint32_components %{
    "limit" => {"limit", 100, 1},
    "lineLimit" => {"line_limit", 100, 1},
    "detectedFieldsLimit" => {"limit", 1000, 1},
    "tailDelay" => {"delay_for", 0, 0}
  }

  test "replays every row in the nine complete frozen tables" do
    assert Enum.frequencies_by(@selected, & &1["table"]) == @tables
    assert length(@selected) == 56
    assert length(Enum.uniq_by(@selected, &{&1["table"], &1["name"]})) == 56
    assert Enum.count(@selected, & &1["error"]["reject"]) == 25
  end

  for row <- @selected do
    @tag table: row["table"]
    test "#{row["table"]}: #{row["name"]}" do
      row = unquote(Macro.escape(row))
      result = replay(row)
      assert_error_expectation(result, row["error"])

      if row["expected_asserted"] do
        assert_value_expectation(result, row)
      end
    end
  end

  test "the year-one timestamp sentinel is an accepted default, not an explicit int64 timestamp" do
    assert HTTPParams.timestamp("", @year_one) == {:ok, @year_one}
    assert HTTPParams.timestamp(nil, @year_one) == {:ok, @year_one}
    assert {:error, {:http_parameter_error, "time", _}} = HTTPParams.timestamp(Integer.to_string(@year_one))
    assert {:error, {:http_parameter_error, "time", _}} = HTTPParams.timestamp("0001-01-01T00:00:00Z")
  end

  test "uint32 component defaults and minimums are independent of endpoint ceilings" do
    for {_component, {name, default, minimum}} <- @uint32_components do
      assert HTTPParams.uint32(nil, name, default, minimum) == {:ok, default}
      assert HTTPParams.uint32("", name, default, minimum) == {:ok, default}
      assert HTTPParams.uint32(Integer.to_string(minimum), name, default, minimum) == {:ok, minimum}
    end
  end

  test "resolution admission counts intervals and rejects zero, nonfinite and oversized numeric values" do
    assert HTTPParams.step("1", 0, 11_000_000_000_000) == {:ok, 1_000_000_000}
    assert {:error, _} = HTTPParams.step("1", 0, 11_001_000_000_000)

    for value <- ["0", "-0.5", "NaN", "Inf", "1e309", "9223372036.854776", String.duplicate("9", 129)] do
      assert {:error, _} = HTTPParams.step(value, 0, 1_000_000_000)
    end
  end

  test "timestamp rounding, original integer length and explicit int64 bounds remain distinct" do
    for {input, expected} <- [
          {"0.0005", 1_000_000},
          {"-0.0005", -1_000_000},
          {"-1234567890", -1_234_567_890},
          {"0x1.0p+0", 1_000_000_000},
          {"9223372036854775807", 9_223_372_036_854_775_807},
          {"-9223372036854775808", -9_223_372_036_854_775_808}
        ] do
      assert HTTPParams.timestamp(input) == {:ok, expected}
    end

    for input <- ["9223372036854775808", "-9223372036854775809", "1.0e100", "1e3", String.duplicate("1", 129)] do
      assert {:error, _} = HTTPParams.timestamp(input)
    end
  end

  @calendar_fixture Path.expand("../../fixtures/logs/loki-upstream/http-calendar-timestamps.json", __DIR__)
  @external_resource @calendar_fixture
  test "calendar timestamps replay pinned Go fractional and grammar oracles within int64 bounds" do
    fixture = @calendar_fixture |> File.read!() |> JSON.decode!()
    assert length(fixture["rows"]) == 105

    for row <- fixture["rows"] do
      expected = if row["expected_ns"], do: String.to_integer(row["expected_ns"])
      result = HTTPParams.timestamp(row["input"])

      if row["reject"] or expected < -9_223_372_036_854_775_808 or expected > 9_223_372_036_854_775_807 do
        assert match?({:error, {:http_parameter_error, "time", _}}, result), row["id"]
      else
        assert result == {:ok, expected}, row["id"]
      end
    end

    prefix = "2020-01-02T03:04:05."
    at_limit = prefix <> String.duplicate("1", 107) <> "Z"
    assert byte_size(at_limit) == 128
    assert HTTPParams.timestamp(at_limit) == {:ok, 1_577_934_245_111_111_111}
    assert {:error, _} = HTTPParams.timestamp(prefix <> String.duplicate("1", 108) <> "Z")
  end

  defp replay(%{"table" => "TestHttp_defaultQueryRangeStep", "input" => input}) do
    HTTPParams.default_step(ns(input["start_ns"]), ns(input["end_ns"]))
  end

  defp replay(%{"component" => component, "input" => input}) do
    {name, default, minimum} = Map.fetch!(@uint32_components, component)
    HTTPParams.uint32(params(input)[name], name, default, minimum)
  end

  defp replay(%{"table" => "Test_interval", "input" => input}) do
    HTTPParams.interval(params(input)["interval"])
  end

  defp replay(%{"table" => "Test_parseTimestamp", "input" => input}) do
    HTTPParams.timestamp(input["value"], ns(input["def_ns"]))
  end

  defp replay(%{"table" => "Test_determineBounds", "input" => %{"args" => args}}) do
    HTTPParams.bounds(
      %{"start" => args["startString"], "end" => args["endString"], "since" => args["sinceString"]},
      ns(args["now_ns"])
    )
  end

  defp replay(%{"table" => table, "input" => input}) do
    mode = if table == "TestParseInstantQuery", do: :instant, else: :range
    HTTPParams.query(params(input), mode)
  end

  defp params(input) do
    target = input["reqPath"] || input["r"]["fields"]["URL"]
    target |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  # Four interval rows deliberately assert only the value, not nil error.
  # The three default-step rows have no error return at all.
  defp assert_error_expectation(_result, %{"asserted" => false}), do: :ok

  defp assert_error_expectation(result, %{"reject" => false}) do
    refute match?({:error, _}, result)
  end

  defp assert_error_expectation(result, %{"reject" => true} = expected) do
    assert {:error, {:http_parameter_error, _name, message}} = result
    if fragment = expected["contains"], do: assert(message =~ fragment)
    if exact = expected["equals"], do: assert(message == exact)
  end

  # Go returns zero-valued time/bounds alongside errors. The public Elixir API
  # instead returns an error with no value. Preserve that no-result assertion
  # without treating the frozen year-one sentinel as an explicit timestamp.
  defp assert_value_expectation({:error, _} = result, %{"error" => %{"reject" => true}} = row) do
    assert {:error, {:http_parameter_error, _, _}} = result

    case row["expected"] do
      nil ->
        :ok

      value when is_binary(value) ->
        assert ns(value) == @year_one

      %{"type" => "bounds", "fields" => fields} ->
        assert fields == %{"Start_ns" => Integer.to_string(@year_one), "End_ns" => Integer.to_string(@year_one)}
    end
  end

  defp assert_value_expectation(result, %{"table" => "TestHttp_defaultQueryRangeStep", "expected" => expected}) do
    assert result == ns(expected)
  end

  defp assert_value_expectation(result, %{"expected" => %{"type" => "bounds", "fields" => fields}}) do
    assert result == {:ok, %{start_ns: ns(fields["Start_ns"]), end_ns: ns(fields["End_ns"])}}
  end

  defp assert_value_expectation(result, %{"expected" => %{"type" => "RangeQuery", "fields" => fields}}) do
    assert result ==
             {:ok,
              %{
                start_ts_ns: ns(fields["Start_ns"]),
                end_ts_ns: ns(fields["End_ns"]),
                limit: fields["Limit"],
                direction: direction(fields["Direction"]),
                step_ns: ns(fields["Step_ns"]),
                interval_ns: ns(Map.get(fields, "Interval_ns", "0"))
              }}
  end

  defp assert_value_expectation(result, %{"expected" => %{"type" => "InstantQuery", "fields" => fields}}) do
    assert result ==
             {:ok, %{end_ts_ns: ns(fields["Ts_ns"]), limit: fields["Limit"], direction: direction(fields["Direction"])}}
  end

  defp assert_value_expectation(result, %{"expected" => expected}) do
    # Extract only the value for interval's unasserted error channel.
    value =
      case result do
        {:ok, value} -> value
        {:error, _} -> nil
      end

    assert value == if(is_binary(expected), do: ns(expected), else: expected)
  end

  defp ns(value), do: String.to_integer(value)
  defp direction("BACKWARD"), do: :backward
  defp direction("FORWARD"), do: :forward
end
