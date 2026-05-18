defmodule TuistWeb.CldrHelpers do
  @moduledoc """
  Locale-aware formatting helpers for numbers rendered in the web layer.
  """

  alias Tuist.Cldr

  def format_number(number, opts \\ []) do
    {locale, opts} = Keyword.pop(opts, :locale)

    Cldr.Number.to_string!(number, Keyword.merge([format: "#,##0", locale: locale(locale)], opts))
  end

  def format_money(%Money{} = money, opts \\ []) do
    {locale, opts} = Keyword.pop(opts, :locale)

    money
    |> Money.to_decimal()
    |> Cldr.Number.to_string!(
      Keyword.merge(
        [format: :currency, currency: money.currency, locale: locale(locale)],
        opts
      )
    )
  end

  def format_percent(number, opts \\ []) when is_number(number) do
    {locale, opts} = Keyword.pop(opts, :locale)
    digits = if trunc(number) == number, do: 0, else: 1

    Cldr.Number.to_string!(
      number / 100,
      Keyword.merge([format: :percent, fractional_digits: digits, locale: locale(locale)], opts)
    )
  end

  defp locale(nil), do: TuistWeb.Gettext |> Gettext.get_locale() |> normalize_locale()
  defp locale(locale), do: normalize_locale(locale)

  defp normalize_locale(locale) do
    locale
    |> to_string()
    |> String.replace("_", "-")
  end
end
