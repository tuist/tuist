defmodule AtlasWeb.FinanceLive.Formatters do
  @moduledoc false

  use Gettext, backend: AtlasWeb.Gettext

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance.Account
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.Transaction

  def transactions_date_range_presets do
    [
      %{id: "last-7-days", label: gettext("Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: gettext("Last 30 days"), period: {30, :day}},
      %{id: "last-90-days", label: gettext("Last 90 days"), period: {90, :day}},
      %{id: "last-12-months", label: gettext("Last 12 months"), period: {12, :month}},
      %{id: "custom", label: gettext("Custom")}
    ]
  end

  def source_option_label(source) do
    [
      "#{source.name} (#{humanize_value(source.provider)})",
      source.atlas_account && source.atlas_account.name
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" · ")
  end

  def account_option_label(account) do
    [
      account.name,
      account.source.atlas_account && account.source.atlas_account.name,
      account.currency || account.balance_currency || "n/a"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" · ")
  end

  def account_description(%Account{} = account) do
    [
      account.source.atlas_account && account.source.atlas_account.name,
      account.source.name,
      humanize_value(account.provider),
      account.currency
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" · ")
  end

  def account_type_label(%Account{} = account) do
    [account.account_type, account.account_subtype]
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> "-"
      values -> Enum.map_join(values, " / ", &humanize_value/1)
    end
  end

  def counterparty_label(%Transaction{} = transaction) do
    transaction.counterparty_name || transaction.reference || transaction.description || transaction.external_id
  end

  def transaction_description(%Transaction{} = transaction) do
    [transaction.description, maybe_humanize(transaction.kind), transaction.reference]
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> case do
      [] -> "-"
      values -> Enum.join(values, " · ")
    end
  end

  def transaction_amount_description(%Transaction{} = transaction) do
    [local_amount_label(transaction), fee_label(transaction)]
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, " · ")
    end
  end

  def category_label(%Transaction{category: nil}), do: "-"
  def category_label(%Transaction{category: category}), do: category.name

  def invoice_line_items_label(%Invoice{line_items: []}), do: gettext("No extracted lines")

  def invoice_line_items_label(%Invoice{} = invoice) do
    invoice.line_items
    |> Enum.map(fn line_item ->
      (line_item.category && line_item.category.name) || line_item.cost_type || gettext("Uncategorized")
    end)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.take(3)
    |> case do
      [] -> gettext("No extracted lines")
      values -> Enum.join(values, " · ")
    end
  end

  def local_amount_label(%Transaction{local_amount_value: nil}), do: nil

  def local_amount_label(%Transaction{} = transaction) do
    gettext(
      "Local %{amount}",
      amount: format_amount(transaction.local_amount_value, transaction.local_amount_currency)
    )
  end

  def fee_label(%Transaction{fee_value: nil}), do: nil

  def fee_label(%Transaction{} = transaction) do
    gettext("Fee %{amount}", amount: format_amount(transaction.fee_value, transaction.fee_currency))
  end

  def format_amount(nil, _currency), do: "-"
  def format_amount(_value, nil), do: "-"
  def format_amount(value, currency), do: Amounts.format(value, currency)

  @million Decimal.new("1000000")
  @thousand Decimal.new("1000")

  @doc """
  Compact currency label for KPI tiles. Keeps long values readable in
  narrow widget cells by collapsing them to `K`/`M` suffixes (e.g. `EUR 190.4K`).
  """
  def compact_amount(nil, _currency), do: "-"
  def compact_amount(_value, nil), do: "-"

  def compact_amount(value, currency) do
    {sign, abs_value} = decimal_sign(value)

    cond do
      Decimal.compare(abs_value, @million) != :lt ->
        "#{sign}#{currency} #{compact_number(abs_value, @million, "M")}"

      Decimal.compare(abs_value, @thousand) != :lt ->
        "#{sign}#{currency} #{compact_number(abs_value, @thousand, "K")}"

      true ->
        format_amount(value, currency)
    end
  end

  @doc """
  Compact currency label with a leading sign for net flow values
  (e.g. `+EUR 12.3K`, `-EUR 33.2K`).
  """
  def signed_compact_amount(nil, _currency), do: "-"
  def signed_compact_amount(_value, nil), do: "-"

  def signed_compact_amount(value, currency) do
    label = compact_amount(Decimal.abs(value), currency)

    case Decimal.compare(value, Decimal.new("0")) do
      :gt -> "+" <> label
      :lt -> "-" <> label
      :eq -> label
    end
  end

  defp decimal_sign(%Decimal{} = value) do
    if Decimal.negative?(value), do: {"-", Decimal.abs(value)}, else: {"", value}
  end

  defp compact_number(%Decimal{} = abs_value, divisor, suffix) do
    abs_value
    |> Decimal.div(divisor)
    |> Decimal.round(1)
    |> Decimal.to_string(:normal)
    |> Kernel.<>(suffix)
  end

  def signed_amount_label(value, currency), do: signed_amount_label(value, currency, nil)
  def signed_amount_label(nil, _currency, _direction), do: "-"

  def signed_amount_label(value, currency, direction) do
    absolute_label = format_amount(Decimal.abs(value), currency)

    case direction do
      "debit" -> "-" <> absolute_label
      "credit" -> "+" <> absolute_label
      _other -> signed_decimal_label(value, absolute_label)
    end
  end

  def runway_label(value, nil_label \\ gettext("No net burn"))
  def runway_label(nil, nil_label), do: nil_label

  def runway_label(value, _nil_label) do
    gettext("%{months} months", months: Decimal.to_string(Decimal.round(value, 1)))
  end

  @doc """
  Trend caption rendered next to the Runway widget's percentage badge.
  When the plan-adjusted runway extends the cash-only number, the
  uplift is appended inline so the widget keeps a single-row footer.
  """
  def runway_trend_label(nil), do: gettext("since last month")

  def runway_trend_label(%Decimal{} = uplift) do
    case Decimal.compare(uplift, Decimal.new("0.05")) do
      :gt ->
        gettext("since last month · +%{months} mo with renewals",
          months: Decimal.to_string(Decimal.round(uplift, 1))
        )

      _ ->
        gettext("since last month")
    end
  end

  @doc """
  Trend caption rendered next to the Income widget's percentage badge.
  Appends the matching expenses figure inline so the widget keeps a
  single-row footer like its siblings.
  """
  def income_trend_label(nil, _currency), do: gettext("vs last month")
  def income_trend_label(_value, nil), do: gettext("vs last month")

  def income_trend_label(%Decimal{} = expenses, currency) do
    gettext("vs last month · %{amount} expenses", amount: compact_amount(expenses, currency))
  end

  @doc """
  Caption shown under the committed pipeline widget, e.g.
  "Next: Monday · Aug 1".
  """
  def committed_pipeline_caption(nil), do: nil

  def committed_pipeline_caption(%{name: name, renewal_date: %Date{} = date}) do
    gettext("Next: %{name} · %{date}", name: name, date: Calendar.strftime(date, "%b %-d"))
  end

  @doc """
  Sublabel for the plan-adjusted runway widget showing the
  cash-plus-committed runway alongside, e.g. "13.1 mo incl. pipeline".
  """
  def cash_plus_committed_caption(nil), do: nil

  def cash_plus_committed_caption(%Decimal{} = months) do
    gettext("%{months} mo incl. pipeline",
      months: Decimal.to_string(Decimal.round(months, 1))
    )
  end

  @doc """
  Caption shown under the Renewal ARR widget so the renewal-scenario
  tiles all keep a one-row footer.
  """
  def renewal_base_caption(0), do: nil
  def renewal_base_caption(nil), do: nil

  def renewal_base_caption(count) when is_integer(count) do
    gettext("Across %{count} customers", count: count)
  end

  @doc """
  Caption shown under the Adjusted burn widget. Surfaces the gross
  monthly expenses so the user can read the burn as a delta.
  """
  def adjusted_burn_caption(nil, _currency), do: nil
  def adjusted_burn_caption(_value, nil), do: nil

  def adjusted_burn_caption(%Decimal{} = expenses, currency) do
    gettext("vs %{amount} gross", amount: compact_amount(expenses, currency))
  end

  def zero_decimal?(nil), do: true
  def zero_decimal?(value), do: Decimal.equal?(value, Decimal.new("0"))

  def net_legend_color(nil), do: "neutral"

  def net_legend_color(value) do
    case Decimal.compare(value, Decimal.new("0")) do
      :gt -> "success"
      :lt -> "destructive"
      :eq -> "neutral"
    end
  end

  def direction_color("credit"), do: "success"
  def direction_color("debit"), do: "destructive"
  def direction_color(_direction), do: "neutral"

  def status_color(status) when status in ["completed", "booked", "active", "open", "sent"], do: "success"
  def status_color(status) when status in ["pending", "processing"], do: "attention"

  def status_color(status) when status in ["failed", "rejected", "canceled", "cancelled", "closed", "blocked"],
    do: "destructive"

  def status_color(_status), do: "neutral"

  def status_label(nil), do: "-"
  def status_label(value), do: humanize_value(value)

  def humanize_value(nil), do: "-"

  def humanize_value(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.trim()
    |> String.capitalize()
  end

  def humanize_value(value), do: value |> to_string() |> humanize_value()

  def maybe_humanize(nil), do: nil
  def maybe_humanize(value), do: humanize_value(value)

  def last_synced_label(nil), do: gettext("Not synced yet")

  def last_synced_label(%DateTime{} = datetime) do
    gettext("Last sync %{datetime}", datetime: format_datetime(datetime))
  end

  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Date.to_iso8601(date)
  def format_date(_value), do: "-"

  def signed_decimal_label(value, label) do
    case Decimal.compare(value, Decimal.new("0")) do
      :gt -> "+" <> label
      :lt -> "-" <> label
      :eq -> label
    end
  end

  def blank?(nil), do: true
  def blank?(""), do: true
  def blank?(_value), do: false
end
