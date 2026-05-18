defmodule TuistWeb.CldrHelpersTest do
  use ExUnit.Case, async: true

  import TuistWeb.CldrHelpers

  test "formats numbers using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_number(12_345) == "12.345"
  end

  test "formats money using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_money(Money.new(123_456, :EUR)) == "1234,56\u00a0€"
  end

  test "formats percentages using the current locale" do
    Gettext.put_locale(TuistWeb.Gettext, "es")

    assert format_percent(98.1) == "98,1\u00a0%"
  end

  test "normalizes gettext locales before formatting" do
    assert format_number(12_345, locale: "zh_Hant") == "12,345"
  end
end
