defmodule TuistWeb.CldrHelpers do
  @moduledoc """
  Locale-aware formatting helpers for numbers rendered in the web layer.
  """

  @default_format %{decimal: ".", group: ",", space: ""}
  @locale_formats %{
    "es" => %{decimal: ",", group: ".", space: "\u00A0"},
    "ru" => %{decimal: ",", group: "\u00A0", space: "\u00A0"}
  }

  def format_number(number, opts \\ []) do
    {locale, opts} = Keyword.pop(opts, :locale)
    digits = Keyword.get(opts, :fractional_digits, 0)

    number
    |> decimal()
    |> format_decimal(locale(locale), digits)
  end

  def format_money(%Money{} = money, opts \\ []) do
    {locale, opts} = Keyword.pop(opts, :locale)
    locale = locale(locale)
    digits = Keyword.get(opts, :fractional_digits, Money.Currency.exponent!(money.currency))
    symbol = Money.Currency.symbol!(money.currency)
    format = locale_format(locale)

    money
    |> Money.to_decimal()
    |> format_decimal(locale, digits, minimum_grouping_digits: 5)
    |> Kernel.<>(format.space <> symbol)
  end

  def format_percent(number, opts \\ []) when is_number(number) do
    {locale, opts} = Keyword.pop(opts, :locale)
    locale = locale(locale)
    digits = if trunc(number) == number, do: 0, else: 1
    digits = Keyword.get(opts, :fractional_digits, digits)
    format = locale_format(locale)

    number
    |> decimal()
    |> format_decimal(locale, digits)
    |> Kernel.<>(format.space <> "%")
  end

  defp locale(nil), do: TuistWeb.Gettext |> Gettext.get_locale() |> normalize_locale()
  defp locale(locale), do: normalize_locale(locale)

  defp normalize_locale(locale) do
    locale
    |> to_string()
    |> String.replace("_", "-")
  end

  defp decimal(%Decimal{} = decimal), do: decimal
  defp decimal(number) when is_integer(number), do: Decimal.new(number)
  defp decimal(number) when is_float(number), do: Decimal.from_float(number)

  defp format_decimal(decimal, locale, digits, opts \\ []) do
    format = locale_format(locale)
    minimum_grouping_digits = Keyword.get(opts, :minimum_grouping_digits, 1)

    decimal
    |> Decimal.round(digits)
    |> Decimal.to_string(:normal)
    |> localized_decimal(format, digits, minimum_grouping_digits)
  end

  defp localized_decimal("-" <> decimal, format, digits, minimum_grouping_digits) do
    "-" <> localized_decimal(decimal, format, digits, minimum_grouping_digits)
  end

  defp localized_decimal(decimal, format, digits, minimum_grouping_digits) do
    {integer, fractional} =
      case String.split(decimal, ".", parts: 2) do
        [integer] -> {integer, ""}
        [integer, fractional] -> {integer, fractional}
      end

    fractional = String.pad_trailing(fractional, digits, "0")
    integer = group_integer(integer, format.group, minimum_grouping_digits)

    if digits == 0 do
      integer
    else
      integer <> format.decimal <> fractional
    end
  end

  defp group_integer(integer, group_separator, minimum_grouping_digits) do
    if String.length(integer) < minimum_grouping_digits do
      integer
    else
      integer
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(fn chunk -> chunk |> Enum.reverse() |> Enum.join() end)
      |> Enum.reverse()
      |> Enum.join(group_separator)
    end
  end

  defp locale_format(locale) do
    Map.get(@locale_formats, locale, @default_format)
  end
end
