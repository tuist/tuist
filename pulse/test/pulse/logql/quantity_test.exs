defmodule Pulse.LogQL.QuantityTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Quantity

  test "duration parsing reverses all 1047 independently produced public Go formatter controls" do
    cases = Pulse.JSON.decode!(File.read!("test/fixtures/traces/tempo-trace-duration-format-oracle.json"))
    assert length(cases) == 1047
    for [ns, text] <- cases, do: assert(Quantity.duration(text) == {:ok, String.to_integer(ns)})
  end

  test "fractional scaling is exact without decimal floats or unbounded fraction integers" do
    for {unit, factor} <- [{"B", 1}, {"KB", 1_000}, {"KiB", 1024}, {"PiB", 1_125_899_906_842_624}],
        length <- [1, 2, 15, 40, 200] do
      fraction = String.slice(String.duplicate("9876543210", 20), 0, length)
      # Independent bounded test-only rational oracle, never used in production.
      expected = div(String.to_integer("1" <> fraction) * factor, Integer.pow(10, length))
      assert Quantity.bytes("1." <> fraction <> unit) == {:ok, expected}
    end

    assert Quantity.duration("1h2m3.5s") == {:ok, 3_723_500_000_000}
    assert Quantity.duration("0s") == {:ok, 0}
    assert Quantity.duration("+0") == {:ok, 0}
    assert Quantity.duration("-0.0ns") == {:ok, 0}
    # Deliberate exact-decimal policy: Go1.25.10 ParseDuration rounds this to
    # 1_200_000_000_000 through float64; Pulse truncates the exact quantity.
    assert Quantity.duration("0.3333333333333333333h") == {:ok, 1_199_999_999_999}
    assert Quantity.bytes("-5MB") == {:ok, -5_000_000}
    assert Quantity.bytes("+1.5KB") == {:ok, 1_500}
    assert Quantity.duration("1.999999999999999999999ns") == {:ok, 1}
    assert Quantity.bytes("9007199254740993B") == {:ok, 9_007_199_254_740_993}
  end

  test "query literals separate Loki thresholds, range windows and exact shared quantities" do
    alias Pulse.LogQL.{AST, Parser}

    for {text, expected} <- [
          {"9007199254740993.0ns", 9_007_199_254_740_993},
          {"0.6ns0.6ns", 0},
          {"0.3333333333333333333h", 1_200_000_000_000},
          {"-1h2m", -3_720_000_000_000},
          {"1w2d", 777_600_000_000_000}
        ] do
      assert {:ok, %AST.LogQuery{stages: [%AST.LabelFilter{expr: {:cmp, "latency", :eq, {:duration_ns, ^expected}}}]}} =
               Parser.parse(~s/{app="a"} | latency = #{text}/)
    end

    for text <- ["9223372036854775808ns", "9223372036854775807ns1ns", "1.5w", "1d1w", String.duplicate("9", 200) <> "s"] do
      assert {:error, :invalid_quantity} = Parser.parse(~s/{app="a"} | latency = #{text}/)
    end

    assert {:ok, %AST.LogQuery{stages: [%AST.LabelFilter{expr: {:cmp, "size", :eq, {:bytes, 9_007_199_254_740_992}}}]}} =
             Parser.parse(~s/{app="a"} | size = 9007199254740993.0B/)

    assert {:ok,
            %AST.LogQuery{stages: [%AST.LabelFilter{expr: {:cmp, "size", :eq, {:bytes, 18_446_744_073_709_551_615}}}]}} =
             Parser.parse(~s/{app="a"} | size = 18446744073709551615B/)

    for text <- ["1.5h", "1ns", "1µs", "1s1m", "1m1m", " 1m", "1m "] do
      assert {:error, _} = Parser.parse(~s/count_over_time({app="a"}[#{text}])/)
    end

    assert Quantity.duration("1w") == :error
    assert Quantity.duration_literal("1w") == {:ok, 604_800_000_000_000}
    assert Quantity.duration_literal("1.5w") == :error
    assert Quantity.duration("0.3333333333333333333h") == {:ok, 1_199_999_999_999}
  end

  test "overflow, unsupported units, junk and internal signs reject without partial parsing" do
    for text <- [
          "",
          "+",
          "--1s",
          "1s-1ms",
          "1sx",
          "1e3s",
          "1w",
          "1y",
          "1.2.3s",
          "9223372036854775808ns",
          "-9223372036854775809ns",
          String.duplicate("9", 10_000) <> "s"
        ] do
      assert Quantity.duration(text) == :error
    end

    assert Quantity.duration("-9223372036854775808ns") == {:ok, -9_223_372_036_854_775_808}
    assert Quantity.duration("9223372036854775807ns1ns") == :error

    for text <- ["", "unknown", "1.5K", "1e3B", "1KBjunk", "9223372036854775808B"] do
      assert Quantity.bytes(text) == :error
    end
  end

  test "runtime profiles preserve bounded rounding, unsigned bytes and literal isolation" do
    assert Quantity.duration_value("0.3333333333333333333h") == {:ok, 1_200_000_000_000}
    assert Quantity.duration("0.3333333333333333333h") == {:ok, 1_199_999_999_999}
    assert Quantity.bytes_value("0.9999999999999999999B") == {:ok, 1}
    assert Quantity.bytes("0.9999999999999999999B") == {:ok, 0}
    assert Quantity.bytes_value("9007199254740993B") == {:ok, 9_007_199_254_740_993}
    assert Quantity.bytes_value("9007199254740993.0B") == {:ok, 9_007_199_254_740_992}
    assert Quantity.bytes_value("18446744073709549568.0B") == {:ok, 18_446_744_073_709_549_568}
    assert Quantity.bytes_value("18446744073709551615B") == {:ok, 18_446_744_073_709_551_615}
    assert Quantity.bytes_value("18446744073709551615.0B") == {:error, "too large: 18446744073709551615.0B"}
    assert Quantity.bytes_value("18446744073709551616B") == {:error, "too large: 18446744073709551616B"}
    assert Quantity.bytes_value("42\u0085MiB\u3000") == {:ok, 44_040_192}
    assert Quantity.bytes_value("4,2,MiB") == {:ok, 44_040_192}

    for text <- ["+5MB", "-5MB", " 5MB", "1e3B", "1..2B", "NaNB", "１２MB"] do
      assert {:error, _details} = Quantity.bytes_value(text)
    end

    assert Quantity.bytes_value(<<255>>) == :error

    for text <- ["0s0", "0ns0.0ns0", "1d", "1w", "1y", "1s-1ms", <<255>>] do
      assert {:error, _details} = Quantity.duration_value(text)
    end

    # The three non-UTF-8 Go error-table inputs cannot enter JSON HTTP, but
    # the converter must still retain their byte-oriented diagnostic text.
    for {text, quoted} <- [
          {<<0x85, 0x85>>, ~S/"\x85\x85"/},
          {<<0xFF, "ff">>, ~S/"\xffff"/},
          {<<"hello ", 0xFF, "ff world">>, ~S/"hello \xffff world"/}
        ] do
      assert Quantity.duration_value(text) == {:error, "time: invalid duration " <> quoted}
    end

    zeros = String.duplicate("0", 10_000)
    assert Quantity.duration_value("0." <> zeros <> "1h") == {:ok, 0}
    assert Quantity.bytes_value("0." <> zeros <> "1B") == {:ok, 0}
    assert Quantity.duration_value(String.duplicate("0s", 2000)) == {:ok, 0}
    assert {:error, _details} = Quantity.bytes_value(String.duplicate("9", 10_000) <> "B")
    assert {:error, _details} = Quantity.duration_value(String.duplicate("9", 10_000) <> "h")
  end
end
