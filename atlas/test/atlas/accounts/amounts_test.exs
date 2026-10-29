defmodule Atlas.Accounts.AmountsTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Amounts

  test "formats monetary values using normalized ISO currencies" do
    assert Amounts.format(Decimal.new("4200"), "eur") == "EUR 4,200.00"
    assert Amounts.format(Decimal.new("125000"), "JPY") == "JPY 125,000"
  end

  test "falls back gracefully when the currency is missing or unknown" do
    assert Amounts.format(Decimal.new("15.5"), nil) == "15.5"
    assert Amounts.format(Decimal.new("15.5"), "xyz") == "XYZ 15.5"
  end

  test "normalizes currency codes" do
    assert Amounts.normalize_currency(" usd ") == "USD"
    assert Amounts.normalize_currency(:eur) == "EUR"
    assert Amounts.normalize_currency("") == nil
  end

  test "returns placeholder for unparsable values" do
    assert Amounts.format("not-a-number", "EUR") == "-"
    assert Amounts.format_or_nil("not-a-number", "EUR") == nil
  end
end
