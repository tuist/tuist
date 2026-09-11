defmodule TuistWeb.CldrHelpersTest do
  use ExUnit.Case, async: true

  # Formats numbers/money/percentages in non-en locales, which are only
  # compiled when TUIST_DEV_ALL_LOCALES=1.
  import TuistWeb.CldrHelpers

  @tag :locale
  test "formats numbers using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_number(12_345) == "12,3K"
  end

  @tag :locale
  test "formats money using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_money(Money.new(123_456, :EUR)) == "1234,56\u00a0€"
  end

  @tag :locale
  test "formats percentages using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_percent(98.1) == "98,1\u00a0%"
  end

  test "normalizes gettext locales before formatting" do
    assert format_number(12_345, locale: "zh_Hant") == "12.3K"
  end

  test "humanizes large counts at the threshold and unit boundaries" do
    for {number, expected} <- [
          {0, "0"},
          {836, "836"},
          {9999, "9,999"},
          {10_000, "10K"},
          {18_672, "18.7K"},
          {24_420, "24.4K"},
          {121_755, "121.8K"},
          {950_000, "950K"},
          {999_949, "999.9K"},
          {999_950, "1M"},
          {2_901_412, "2.9M"},
          {3_799_196, "3.8M"},
          {1_000_000_000, "1B"},
          {1_000_000_000_000, "1T"},
          {-18_672, "-18.7K"},
          {-999_950, "-1M"}
        ] do
      assert format_number(number, locale: "en") == expected
    end
  end

  test "supports floats, decimals and explicit precision below the threshold" do
    assert format_number(Decimal.new("18672"), locale: "en") == "18.7K"
    assert format_number(18_672.5, locale: "en") == "18.7K"
    assert format_number(12.5, locale: "en", fractional_digits: 1) == "12.5"
    assert format_number(12_345, locale: "es") == "12,3K"
  end

  test "preserves money and percent formatting" do
    assert format_money(Money.new(1_234_567, :USD), locale: "en") == "12,345.67$"
    assert format_percent(12_345, locale: "en") == "12,345%"
  end
end
