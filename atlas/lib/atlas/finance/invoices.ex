defmodule Atlas.Finance.Invoices do
  @moduledoc false

  import Ecto.Changeset
  import Ecto.Query

  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Finance.Category
  alias Atlas.Finance.Config
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.InvoiceLineItem
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  @default_limit 50
  @zero Decimal.new("0")

  def list_invoices(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    from(invoice in Invoice, as: :invoice)
    |> join(:left, [invoice], document in assoc(invoice, :document), as: :document)
    |> join(:left, [invoice], transaction in assoc(invoice, :transaction), as: :transaction)
    |> preload([document: document, transaction: transaction],
      document: document,
      transaction: {transaction, [:category]},
      line_items: ^line_items_query()
    )
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_vendor(Keyword.get(opts, :vendor))
    |> maybe_filter_category_slug(Keyword.get(opts, :category_slug))
    |> maybe_filter_date_from(Keyword.get(opts, :date_from))
    |> maybe_filter_date_to(Keyword.get(opts, :date_to))
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> order_by([invoice], desc_nulls_last: invoice.invoice_date, desc: invoice.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_invoice(id) when is_binary(id) do
    from(invoice in Invoice, as: :invoice)
    |> preload([:document, transaction: [:category], line_items: ^line_items_query()])
    |> Repo.get(id)
  end

  def get_invoice_by_document(%Document{id: document_id}), do: get_invoice_by_document(document_id)

  def get_invoice_by_document(document_id) when is_binary(document_id) do
    Invoice
    |> where([invoice], invoice.document_id == ^document_id)
    |> preload([:document, transaction: [:category], line_items: ^line_items_query()])
    |> Repo.one()
  end

  def invoice_for_transaction?(%Transaction{id: transaction_id}), do: invoice_for_transaction?(transaction_id)

  def invoice_for_transaction?(transaction_id) when is_binary(transaction_id) do
    Repo.exists?(from invoice in Invoice, where: invoice.finance_transaction_id == ^transaction_id)
  end

  def upsert_extracted_invoice(%Document{} = document, attrs, line_items, opts \\ [])
      when is_map(attrs) and is_list(line_items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      invoice =
        Repo.one(from invoice in Invoice, where: invoice.document_id == ^document.id) ||
          %Invoice{document_id: document.id}

      invoice_attrs =
        attrs
        |> Map.put_new(:status, status_for(line_items))
        |> Map.put(:extracted_at, Map.get(attrs, :extracted_at) || now)
        # A successful re-extraction must clear any error left by a prior failed
        # attempt, otherwise the invoice looks failed while carrying valid data.
        |> Map.put(:last_error, nil)

      {finance_transaction_id, invoice_attrs} = Map.pop(invoice_attrs, :finance_transaction_id)

      invoice =
        invoice
        |> Invoice.changeset(invoice_attrs)
        |> maybe_put_change(:finance_transaction_id, finance_transaction_id)
        |> Repo.insert_or_update!()

      from(line_item in InvoiceLineItem, where: line_item.finance_invoice_id == ^invoice.id)
      |> Repo.delete_all()

      inserted_line_items =
        Enum.map(line_items, fn line_item_attrs ->
          {finance_category_id, line_item_attrs} =
            line_item_attrs
            |> put_line_item_category()
            |> Map.pop(:finance_category_id)

          %InvoiceLineItem{finance_invoice_id: invoice.id}
          |> InvoiceLineItem.changeset(line_item_attrs)
          |> maybe_put_change(:finance_category_id, finance_category_id)
          |> Repo.insert!()
        end)

      invoice = Repo.preload(invoice, [:document, :transaction, line_items: line_items_query()], force: true)
      audit_invoice("finance_invoice.extracted", invoice, inserted_line_items, opts)
      invoice
    end)
  end

  def mark_invoice_extraction_failed(%Document{} = document, reason, opts \\ []) do
    attrs = %{
      vendor_name: document.title || document.original_filename || "Unknown vendor",
      status: "failed",
      last_error: inspect(reason),
      extracted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: %{"document_path" => "/documents/#{document.id}"}
    }

    Repo.transaction(fn ->
      invoice =
        Repo.one(from invoice in Invoice, where: invoice.document_id == ^document.id) ||
          %Invoice{document_id: document.id}

      invoice =
        invoice
        |> Invoice.changeset(attrs)
        |> Repo.insert_or_update!()

      from(line_item in InvoiceLineItem, where: line_item.finance_invoice_id == ^invoice.id)
      |> Repo.delete_all()

      invoice = Repo.preload(invoice, [:document, :transaction, line_items: line_items_query()], force: true)
      audit_invoice("finance_invoice.extraction_failed", invoice, [], opts)
      invoice
    end)
  end

  def link_transaction(%Invoice{} = invoice, %Transaction{} = transaction, opts \\ []) do
    invoice
    |> Invoice.changeset(%{})
    |> put_change(:finance_transaction_id, transaction.id)
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        audit_invoice("finance_invoice.transaction_linked", Repo.preload(updated, :line_items), [], opts)

      _result ->
        :ok
    end)
  end

  defp maybe_put_change(changeset, _key, nil), do: changeset
  defp maybe_put_change(changeset, key, value), do: put_change(changeset, key, value)

  def cost_breakdown(opts \\ []) do
    currency = Keyword.get(opts, :currency)

    InvoiceLineItem
    |> join(:inner, [line_item], invoice in assoc(line_item, :invoice), as: :invoice)
    |> join(:left, [line_item], category in assoc(line_item, :category), as: :category)
    |> maybe_filter_line_currency(currency)
    |> group_by([line_item, category: category], [
      fragment("coalesce(?, ?)", category.name, line_item.cost_type),
      fragment("coalesce(?, ?)", category.slug, line_item.cost_type),
      line_item.amount_currency
    ])
    |> select([line_item, category: category], %{
      category_name: fragment("coalesce(?, ?)", category.name, line_item.cost_type),
      category_slug: fragment("coalesce(?, ?)", category.slug, line_item.cost_type),
      amount_currency: line_item.amount_currency,
      amount_value: sum(line_item.amount_value),
      line_item_count: count(line_item.id)
    })
    |> order_by([line_item], desc: sum(line_item.amount_value))
    |> Repo.all()
  end

  def vendor_analytics(opts \\ []) do
    invoices =
      opts
      |> vendor_invoice_query()
      |> Repo.all()

    report_currency = Config.report_currency()
    exchange_rates = load_exchange_rates(report_currency, invoices, opts)
    reported_invoices = convert_invoices(invoices, report_currency, exchange_rates)
    available_currencies = currency_summaries(reported_invoices)
    total_spend = sum_decimals(reported_invoices, &(&1.total_amount_value || @zero))
    vendors = vendor_summaries(reported_invoices)
    top_vendor = List.first(vendors)

    %{
      currency: report_currency,
      default_currency: report_currency,
      available_currencies: available_currencies,
      total_spend_value: total_spend,
      invoice_count: length(reported_invoices),
      vendor_count: length(vendors),
      needs_review_count: Enum.count(reported_invoices, &(&1.status == "needs_review")),
      concentration_percent: concentration_percent(vendors, total_spend),
      top_vendor: top_vendor,
      vendors: vendors,
      categories: category_summaries(reported_invoices),
      monthly_spend: monthly_spend(reported_invoices),
      expenses: expense_summaries(reported_invoices)
    }
  end

  defp line_items_query do
    from(line_item in InvoiceLineItem,
      left_join: category in assoc(line_item, :category),
      preload: [category: category],
      order_by: [asc: line_item.inserted_at, asc: line_item.id]
    )
  end

  defp vendor_invoice_query(opts) do
    from(invoice in Invoice, as: :invoice)
    |> join(:left, [invoice], settlement in assoc(invoice, :transaction), as: :settlement)
    |> preload([:document, transaction: [:category], line_items: ^line_items_query()])
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_vendor(Keyword.get(opts, :vendor))
    |> maybe_filter_category_slug(Keyword.get(opts, :category_slug))
    |> maybe_filter_settlement_date_from(Keyword.get(opts, :date_from))
    |> maybe_filter_settlement_date_to(Keyword.get(opts, :date_to))
    |> where([invoice], not is_nil(invoice.total_amount_value) and not is_nil(invoice.total_amount_currency))
    |> order_by([invoice], desc_nulls_last: invoice.invoice_date, desc: invoice.inserted_at)
  end

  defp dominant_currency([]), do: "EUR"

  defp dominant_currency(invoices) do
    invoices
    |> Enum.group_by(& &1.total_amount_currency)
    |> Enum.max_by(fn {currency, invoices} -> {length(invoices), currency} end)
    |> elem(0)
  end

  defp currency_summaries(invoices) do
    invoices
    |> Enum.group_by(& &1.total_amount_currency)
    |> Enum.map(fn {currency, currency_invoices} ->
      %{
        currency: currency,
        total_spend_value: sum_decimals(currency_invoices, &(&1.total_amount_value || @zero)),
        invoice_count: length(currency_invoices),
        vendor_count:
          currency_invoices
          |> Enum.map(& &1.vendor_name)
          |> Enum.uniq()
          |> length()
      }
    end)
    |> Enum.sort_by(& &1.currency)
  end

  defp load_exchange_rates(report_currency, invoices, opts) do
    currencies =
      invoices
      |> Enum.flat_map(fn invoice ->
        [invoice.total_amount_currency | Enum.map(invoice.line_items, & &1.amount_currency)]
      end)
      |> Kernel.++([report_currency])
      |> Enum.map(&Amounts.normalize_currency/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "EUR"))

    case exchange_rates_client(opts).latest_rates(currencies) do
      {:ok, exchange_rates} -> Map.put(exchange_rates, :report_currency, report_currency)
      {:error, _reason} -> %{published_on: nil, rates: %{}, report_currency: report_currency}
    end
  end

  defp exchange_rates_client(opts) do
    Keyword.get(opts, :exchange_rates_client) ||
      :atlas
      |> Application.get_env(:accounts, [])
      |> Keyword.get(:exchange_rates_client, ExchangeRates)
  end

  defp convert_invoices(invoices, report_currency, exchange_rates) do
    Enum.flat_map(invoices, fn invoice ->
      case convert(invoice.total_amount_value, invoice.total_amount_currency, report_currency, exchange_rates) do
        {:ok, total_amount_value} ->
          [
            %{
              invoice
              | total_amount_value: total_amount_value,
                total_amount_currency: report_currency,
                line_items: convert_line_items(invoice, report_currency, exchange_rates)
            }
          ]

        :skip ->
          []
      end
    end)
  end

  defp convert_line_items(invoice, report_currency, exchange_rates) do
    Enum.map(invoice.line_items, fn line_item ->
      source_currency = line_item.amount_currency || invoice.total_amount_currency

      case convert(line_item.amount_value, source_currency, report_currency, exchange_rates) do
        {:ok, amount_value} -> %{line_item | amount_value: amount_value, amount_currency: report_currency}
        :skip -> line_item
      end
    end)
  end

  defp vendor_summaries(invoices) do
    invoices
    |> Enum.group_by(& &1.vendor_name)
    |> Enum.map(fn {vendor_name, vendor_invoices} ->
      line_items = invoice_line_item_pairs(vendor_invoices)

      %{
        id: stable_id("vendor", vendor_name),
        vendor_name: vendor_name,
        total_amount_value: sum_decimals(vendor_invoices, &(&1.total_amount_value || @zero)),
        total_amount_currency: dominant_currency(vendor_invoices),
        invoice_count: length(vendor_invoices),
        line_item_count: length(line_items),
        needs_review_count: Enum.count(vendor_invoices, &(&1.status == "needs_review")),
        last_invoice_date: last_invoice_date(vendor_invoices),
        categories: top_category_names(vendor_invoices)
      }
    end)
    |> Enum.sort_by(& &1.total_amount_value, {:desc, Decimal})
  end

  defp category_summaries(invoices) do
    invoices
    |> invoice_line_item_pairs()
    |> Enum.filter(fn {_invoice, line_item} -> match?(%Decimal{}, line_item.amount_value) end)
    |> Enum.group_by(fn {invoice, line_item} ->
      line_item_category_name(line_item, invoice)
    end)
    |> Enum.map(fn {category_name, pairs} ->
      line_items = Enum.map(pairs, &elem(&1, 1))

      %{
        id: stable_id("category", category_name),
        category_name: category_name,
        amount_value: sum_decimals(line_items, & &1.amount_value),
        amount_currency: dominant_line_currency(line_items),
        line_item_count: length(line_items)
      }
    end)
    |> Enum.sort_by(& &1.amount_value, {:desc, Decimal})
    |> Enum.take(8)
  end

  # Buckets invoice spend by the month the cash actually moved — the linked
  # transaction's settlement date — so the vendor spend trend lines up with the
  # cash overview's expense calendar. Invoices with no linked transaction fall
  # back to their own invoice date.
  defp monthly_spend(invoices) do
    invoices
    |> Enum.map(&{effective_date(&1), &1})
    |> Enum.filter(fn {date, _invoice} -> match?(%Date{}, date) end)
    |> Enum.group_by(fn {date, _invoice} -> Date.beginning_of_month(date) end)
    |> Enum.map(fn {month, pairs} ->
      month_invoices = Enum.map(pairs, &elem(&1, 1))
      %{date: month, amount_value: sum_decimals(month_invoices, &(&1.total_amount_value || @zero))}
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  # The date Atlas treats an invoice as "spent": the linked transaction's
  # settlement date (settled / booked / provider-updated, matching
  # `Transaction.occurred_at`), falling back to the invoice date when nothing is
  # linked. Keep this in sync with the SQL `coalesce` in the settlement-date
  # filters below.
  defp effective_date(invoice) do
    case effective_datetime(invoice) do
      %DateTime{} = datetime -> DateTime.to_date(datetime)
      nil -> invoice.invoice_date
    end
  end

  defp effective_datetime(%{transaction: %Transaction{} = transaction}) do
    transaction.settled_at || transaction.booked_at || transaction.provider_updated_at
  end

  defp effective_datetime(_invoice), do: nil

  defp expense_summaries(invoices) do
    Enum.map(invoices, fn invoice ->
      %{
        id: invoice.id,
        vendor_name: invoice.vendor_name,
        invoice_number: invoice.invoice_number,
        invoice_date: invoice.invoice_date,
        document_id: invoice.document_id,
        finance_transaction_id: invoice.finance_transaction_id,
        transaction_reference: invoice.transaction && invoice.transaction.reference,
        transaction_external_id: invoice.transaction && invoice.transaction.external_id,
        transaction_counterparty_name: invoice.transaction && invoice.transaction.counterparty_name,
        status: invoice.status,
        total_amount_value: invoice.total_amount_value,
        total_amount_currency: invoice.total_amount_currency,
        categories: top_category_names([invoice]),
        line_items: expense_line_item_summaries(invoice)
      }
    end)
  end

  defp expense_line_item_summaries(invoice) do
    Enum.map(invoice.line_items, fn line_item ->
      %{
        id: line_item.id,
        description: line_item.description,
        category_name: line_item_category_name(line_item, invoice),
        amount_value: line_item.amount_value,
        amount_currency: line_item.amount_currency
      }
    end)
  end

  defp dominant_line_currency([]), do: "EUR"

  defp dominant_line_currency(line_items) do
    line_items
    |> Enum.group_by(& &1.amount_currency)
    |> Enum.max_by(fn {_currency, line_items} -> length(line_items) end)
    |> elem(0)
  end

  defp top_category_names(invoices) do
    invoices
    |> invoice_line_item_pairs()
    |> Enum.map(fn {invoice, line_item} ->
      line_item_category_name(line_item, invoice)
    end)
    |> Enum.reject(&blank?/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_name, count} -> count end, :desc)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(3)
  end

  defp invoice_line_item_pairs(invoices) do
    Enum.flat_map(invoices, fn invoice ->
      Enum.map(invoice.line_items, &{invoice, &1})
    end)
  end

  defp line_item_category_name(line_item, invoice) do
    line_item
    |> raw_line_item_category_name(invoice)
    |> Category.display_name()
    |> case do
      nil -> "Uncategorized"
      name -> name
    end
  end

  defp raw_line_item_category_name(line_item, invoice) do
    (line_item.category && line_item.category.name) ||
      line_item.cost_type ||
      (invoice.transaction && invoice.transaction.category && invoice.transaction.category.name)
  end

  defp last_invoice_date(invoices) do
    invoices
    |> Enum.map(& &1.invoice_date)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.max_by(dates, &Date.to_iso8601/1)
    end
  end

  defp concentration_percent([], _total_spend), do: nil

  defp concentration_percent(vendors, total_spend) do
    top_five_spend =
      vendors
      |> Enum.take(5)
      |> sum_decimals(& &1.total_amount_value)

    if !Decimal.equal?(total_spend, @zero) do
      top_five_spend
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.div(total_spend)
      |> Decimal.round(1)
    end
  end

  defp sum_decimals(items, fun) do
    Enum.reduce(items, @zero, fn item, acc ->
      case fun.(item) do
        %Decimal{} = value -> Decimal.add(acc, value)
        _value -> acc
      end
    end)
  end

  defp stable_id(prefix, value) do
    slug =
      value
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{prefix}-#{slug}"
  end

  defp put_line_item_category(attrs) do
    case Map.get(attrs, :category_name) || Map.get(attrs, "category_name") do
      name when is_binary(name) ->
        case resolve_category(name) do
          %Category{id: id} -> Map.put(attrs, :finance_category_id, id)
          nil -> attrs
        end

      _other ->
        attrs
    end
    |> Map.drop([:category_name, "category_name"])
  end

  defp resolve_category(name) do
    slug = Category.slugify(name)

    Repo.get_by(Category, slug: slug) ||
      %Category{}
      |> Category.changeset(%{
        name: name,
        direction: "debit",
        created_by_agent: "finance_invoice_extractor",
        metadata: %{"source" => "invoice_line_item"}
      })
      |> Repo.insert()
      |> case do
        {:ok, category} -> category
        {:error, _changeset} -> Repo.get_by(Category, slug: slug)
      end
  end

  defp status_for([]), do: "needs_review"
  defp status_for(_line_items), do: "extracted"

  defp audit_invoice(action, %Invoice{} = invoice, line_items, opts) do
    Audit.record(
      action,
      %{
        target_type: "finance_invoice",
        target_id: invoice.id,
        target_label: invoice.vendor_name,
        metadata: %{
          "path" => "/finance",
          "document_id" => invoice.document_id,
          "document_path" => invoice.document_id && "/documents/#{invoice.document_id}",
          "finance_transaction_id" => invoice.finance_transaction_id,
          "line_item_count" => length(line_items),
          "total_amount_value" => decimal_to_string(invoice.total_amount_value),
          "total_amount_currency" => invoice.total_amount_currency
        }
      },
      opts
    )
  end

  defp maybe_filter_status(query, status) when status in ["extracted", "needs_review", "failed"] do
    where(query, [invoice], invoice.status == ^status)
  end

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_vendor(query, vendor) when is_binary(vendor) and vendor != "" do
    where(query, [invoice], ilike(invoice.vendor_name, ^"%#{String.trim(vendor)}%"))
  end

  defp maybe_filter_vendor(query, _vendor), do: query

  defp maybe_filter_category_slug(query, category_slug) when is_binary(category_slug) and category_slug != "" do
    where(
      query,
      [invoice],
      exists(
        from line_item in InvoiceLineItem,
          join: category in assoc(line_item, :category),
          where: line_item.finance_invoice_id == parent_as(:invoice).id and category.slug == ^category_slug
      )
    )
  end

  defp maybe_filter_category_slug(query, _category_slug), do: query

  defp maybe_filter_date_from(query, %Date{} = date_from) do
    where(query, [invoice], invoice.invoice_date >= ^date_from)
  end

  defp maybe_filter_date_from(query, _date_from), do: query

  defp maybe_filter_date_to(query, %Date{} = date_to) do
    where(query, [invoice], invoice.invoice_date <= ^date_to)
  end

  defp maybe_filter_date_to(query, _date_to), do: query

  # Range filters on the invoice's settlement date (linked transaction), falling
  # back to the invoice date. Mirrors `effective_date/1` so the date picker on
  # the vendor page scopes invoices to the same calendar the spend trend buckets
  # by. Requires the `:settlement` join added in `vendor_invoice_query/1`.
  defp maybe_filter_settlement_date_from(query, %Date{} = date_from) do
    where(
      query,
      [invoice: invoice, settlement: settlement],
      fragment(
        "coalesce(?::date, ?::date, ?::date, ?) >= ?",
        settlement.settled_at,
        settlement.booked_at,
        settlement.provider_updated_at,
        invoice.invoice_date,
        ^date_from
      )
    )
  end

  defp maybe_filter_settlement_date_from(query, _date_from), do: query

  defp maybe_filter_settlement_date_to(query, %Date{} = date_to) do
    where(
      query,
      [invoice: invoice, settlement: settlement],
      fragment(
        "coalesce(?::date, ?::date, ?::date, ?) <= ?",
        settlement.settled_at,
        settlement.booked_at,
        settlement.provider_updated_at,
        invoice.invoice_date,
        ^date_to
      )
    )
  end

  defp maybe_filter_settlement_date_to(query, _date_to), do: query

  defp maybe_filter_query(query, value) when is_binary(value) and value != "" do
    pattern = "%#{String.trim(value)}%"

    where(
      query,
      [invoice, document: document],
      ilike(invoice.vendor_name, ^pattern) or
        ilike(fragment("coalesce(?, '')", invoice.invoice_number), ^pattern) or
        ilike(fragment("coalesce(?, '')", document.title), ^pattern) or
        exists(
          from line_item in InvoiceLineItem,
            where: line_item.finance_invoice_id == parent_as(:invoice).id,
            where:
              ilike(line_item.description, ^pattern) or
                ilike(fragment("coalesce(?, '')", line_item.cost_type), ^pattern)
        )
    )
  end

  defp maybe_filter_query(query, _value), do: query

  defp maybe_filter_line_currency(query, currency) when is_binary(currency) and currency != "" do
    where(query, [line_item], line_item.amount_currency == ^currency)
  end

  defp maybe_filter_line_currency(query, _currency), do: query

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)

  defp convert(nil, _currency, _report_currency, _exchange_rates), do: :skip
  defp convert(_value, nil, _report_currency, _exchange_rates), do: :skip

  defp convert(%Decimal{} = value, currency, report_currency, exchange_rates) do
    source_currency = Amounts.normalize_currency(currency)
    target_currency = Amounts.normalize_currency(report_currency)

    cond do
      is_nil(source_currency) or is_nil(target_currency) ->
        :skip

      source_currency == target_currency ->
        {:ok, value}

      source_currency == "EUR" ->
        multiply_by_rate(value, target_currency, exchange_rates)

      target_currency == "EUR" ->
        divide_by_rate(value, source_currency, exchange_rates)

      true ->
        convert_via_eur(value, source_currency, target_currency, exchange_rates)
    end
  end

  defp convert(_value, _currency, _report_currency, _exchange_rates), do: :skip

  defp multiply_by_rate(value, currency, exchange_rates) do
    case Map.get(exchange_rates.rates, currency) do
      %Decimal{} = rate -> {:ok, Decimal.mult(value, rate)}
      _missing -> :skip
    end
  end

  defp divide_by_rate(value, currency, exchange_rates) do
    case Map.get(exchange_rates.rates, currency) do
      %Decimal{} = rate -> {:ok, Decimal.div(value, rate)}
      _missing -> :skip
    end
  end

  defp convert_via_eur(value, source_currency, target_currency, exchange_rates) do
    with {:ok, eur_value} <- divide_by_rate(value, source_currency, exchange_rates),
         {:ok, target_value} <- multiply_by_rate(eur_value, target_currency, exchange_rates) do
      {:ok, target_value}
    else
      _error -> :skip
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
