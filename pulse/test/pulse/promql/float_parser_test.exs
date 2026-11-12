defmodule Pulse.PromQL.FloatParserTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.FloatParser

  test "Go ParseFloat decimal, separator, and special-value spellings" do
    for {text, value} <- [
          {".5", 0.5},
          {"5.", 5.0},
          {"-5.e2", -500.0},
          {"1_000", 1000.0},
          {"1e1_0", 1.0e10},
          {"Infinity", :infinity},
          {"+inf", :infinity},
          {"-INFINITY", :negative_infinity},
          {"nAn", :nan}
        ] do
      assert FloatParser.parse(text) == {:ok, value}
    end

    for text <- ["", " 1", "1 ", "+NaN", "0x10", "1__0", "1_", "1e_2", "0x1p", "1e400"] do
      assert FloatParser.parse(text) == :error
    end
  end

  test "hexadecimal bounds round exactly once at normal and subnormal boundaries" do
    for {text, value} <- [
          {"0x1p1", 2.0},
          {"0x1.fp-2", 0.484375},
          {"0x_1p0", 1.0},
          {"0x1p-1074", 5.0e-324},
          {"0x1p-1075", 0.0},
          {"0x3p-1075", 1.0e-323},
          {"0x1.fffffffffffffp1023", 1.797_693_134_862_315_7e308}
        ] do
      assert FloatParser.parse(text) == {:ok, value}
    end

    assert {:ok, negative_zero} = FloatParser.parse("-0x1p-9999999999999")
    assert <<negative_zero::float-64>> == <<0x8000000000000000::64>>
    assert FloatParser.parse("0x1.fffffffffffff8p1023") == :error
  end

  test "query integer spellings are distinct from histogram floating-point bounds" do
    assert FloatParser.parse("0x10", :literal) == {:ok, 16.0}
    assert FloatParser.parse("010", :literal) == {:ok, 8.0}
    assert FloatParser.parse("010") == {:ok, 10.0}
    assert FloatParser.parse("0x8000000000000000", :literal) == :error
  end
end
