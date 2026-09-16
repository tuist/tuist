defmodule AtlasWeb.FinanceLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.FinanceFixtures
  import Atlas.MCP.ToolCase, only: [insert_account!: 1]
  import Phoenix.LiveViewTest

  alias Atlas.Documents.Document

  test "renders finance overview, accounts, and transactions", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance@example.com", role: :executive})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    company = insert_account!(%{name: "Tuist GmbH", segment: :customer})
    debit_at = DateTime.add(now, -10, :day)
    credit_at = DateTime.add(now, -15, :day)

    source =
      insert_finance_source!(%{
        atlas_account_id: company.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main",
        last_successful_sync_at: ~U[2026-05-26 08:00:00Z]
      })

    account =
      insert_finance_account!(source, %{
        name: "Operating",
        balance_value: Decimal.new("1000.00"),
        available_balance_value: Decimal.new("900.00")
      })

    transaction =
      insert_finance_transaction!(account, %{
        external_id: "txn-payroll",
        direction: "debit",
        kind: "salary",
        counterparty_name: "Payroll Provider",
        description: "Monthly payroll",
        amount_value: Decimal.new("120.00"),
        booked_at: debit_at,
        settled_at: debit_at,
        provider_updated_at: debit_at
      })

    _credit =
      insert_finance_transaction!(account, %{
        external_id: "txn-credit",
        direction: "credit",
        kind: "invoice_payment",
        counterparty_name: "Customer",
        description: "Invoice settlement",
        amount_value: Decimal.new("30.00"),
        booked_at: credit_at,
        settled_at: credit_at,
        provider_updated_at: credit_at
      })

    invoice = insert_finance_invoice!(%{vendor_name: "Amazon Web Services", invoice_number: "AWS-2026-06"})
    insert_finance_invoice_line_item!(invoice, %{description: "Compute workloads"})

    {:ok, view, _html} = live(conn, ~p"/finance")

    assert has_element?(view, "#finance")
    assert has_element?(view, "#finance-filters-dropdown")
    assert has_element?(view, "#finance-transactions-date-range-picker")
    assert has_element?(view, "#finance-runway-date-range-picker")
    assert has_element?(view, "#finance-search-form")
    assert has_element?(view, "#finance-widget-runway")
    assert has_element?(view, "#finance-widget-available-cash [data-part='value']", "EUR 900.00")
    assert has_element?(view, "#finance-widget-income [data-part='title']", "Income this month")
    assert has_element?(view, "#finance-widget-monthly-burn [data-part='title']", "Monthly burn")
    # Explanatory copy lives in the tooltip, not inline in the widget body.
    assert has_element?(view, "#finance-widget-monthly-burn [data-part='tooltip']")

    assert has_element?(view, "#finance-widget-runway [data-part='title']", "Runway")
    assert has_element?(view, "#finance-widget-committed-pipeline [data-part='title']", "Committed pipeline")
    assert has_element?(view, "#finance-widget-projected-runway [data-part='title']", "Plan-adjusted runway")
    assert has_element?(view, "#finance-last-synced", "Last sync 2026-05-26 08:00 UTC")
    # Runway is selected by default and renders its own chart.
    assert has_element?(view, "#finance-runway-chart")
    refute has_element?(view, "#finance-balance-chart")
    assert has_element?(view, ~s(#finance-accounts-table tr[id="#{account.id}"]), "Operating")
    assert has_element?(view, "#finance-accounts-table", "Tuist GmbH")
    assert has_element?(view, "#finance-invoices-table", "Amazon Web Services")
    assert has_element?(view, "#finance-invoices-table", "AWS-2026-06")
    assert has_element?(view, "#finance-vendors-link")
    assert has_element?(view, ~s(#finance-transactions-table tr[id="#{transaction.id}"]), "Payroll Provider")
    assert has_element?(view, "#finance-transactions-result-count", "2 transactions")
  end

  test "paginates finance transactions", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-pagination@example.com", role: :executive})

    source =
      insert_finance_source!(%{
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    account = insert_finance_account!(source, %{name: "Operating"})

    for day <- 1..26 do
      booked_at = ~D[2026-05-01] |> Date.add(day) |> DateTime.new!(~T[09:00:00], "Etc/UTC")
      counterparty_name = if day == 1, do: "Oldest Vendor", else: "Paged Vendor #{day}"

      insert_finance_transaction!(account, %{
        external_id: "txn-page-#{day}",
        counterparty_name: counterparty_name,
        booked_at: booked_at,
        settled_at: booked_at,
        provider_updated_at: booked_at
      })
    end

    {:ok, view, _html} = live(conn, ~p"/finance")

    assert has_element?(view, "#finance-transactions-pagination")
    assert has_element?(view, "#finance-transactions-result-count", "26 transactions")
    assert has_element?(view, "#finance-transactions-table", "Paged Vendor 26")
    refute has_element?(view, "#finance-transactions-table", "Oldest Vendor")

    view
    |> element(~s(#finance-transactions-pagination a[data-part="page-button"][href*="transactions-page=2"]))
    |> render_click()

    assert_patched(view, ~p"/finance?transactions-page=2")
    assert has_element?(view, "#finance-transactions-table", "Oldest Vendor")
  end

  test "renders vendor cost analytics page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors@example.com", role: :executive})
    cloud = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})
    software = insert_finance_category!(%{name: "Software", direction: "debit"})
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})
    account = insert_finance_account!(source, %{name: "Operating"})

    transaction =
      insert_finance_transaction!(account, %{
        external_id: "txn-aws-2026-06",
        reference: "AWS-2026-06",
        counterparty_name: "Amazon Web Services",
        amount_value: Decimal.new("6700.00"),
        # Vendor spend is scoped and bucketed by the linked transaction's
        # settlement date, so pin it to the invoice's month.
        booked_at: ~U[2026-06-01 10:00:00Z],
        settled_at: ~U[2026-06-01 10:00:00Z],
        provider_updated_at: ~U[2026-06-01 10:00:00Z]
      })

    document =
      insert_document!(%{
        title: "AWS invoice",
        original_filename: "aws-invoice.txt",
        source: "qonto"
      })

    aws =
      insert_finance_invoice!(%{
        vendor_name: "Amazon Web Services",
        invoice_number: "AWS-2026-06",
        invoice_date: ~D[2026-06-01],
        document_id: document.id,
        finance_transaction_id: transaction.id,
        total_amount_value: Decimal.new("6700.00"),
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

    insert_finance_invoice!(%{
      vendor_name: "Unparsed Vendor",
      invoice_number: nil,
      invoice_date: ~D[2026-05-01],
      status: "needs_review",
      total_amount_value: Decimal.new("100.00"),
      total_amount_currency: "EUR"
    })

    insert_finance_invoice_line_item!(aws, %{
      finance_category_id: cloud.id,
      description: "EC2 compute",
      amount_value: Decimal.new("5200.00")
    })

    insert_finance_invoice_line_item!(aws, %{
      finance_category_id: cloud.id,
      description: "S3 storage",
      amount_value: Decimal.new("1500.00")
    })

    insert_finance_invoice_line_item!(linear, %{
      finance_category_id: software.id,
      description: "Seats",
      amount_value: Decimal.new("980.00")
    })

    {:ok, view, _html} = live(conn, ~p"/finance/vendors")

    assert has_element?(view, "#finance-vendors")
    assert has_element?(view, "#finance-vendors-date-range-picker")
    assert has_element?(view, "#finance-vendors-widget-spend [data-part='value']", "EUR 7.8K")
    assert has_element?(view, "#finance-vendors-widget-top-vendor", "Amazon Web Services")
    assert has_element?(view, "#finance-vendors-widget-categories", "Cloud Infrastructure")
    assert has_element?(view, "#finance-vendors-spend-chart")
    refute has_element?(view, "#finance-vendors-category-chart")

    render_click(view, "select_chart", %{"widget" => "vendors"})

    assert_patched(view, ~p"/finance/vendors?vendors-chart=vendors")
    assert has_element?(view, "#finance-vendors-vendor-chart")

    render_click(view, "select_chart", %{"widget" => "categories"})

    assert_patched(view, ~p"/finance/vendors?vendors-chart=categories")
    assert has_element?(view, "#finance-vendors-category-chart")
    assert has_element?(view, "#finance-vendors-expenses-list", "Cloud Infrastructure")
    assert has_element?(view, "#finance-vendors-expenses-list", "EC2 compute")
    assert has_element?(view, "#finance-vendors-expenses-list", "S3 storage")
    assert has_element?(view, ~s(a[href="/documents/#{document.id}"]), "Amazon Web Services")

    assert has_element?(
             view,
             "#finance-vendors-expenses-list [data-part='transaction-reference']",
             "Amazon Web Services"
           )

    refute has_element?(view, ~s(a[href="/finance?search=AWS-2026-06"]))
    assert has_element?(view, "#finance-vendors-expenses-list", "Linear")

    render_hook(view, "vendors_period_changed", %{
      "preset" => "custom",
      "value" => %{"start" => "2026-05-02", "end" => "2026-06-01"}
    })

    assert_patched(
      view,
      ~p"/finance/vendors?vendors-chart=categories&vendors-date-range=custom&vendors-end-date=2026-06-01&vendors-start-date=2026-05-02"
    )

    assert has_element?(view, "#finance-vendors-invoice-count", "1 invoice")
    assert has_element?(view, "#finance-vendors-widget-spend [data-part='value']", "EUR 6.7K")
    refute has_element?(view, "#finance-vendors-expenses-list", "Linear")
  end

  test "renders vendor cost expenses empty state", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors-empty@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/finance/vendors")

    assert has_element?(view, "#finance-vendors-expenses-empty")

    assert has_element?(
             view,
             "#finance-vendors-expenses-empty [data-part='expenses-empty-title']",
             "No expenses in this period"
           )

    assert has_element?(view, "#finance-vendors-expenses-empty [data-part='expenses-empty-icon'] svg")
  end

  test "paginates vendor cost expenses", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors-expenses-pagination@example.com", role: :executive})

    for day <- 1..11 do
      invoice_date = ~D[2026-05-01] |> Date.add(day)
      vendor_name = if day == 1, do: "Oldest Expense Vendor", else: "Paged Expense Vendor #{day}"

      insert_finance_invoice!(%{
        vendor_name: vendor_name,
        invoice_number: "EXPENSE-#{day}",
        invoice_date: invoice_date,
        total_amount_value: Decimal.new("#{day}.00"),
        total_amount_currency: "EUR"
      })
    end

    {:ok, view, _html} = live(conn, ~p"/finance/vendors")

    assert has_element?(view, "#finance-vendors-expenses-pagination")
    assert has_element?(view, "#finance-vendors-expenses-list", "Paged Expense Vendor 11")
    refute has_element?(view, "#finance-vendors-expenses-list", "Oldest Expense Vendor")

    view
    |> element(~s(#finance-vendors-expenses-pagination a[data-part="page-button"][href*="vendors-expenses-page=2"]))
    |> render_click()

    assert_patched(view, ~p"/finance/vendors?vendors-expenses-page=2")
    assert has_element?(view, "#finance-vendors-expenses-list", "Oldest Expense Vendor")
    refute has_element?(view, "#finance-vendors-expenses-list", "Paged Expense Vendor 11")
  end

  test "filters vendor cost expenses", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors-expenses-filters@example.com", role: :executive})
    cloud = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})
    software = insert_finance_category!(%{name: "Software", direction: "debit"})

    aws =
      insert_finance_invoice!(%{
        vendor_name: "Amazon Web Services",
        invoice_number: "AWS-2026-06",
        invoice_date: ~D[2026-06-01],
        total_amount_value: Decimal.new("240.00"),
        total_amount_currency: "EUR"
      })

    linear =
      insert_finance_invoice!(%{
        vendor_name: "Linear",
        invoice_number: "LINEAR-2026-06",
        invoice_date: ~D[2026-06-02],
        total_amount_value: Decimal.new("120.00"),
        total_amount_currency: "EUR"
      })

    insert_finance_invoice_line_item!(aws, %{
      finance_category_id: cloud.id,
      description: "Compute",
      amount_value: Decimal.new("240.00")
    })

    insert_finance_invoice_line_item!(linear, %{
      finance_category_id: software.id,
      description: "Seats",
      amount_value: Decimal.new("120.00")
    })

    {:ok, view, _html} = live(conn, ~p"/finance/vendors")

    assert has_element?(view, "#finance-vendors-expenses-filters-dropdown")
    assert has_element?(view, "#finance-vendors-expenses-search-form")

    view
    |> form("#finance-vendors-expenses-search-form", expenses_search: %{query: "linear"})
    |> render_change()

    assert_patched(view, ~p"/finance/vendors?vendors-expenses-search=linear")
    assert has_element?(view, "#finance-vendors-expenses-list", "Linear")
    refute has_element?(view, "#finance-vendors-expenses-list", "Amazon Web Services")

    {:ok, filtered_view, _html} =
      live(
        conn,
        ~p"/finance/vendors?#{%{"filter_category_op" => "==", "filter_category_val" => "Cloud Infrastructure"}}"
      )

    assert has_element?(filtered_view, "#finance-vendors-expenses-list", "Amazon Web Services")
    refute has_element?(filtered_view, "#finance-vendors-expenses-list", "Linear")
  end

  test "caps vendor breakdown chart labels", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors-chart-limit@example.com", role: :executive})

    for index <- 1..14 do
      insert_finance_invoice!(%{
        vendor_name: "Chart Vendor #{index}",
        invoice_number: "CHART-#{index}",
        invoice_date: ~D[2026-06-01],
        total_amount_value: Decimal.new("#{index}.00"),
        total_amount_currency: "EUR"
      })
    end

    {:ok, view, _html} = live(conn, ~p"/finance/vendors?vendors-chart=vendors")

    assert has_element?(view, "#finance-vendors-vendor-chart")

    assert has_element?(
             view,
             "#finance-vendors-vendor-chart-note",
             "Showing the top 12 vendors. 2 additional vendors account for EUR 3.00."
           )

    refute render(view) =~ "2 remaining vendors"
  end

  test "renders vendor costs in EUR and ignores stale currency parameter", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-vendors-currency@example.com", role: :executive})

    insert_finance_invoice!(%{
      vendor_name: "Grafana Labs",
      invoice_number: "GRAFANA-2026-06",
      invoice_date: ~D[2026-06-01],
      total_amount_value: Decimal.new("117.02"),
      total_amount_currency: "USD"
    })

    insert_finance_invoice!(%{
      vendor_name: "Hetzner Online GmbH",
      invoice_number: "083000902413",
      invoice_date: ~D[2026-05-27],
      total_amount_value: Decimal.new("50.00"),
      total_amount_currency: "EUR"
    })

    {:ok, view, _html} = live(conn, ~p"/finance/vendors?vendors-chart=vendors&vendors-currency=USD")

    refute has_element?(view, "#finance-vendors-currency-switcher")
    assert has_element?(view, "#finance-vendors-widget-spend [data-part='value']", "EUR 150.00")
    assert has_element?(view, "#finance-vendors-widget-top-vendor", "Grafana Labs")

    render_click(view, "select_chart", %{"widget" => "categories"})

    assert_patched(view, ~p"/finance/vendors?vendors-chart=categories")
  end

  test "labels smoothed runway without trailing net burn", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-runway@example.com", role: :executive})

    source =
      insert_finance_source!(%{
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    account =
      insert_finance_account!(source, %{
        name: "Operating",
        balance_value: Decimal.new("1000.00"),
        available_balance_value: Decimal.new("900.00")
      })

    insert_finance_transaction!(account, %{
      external_id: "txn-customer-payment",
      direction: "credit",
      kind: "invoice_payment",
      amount_value: Decimal.new("100.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    {:ok, view, _html} = live(conn, ~p"/finance")

    assert has_element?(view, "#finance-widget-monthly-burn [data-part='value']", "EUR 0.00")
    assert has_element?(view, "#finance-widget-runway [data-part='value']", "No trailing net burn")
  end

  test "selecting a different overview widget swaps the chart", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-widget@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/finance")

    render_click(view, "select_overview_widget", %{"widget" => "available_cash"})

    assert_patched(view, ~p"/finance?overview-widget=available_cash")
    assert has_element?(view, "#finance-balance-chart")
    refute has_element?(view, "#finance-runway-chart")

    render_click(view, "select_overview_widget", %{"widget" => "income"})

    assert_patched(view, ~p"/finance?overview-widget=income")
    assert has_element?(view, "#finance-cash-flow-chart")
  end

  test "selecting a runway period patches the URL", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-period@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/finance")

    render_hook(view, "runway_period_changed", %{
      "preset" => "last-30-days",
      "value" => %{"start" => "2026-04-27", "end" => "2026-05-27"}
    })

    assert_patched(view, ~p"/finance?runway-date-range=last-30-days")
  end

  test "filters transactions by provider and direction", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "finance-filters@example.com", role: :executive})

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

    qonto_account = insert_finance_account!(qonto_source, %{name: "Operating"})
    mercury_account = insert_finance_account!(mercury_source, %{name: "Reserve"})

    debit =
      insert_finance_transaction!(qonto_account, %{
        external_id: "txn-debit",
        direction: "debit",
        counterparty_name: "Payroll Provider",
        amount_value: Decimal.new("2500.00"),
        booked_at: ~U[2026-05-20 09:00:00Z],
        settled_at: ~U[2026-05-20 09:00:00Z],
        provider_updated_at: ~U[2026-05-20 09:00:00Z]
      })

    _credit =
      insert_finance_transaction!(mercury_account, %{
        external_id: "txn-credit",
        direction: "credit",
        counterparty_name: "Mercury",
        amount_value: Decimal.new("45.00"),
        booked_at: ~U[2026-05-18 09:00:00Z],
        settled_at: ~U[2026-05-18 09:00:00Z],
        provider_updated_at: ~U[2026-05-18 09:00:00Z]
      })

    filter_params = %{
      "filter_provider_op" => "==",
      "filter_provider_val" => "qonto",
      "filter_direction_op" => "==",
      "filter_direction_val" => "debit"
    }

    {:ok, view, _html} = live(conn, ~p"/finance?#{filter_params}")

    assert has_element?(view, ~s(#finance-transactions-table tr[id="#{debit.id}"]))
    assert has_element?(view, "#provider")
    assert has_element?(view, "#direction")
    refute has_element?(view, "#finance-transactions-table", "Mercury")
  end

  test "redirects employees away from the finance page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "employee-finance@example.com", role: :employee})

    assert {:error, {:redirect, %{to: "/sales"}}} = live(conn, ~p"/finance")
  end

  defp insert_document!(attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    {foreign_keys, cast_attrs} =
      Map.split(Map.merge(defaults, attrs), [:account_id, :document_type_id, :correspondent_id, :uploaded_by_id])

    %Document{}
    |> Document.changeset(cast_attrs)
    |> Ecto.Changeset.change(foreign_keys)
    |> Atlas.Repo.insert!()
  end
end
