defmodule Atlas.Finance.QueryTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures
  import Atlas.MCP.ToolCase, only: [insert_account!: 1]

  alias Atlas.Finance.Query

  test "filters finance accounts by linked company, provider, currency, and search" do
    tuist_gmbh = insert_account!(%{name: "Tuist GmbH", segment: :customer})
    tuist_inc = insert_account!(%{name: "Tuist Inc.", segment: :customer})

    qonto_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_gmbh.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    mercury_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_inc.id,
        provider: "mercury",
        config_key: "mercury-main",
        name: "Mercury Main"
      })

    _qonto_account = insert_finance_account!(qonto_source, %{name: "Operating", currency: "EUR", iban: "FR76"})

    mercury_account =
      insert_finance_account!(mercury_source, %{
        name: "US Operating",
        currency: "USD",
        balance_currency: "USD",
        available_balance_currency: "USD"
      })

    assert [result] =
             Query.list_accounts(
               atlas_account_key: tuist_inc.account_key,
               provider: "mercury",
               currency: "USD",
               query: "Operating"
             )

    assert result.id == mercury_account.id
    assert result.source.atlas_account.name == "Tuist Inc."
  end

  test "filters transactions by linked company, source, direction, currency, date, and search" do
    tuist_gmbh = insert_account!(%{name: "Tuist GmbH", segment: :customer})
    tuist_inc = insert_account!(%{name: "Tuist Inc.", segment: :customer})

    qonto_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_gmbh.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    mercury_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_inc.id,
        provider: "mercury",
        config_key: "mercury-main",
        name: "Mercury Main"
      })

    qonto_account = insert_finance_account!(qonto_source, %{name: "Operating", currency: "EUR"})
    mercury_account = insert_finance_account!(mercury_source, %{name: "US Operating", currency: "USD"})

    payroll =
      insert_finance_transaction!(qonto_account, %{
        external_id: "txn-payroll",
        direction: "debit",
        kind: "salary",
        counterparty_name: "Payroll Provider",
        description: "Monthly payroll",
        amount_value: Decimal.new("2500.00"),
        amount_currency: "EUR",
        booked_at: ~U[2026-05-20 09:00:00Z],
        settled_at: ~U[2026-05-20 09:00:00Z],
        provider_updated_at: ~U[2026-05-20 09:00:00Z]
      })

    _mercury_credit =
      insert_finance_transaction!(mercury_account, %{
        external_id: "txn-contract",
        direction: "credit",
        kind: "incoming_domestic_wire",
        counterparty_name: "Acme Inc.",
        amount_value: Decimal.new("36000.00"),
        amount_currency: "USD",
        booked_at: ~U[2026-05-21 09:00:00Z],
        settled_at: ~U[2026-05-21 09:00:00Z],
        provider_updated_at: ~U[2026-05-21 09:00:00Z]
      })

    assert [result] =
             Query.list_transactions(
               atlas_account_key: tuist_gmbh.account_key,
               source_key: qonto_source.config_key,
               direction: "debit",
               currency: "EUR",
               date_from: ~U[2026-05-01 00:00:00Z],
               date_to: ~U[2026-05-31 23:59:59Z],
               query: "payroll"
             )

    assert result.id == payroll.id
    assert result.account.source.atlas_account.account_key == tuist_gmbh.account_key
  end

  test "filters transactions by category and uncategorized state" do
    source = insert_finance_source!(%{config_key: "qonto-main"})
    account = insert_finance_account!(source)
    category = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})

    categorized =
      insert_finance_transaction!(account, %{
        external_id: "txn-cloud",
        finance_category_id: category.id,
        categorized_at: ~U[2026-05-20 09:00:00Z]
      })

    uncategorized = insert_finance_transaction!(account, %{external_id: "txn-unknown"})

    assert [result] = Query.list_transactions(category_id: category.id)
    assert result.id == categorized.id
    assert result.category.name == "Cloud Infrastructure"

    assert [result] = Query.list_transactions(category_slug: category.slug)
    assert result.id == categorized.id

    assert [result] = Query.list_transactions(uncategorized: true)
    assert result.id == uncategorized.id
  end

  test "paginates transactions with total metadata" do
    source = insert_finance_source!(%{config_key: "qonto-main"})
    account = insert_finance_account!(source)

    newest =
      insert_finance_transaction!(account, %{
        external_id: "txn-newest",
        counterparty_name: "Newest",
        settled_at: ~U[2026-05-03 09:00:00Z],
        booked_at: ~U[2026-05-03 09:00:00Z],
        provider_updated_at: ~U[2026-05-03 09:00:00Z]
      })

    _middle =
      insert_finance_transaction!(account, %{
        external_id: "txn-middle",
        counterparty_name: "Middle",
        settled_at: ~U[2026-05-02 09:00:00Z],
        booked_at: ~U[2026-05-02 09:00:00Z],
        provider_updated_at: ~U[2026-05-02 09:00:00Z]
      })

    oldest =
      insert_finance_transaction!(account, %{
        external_id: "txn-oldest",
        counterparty_name: "Oldest",
        settled_at: ~U[2026-05-01 09:00:00Z],
        booked_at: ~U[2026-05-01 09:00:00Z],
        provider_updated_at: ~U[2026-05-01 09:00:00Z]
      })

    assert {[first], meta} = Query.list_transactions_page(page: 1, page_size: 1)
    assert first.id == newest.id
    assert meta.current_page == 1
    assert meta.page_size == 1
    assert meta.total_count == 3
    assert meta.total_pages == 3
    assert meta.has_next_page?
    refute meta.has_previous_page?

    assert {[third], meta} = Query.list_transactions_page(page: 3, page_size: 1)
    assert third.id == oldest.id
    assert meta.current_page == 3
    refute meta.has_next_page?
    assert meta.has_previous_page?
  end

  test "lists extracted invoices with line item category filters" do
    category = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})
    invoice = insert_finance_invoice!(%{vendor_name: "AWS", invoice_number: "AWS-2026-05"})

    insert_finance_invoice_line_item!(invoice, %{
      finance_category_id: category.id,
      description: "EC2 compute",
      amount_value: Decimal.new("75.00")
    })

    assert [result] = Atlas.Finance.list_invoices(category_slug: category.slug, query: "compute")
    assert result.id == invoice.id
    assert [%{category: %{name: "Cloud Infrastructure"}}] = result.line_items
  end

  test "builds vendor cost analytics from extracted invoices and line items" do
    cloud = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})
    software = insert_finance_category!(%{name: "Software", direction: "debit"})

    aws_june =
      insert_finance_invoice!(%{
        vendor_name: "Amazon Web Services",
        invoice_number: "AWS-2026-06",
        invoice_date: ~D[2026-06-01],
        total_amount_value: Decimal.new("6700.00"),
        total_amount_currency: "EUR"
      })

    aws_may =
      insert_finance_invoice!(%{
        vendor_name: "Amazon Web Services",
        invoice_number: "AWS-2026-05",
        invoice_date: ~D[2026-05-01],
        total_amount_value: Decimal.new("3300.00"),
        total_amount_currency: "EUR"
      })

    linear =
      insert_finance_invoice!(%{
        vendor_name: "Linear",
        invoice_number: "LINEAR-2026-05",
        invoice_date: ~D[2026-05-01],
        total_amount_value: Decimal.new("980.00"),
        total_amount_currency: "EUR"
      })

    _needs_review =
      insert_finance_invoice!(%{
        vendor_name: "Unparsed Vendor",
        invoice_number: nil,
        invoice_date: ~D[2026-05-01],
        status: "needs_review",
        total_amount_value: Decimal.new("200.00"),
        total_amount_currency: "EUR"
      })

    insert_finance_invoice_line_item!(aws_june, %{
      finance_category_id: cloud.id,
      description: "EC2 compute",
      amount_value: Decimal.new("5200.00")
    })

    insert_finance_invoice_line_item!(aws_june, %{
      finance_category_id: cloud.id,
      description: "S3 storage",
      amount_value: Decimal.new("1500.00")
    })

    insert_finance_invoice_line_item!(aws_may, %{
      finance_category_id: cloud.id,
      description: "May infrastructure",
      amount_value: Decimal.new("3300.00")
    })

    insert_finance_invoice_line_item!(linear, %{
      finance_category_id: software.id,
      description: "Seats",
      amount_value: Decimal.new("980.00")
    })

    analytics = Atlas.Finance.vendor_cost_analytics()

    assert analytics.currency == "EUR"
    assert analytics.invoice_count == 4
    assert analytics.vendor_count == 3
    assert analytics.needs_review_count == 1
    assert Decimal.equal?(analytics.total_spend_value, Decimal.new("11180.00"))
    assert analytics.top_vendor.vendor_name == "Amazon Web Services"
    assert Decimal.equal?(analytics.top_vendor.total_amount_value, Decimal.new("10000.00"))
    assert [%{category_name: "Cloud Infrastructure", line_item_count: 3} | _rest] = analytics.categories
    assert Enum.map(analytics.monthly_spend, & &1.date) == [~D[2026-05-01], ~D[2026-06-01]]

    assert Enum.any?(analytics.expenses, fn expense ->
             expense.vendor_name == "Amazon Web Services" and not Enum.empty?(expense.line_items)
           end)
  end

  test "reports mixed-currency vendor analytics in EUR" do
    cloud = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})

    grafana =
      insert_finance_invoice!(%{
        vendor_name: "Grafana Labs",
        invoice_number: "GRAFANA-2026-06",
        invoice_date: ~D[2026-06-01],
        total_amount_value: Decimal.new("117.02"),
        total_amount_currency: "USD"
      })

    hetzner =
      insert_finance_invoice!(%{
        vendor_name: "Hetzner Online GmbH",
        invoice_number: "083000902413",
        invoice_date: ~D[2026-05-27],
        total_amount_value: Decimal.new("50.00"),
        total_amount_currency: "EUR"
      })

    insert_finance_invoice_line_item!(grafana, %{
      finance_category_id: cloud.id,
      description: "Observability",
      amount_value: Decimal.new("117.02"),
      amount_currency: "USD"
    })

    insert_finance_invoice_line_item!(hetzner, %{
      description: "Cloud server",
      amount_value: Decimal.new("50.00"),
      amount_currency: "EUR",
      cost_type: "compute"
    })

    analytics = Atlas.Finance.vendor_cost_analytics(currency: "usd")

    assert analytics.currency == "EUR"
    assert analytics.default_currency == "EUR"
    assert Enum.map(analytics.available_currencies, & &1.currency) == ["EUR"]
    assert analytics.invoice_count == 2
    assert analytics.vendor_count == 2
    assert Decimal.equal?(Decimal.round(analytics.total_spend_value, 2), Decimal.new("150.00"))

    assert [%{vendor_name: "Grafana Labs", total_amount_currency: "EUR"} | _rest] = analytics.vendors

    assert Decimal.equal?(
             Decimal.round(analytics.top_vendor.total_amount_value, 2),
             Decimal.new("100.00")
           )

    assert [%{category_name: "Cloud Infrastructure", amount_currency: "EUR", line_item_count: 1} | _rest] =
             analytics.categories
  end

  test "normalizes raw extracted category labels in vendor cost analytics" do
    subscription_invoice =
      insert_finance_invoice!(%{
        vendor_name: "Subscription Vendor",
        invoice_number: "SUB-2026-06",
        invoice_date: ~D[2026-06-01],
        total_amount_value: Decimal.new("70.00"),
        total_amount_currency: "EUR"
      })

    software_invoice =
      insert_finance_invoice!(%{
        vendor_name: "Software Vendor",
        invoice_number: "SOFT-2026-06",
        invoice_date: ~D[2026-06-02],
        total_amount_value: Decimal.new("30.00"),
        total_amount_currency: "EUR"
      })

    insert_finance_invoice_line_item!(subscription_invoice, %{
      description: "Monthly subscription",
      cost_type: "subscription",
      amount_value: Decimal.new("70.00")
    })

    insert_finance_invoice_line_item!(software_invoice, %{
      description: "Seats",
      cost_type: "software_subscriptions",
      amount_value: Decimal.new("30.00")
    })

    analytics = Atlas.Finance.vendor_cost_analytics()

    assert [%{category_name: "Software Subscription", line_item_count: 2}] = analytics.categories

    assert Enum.all?(analytics.expenses, fn expense ->
             expense.categories == ["Software Subscription"] and
               Enum.all?(expense.line_items, &(&1.category_name == "Software Subscription"))
           end)
  end

  test "reports USD-only vendor cost analytics in EUR" do
    insert_finance_invoice!(%{
      vendor_name: "Grafana Labs",
      invoice_number: "GRAFANA-2026-06",
      invoice_date: ~D[2026-06-01],
      total_amount_value: Decimal.new("117.02"),
      total_amount_currency: "USD"
    })

    analytics = Atlas.Finance.vendor_cost_analytics()

    assert analytics.currency == "EUR"
    assert analytics.default_currency == "EUR"
    assert Enum.map(analytics.available_currencies, & &1.currency) == ["EUR"]
    assert analytics.invoice_count == 1
    assert analytics.vendor_count == 1
    assert Decimal.equal?(Decimal.round(analytics.total_spend_value, 2), Decimal.new("100.00"))
    assert [%{vendor_name: "Grafana Labs", total_amount_currency: "EUR"}] = analytics.vendors
  end

  test "uses linked transaction category when extracted invoice lines are uncategorized" do
    software = insert_finance_category!(%{name: "Software", direction: "debit"})
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})
    account = insert_finance_account!(source, %{name: "Operating", currency: "USD"})

    transaction =
      insert_finance_transaction!(account, %{
        counterparty_name: "Supabase Pte. Ltd.",
        finance_category_id: software.id,
        amount_value: Decimal.new("967.26"),
        amount_currency: "USD"
      })

    invoice =
      insert_finance_invoice!(%{
        vendor_name: "Supabase Pte. Ltd.",
        invoice_number: "ZTZBQM-00023",
        invoice_date: ~D[2026-06-05],
        finance_transaction_id: transaction.id,
        total_amount_value: Decimal.new("967.26"),
        total_amount_currency: "USD"
      })

    insert_finance_invoice_line_item!(invoice, %{
      description: "Team plan",
      amount_value: Decimal.new("967.26"),
      amount_currency: "USD"
    })

    analytics = Atlas.Finance.vendor_cost_analytics()

    assert [%{category_name: "Software", amount_currency: "EUR", line_item_count: 1}] = analytics.categories

    assert [%{categories: ["Software"], line_items: [%{category_name: "Software", amount_currency: "EUR"}]}] =
             analytics.expenses
  end
end
