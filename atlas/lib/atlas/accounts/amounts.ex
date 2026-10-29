defmodule Atlas.Accounts.Amounts do
  @moduledoc false

  alias Money.Currency

  @money_options [symbol: false]

  def normalize_currency(nil), do: nil

  def normalize_currency(currency) when is_atom(currency), do: normalize_currency_code(currency)

  def normalize_currency(currency) when is_binary(currency), do: normalize_currency_code(currency)

  defp normalize_currency_code(currency) do
    currency
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      currency -> normalize_present_currency(currency)
    end
  end

  def format(nil, _currency), do: "-"

  def format(value, currency) do
    format_or_nil(value, currency) || "-"
  end

  def format_or_nil(nil, _currency), do: nil

  def format_or_nil(value, currency) do
    amount = decimal_amount(value)
    currency = normalize_currency(currency)

    case {amount, currency} do
      {nil, _currency} ->
        nil

      {%Decimal{} = amount, nil} ->
        Decimal.to_string(amount, :normal)

      {%Decimal{} = amount, currency} ->
        format_with_currency(amount, currency)
    end
  end

  defp decimal_amount(%Decimal{} = value), do: value
  defp decimal_amount(value) when is_integer(value), do: Decimal.new(value)
  defp decimal_amount(value) when is_float(value), do: Decimal.from_float(value)

  defp decimal_amount(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp decimal_amount(_value), do: nil

  defp format_with_currency(amount, currency) do
    if Currency.exists?(currency) do
      currency_code = currency |> Currency.to_atom() |> Atom.to_string()
      {:ok, money} = Money.parse(amount, currency_code)

      "#{currency_code} #{Money.to_string(money, @money_options)}"
    else
      "#{currency} #{Decimal.to_string(amount, :normal)}"
    end
  end

  defp normalize_present_currency(currency) do
    if Currency.exists?(currency) do
      currency
      |> Currency.to_atom()
      |> Atom.to_string()
    else
      currency
      |> String.upcase()
    end
  end
end
