defmodule AtlasWeb.FinanceLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.FinanceLive.Charts
  import AtlasWeb.FinanceLive.Filters
  import AtlasWeb.FinanceLive.Formatters
  import AtlasWeb.FinanceLive.QueryParams
  import AtlasWeb.Widget
  import Noora.Filter

  alias Atlas.Finance
  alias Atlas.Finance.Transaction
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter
  alias Phoenix.LiveView.JS

  @transactions_date_range_prefix "transactions"
  @overview_widgets ~w(runway available_cash monthly_burn income)
  @default_overview_widget "runway"

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Finance"))
     |> assign(:available_filters, [])}
  end

  def handle_params(params, uri, socket) do
    overview = Finance.overview()
    sources = Finance.list_sources()
    all_accounts = Finance.list_accounts()
    categories = Finance.list_categories()
    option_transactions = Finance.list_transactions(limit: 500)
    available_filters = define_filters(sources, all_accounts, categories, option_transactions)
    params = normalize_finance_params(params)
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    search = params["search"] || ""
    transactions_page = Query.parse_page(params[transactions_page_param()])

    %{preset: transactions_date_range_preset, period: transactions_date_range_period} =
      transactions_date_picker_params(params)

    %{preset: runway_preset, period: runway_period} = runway_date_picker_params(params)
    runway_history_days = history_days_for_period(runway_period)

    window = Finance.runway_window(history_days: runway_history_days)
    cash = Finance.cash_analytics(window)
    burn = Finance.burn_rate_analytics(window)
    runway = Finance.runway_analytics(window)
    cash_flow = Finance.cash_flow_analytics(window)

    selected_widget = normalize_overview_widget(params["overview-widget"])

    parsed_uri = URI.parse(uri)

    accounts = filter_accounts(all_accounts, active_filters)
    invoices = Finance.list_invoices(limit: 25)

    {transactions, transactions_meta} =
      Finance.list_transactions_page(
        transaction_filters(search, active_filters, transactions_date_range_period, transactions_page)
      )

    balance_scale = humanize_scale(cash.values)
    burn_scale = humanize_scale(burn.values)
    cash_flow_scale = humanize_scale(cash_flow.income ++ cash_flow.expense)

    {:noreply,
     socket
     |> assign(:uri, parsed_uri)
     |> assign(:overview, overview)
     |> assign(:sources, sources)
     |> assign(:categories, categories)
     |> assign(:available_filters, available_filters)
     |> assign(:accounts, accounts)
     |> assign(:invoices, invoices)
     |> assign(:transactions, transactions)
     |> assign(:transactions_meta, transactions_meta)
     |> assign(:active_filters, active_filters)
     |> assign(:search_form, to_form(%{"query" => search}, as: :search))
     |> assign(:transactions_date_range_preset, transactions_date_range_preset)
     |> assign(:transactions_date_range_period, transactions_date_range_period)
     |> assign(:runway_date_range_preset, runway_preset)
     |> assign(:runway_date_range_period, runway_period)
     |> assign(:selected_overview_widget, selected_widget)
     |> assign(:runway_trend, runway.trend)
     |> assign(:available_cash_trend, cash.trend)
     |> assign(:monthly_burn_trend, burn.trend)
     |> assign(:overview_chart_dates, chart_dates(window.dates))
     |> assign(:balance_chart_data, scaled_chart_series(cash.dates, cash.values, balance_scale))
     |> assign(:balance_chart_format, currency_format(balance_scale, cash.currency))
     |> assign(:burn_chart_data, scaled_chart_series(burn.dates, burn.values, burn_scale))
     |> assign(:burn_chart_format, currency_format(burn_scale, burn.currency))
     |> assign(:runway_chart_data, chart_series(runway.dates, runway.values))
     |> assign(:cash_flow_dates, chart_dates(cash_flow.dates))
     |> assign(:income_chart_data, scaled_chart_series(cash_flow.dates, cash_flow.income, cash_flow_scale))
     |> assign(:expense_chart_data, scaled_chart_series(cash_flow.dates, cash_flow.expense, cash_flow_scale))
     |> assign(:cash_flow_chart_format, currency_format(cash_flow_scale, cash_flow.currency))
     |> assign(:income_value, cash_flow.income_value)
     |> assign(:expense_value, cash_flow.expense_value)
     |> assign(:income_trend, cash_flow.income_trend)}
  end

  defp normalize_overview_widget(value) when value in @overview_widgets, do: value
  defp normalize_overview_widget(_value), do: @default_overview_widget

  def render(assigns) do
    ~H"""
    <div id="finance">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Finance")}</h1>
          <p data-part="description">
            {gettext(
              "Normalized treasury data from Qonto and Mercury, with runway and cash movement surfaced in one place."
            )}
          </p>
          <div data-part="summary">
            <span id="finance-source-count" data-part="summary-item">
              {gettext("%{count} sources", count: @overview.source_count)}
            </span>
            <span id="finance-account-count" data-part="summary-item">
              {gettext("%{count} accounts", count: @overview.account_count)}
            </span>
            <span id="finance-transactions-count" data-part="summary-item">
              {gettext("%{count} tx / 30d", count: @overview.transaction_count_30d)}
            </span>
            <span id="finance-last-synced" data-part="summary-item">
              {last_synced_label(@overview.last_synced_at)}
            </span>
          </div>
        </div>
      </div>

      <.card title={gettext("Cash overview")} icon="building" data-part="overview-card">
        <:actions>
          <div data-part="overview-actions">
            <.date_picker
              id="finance-runway-date-range-picker"
              label={gettext("Date range")}
              name="runway-date-range"
              presets={runway_date_range_presets()}
              selected_preset={@runway_date_range_preset}
              period={@runway_date_range_period}
              on_period_change="runway_period_changed"
              max={Date.utc_today()}
            >
              <:actions>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  phx-click={
                    JS.dispatch("phx:date-picker-cancel",
                      detail: %{id: "finance-runway-date-range-picker"}
                    )
                  }
                />
                <.button
                  label={gettext("Apply")}
                  phx-click={
                    JS.dispatch("phx:date-picker-apply",
                      detail: %{id: "finance-runway-date-range-picker"}
                    )
                  }
                />
              </:actions>
            </.date_picker>
          </div>
        </:actions>
        <.card_section data-part="overview-section">
          <div data-part="widgets">
            <.widget
              id="finance-widget-runway"
              title={gettext("Runway")}
              value={runway_label(@overview.runway_months, gettext("No trailing net burn"))}
              tooltip_description={
                gettext(
                  "Estimated months of runway calculated from synced bank cash divided by smoothed monthly net burn. This is a backward-looking cash movement metric."
                )
              }
              legend_color="primary"
              trend_value={@runway_trend}
              trend_label={runway_trend_label(@overview.runway_uplift_months)}
              trend_type={:regular}
              empty={@overview.account_count == 0}
              empty_label={gettext("Not enough data")}
              phx_click="select_overview_widget"
              phx_value_widget="runway"
              selected={@selected_overview_widget == "runway"}
            />
            <.widget
              id="finance-widget-available-cash"
              title={gettext("Available cash")}
              value={compact_amount(@overview.available_cash_value, @overview.currency)}
              tooltip_description={
                gettext(
                  "Sum of the latest available balances reported by every synced finance account. When a provider does not report an available balance, Atlas falls back to the account balance."
                )
              }
              legend_color="tertiary"
              trend_value={@available_cash_trend}
              trend_label={gettext("since last month")}
              trend_type={:regular}
              empty={@overview.account_count == 0}
              empty_label={gettext("No synced accounts")}
              phx_click="select_overview_widget"
              phx_value_widget="available_cash"
              selected={@selected_overview_widget == "available_cash"}
            />
            <.widget
              id="finance-widget-monthly-burn"
              title={gettext("Monthly burn")}
              value={compact_amount(@overview.monthly_burn_value, @overview.currency)}
              tooltip_description={
                gettext(
                  "Average monthly net cash burn estimated from trailing runway-relevant credits and debits over the selected runway window. One-off transfers excluded from runway are not included."
                )
              }
              legend_color={
                if(zero_decimal?(@overview.monthly_burn_value), do: "neutral", else: "secondary")
              }
              trend_value={@monthly_burn_trend}
              trend_label={gettext("since last month")}
              trend_type={:inverse}
              phx_click="select_overview_widget"
              phx_value_widget="monthly_burn"
              selected={@selected_overview_widget == "monthly_burn"}
            />
            <.widget
              id="finance-widget-income"
              title={gettext("Income this month")}
              value={compact_amount(@income_value, @overview.currency)}
              tooltip_description={
                gettext(
                  "Sum of credits booked in the current calendar month, FX-converted to the report currency. The chart breaks down income alongside expenses per calendar month."
                )
              }
              legend_color="success"
              trend_value={@income_trend}
              trend_label={income_trend_label(@expense_value, @overview.currency)}
              trend_type={:regular}
              empty={is_nil(@income_value) or zero_decimal?(@income_value)}
              empty_label={gettext("No income yet")}
              phx_click="select_overview_widget"
              phx_value_widget="income"
              selected={@selected_overview_widget == "income"}
            />
          </div>
        </.card_section>
        <.card_section data-part="overview-chart-section">
          <div :if={@overview_chart_dates == []} data-part="chart-empty">
            {gettext("Not enough history yet to chart this metric.")}
          </div>
          <div
            :if={@overview_chart_dates != [] and @selected_overview_widget == "runway"}
            data-part="chart"
            id="finance-runway-chart-wrapper"
          >
            <.chart
              id="finance-runway-chart"
              type="line"
              extra_options={chart_options(@overview_chart_dates, "{value} months")}
              series={[
                %{
                  color: "var:noora-chart-primary",
                  data: @runway_chart_data,
                  name: gettext("Runway"),
                  type: "line",
                  smooth: 0.2,
                  symbol: "none",
                  connectNulls: true
                }
              ]}
              y_axis_min={0}
            />
          </div>
          <div
            :if={@overview_chart_dates != [] and @selected_overview_widget == "available_cash"}
            data-part="chart"
            id="finance-balance-chart-wrapper"
          >
            <.chart
              id="finance-balance-chart"
              type="line"
              extra_options={chart_options(@overview_chart_dates, @balance_chart_format)}
              series={[
                %{
                  color: "var:noora-chart-tertiary",
                  data: @balance_chart_data,
                  name: gettext("Total available cash"),
                  type: "line",
                  smooth: 0.1,
                  symbol: "none",
                  areaStyle: %{opacity: 0.18}
                }
              ]}
              y_axis_min={0}
            />
          </div>
          <div
            :if={@overview_chart_dates != [] and @selected_overview_widget == "monthly_burn"}
            data-part="chart"
            id="finance-burn-chart-wrapper"
          >
            <.chart
              id="finance-burn-chart"
              type="line"
              extra_options={chart_options(@overview_chart_dates, @burn_chart_format)}
              series={[
                %{
                  color: "var:noora-chart-secondary",
                  data: @burn_chart_data,
                  name: gettext("Smoothed monthly burn"),
                  type: "line",
                  smooth: 0.4,
                  symbol: "none",
                  areaStyle: %{opacity: 0.12}
                }
              ]}
              y_axis_min={0}
            />
          </div>
          <div
            :if={@cash_flow_dates != [] and @selected_overview_widget == "income"}
            data-part="chart"
            id="finance-cash-flow-chart-wrapper"
          >
            <.chart
              id="finance-cash-flow-chart"
              type="bar"
              extra_options={
                chart_options(@cash_flow_dates, @cash_flow_chart_format, boundary_gap: true)
              }
              series={[
                %{
                  color: "var:noora-chart-tertiary",
                  data: @income_chart_data,
                  name: gettext("Income"),
                  type: "bar",
                  barWidth: 8,
                  barRadius: 2
                },
                %{
                  color: "var:noora-chart-destructive",
                  data: @expense_chart_data,
                  name: gettext("Expenses"),
                  type: "bar",
                  barWidth: 8,
                  barRadius: 2
                }
              ]}
              y_axis_min={0}
            />
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Renewal scenario")} icon="chart_donut_4" data-part="projections-card">
        <.card_section data-part="projections-section">
          <div data-part="widgets">
            <.widget
              id="finance-widget-projected-arr"
              title={gettext("Renewal ARR")}
              value={compact_amount(@overview.projected_arr_value, @overview.currency)}
              description={renewal_base_caption(@overview.projected_customer_count)}
              tooltip_description={
                gettext(
                  "Annual revenue expected if every customer in the renewal base renews on the same commercial terms."
                )
              }
              legend_color="success"
              empty={@overview.projected_customer_count == 0}
              empty_label={gettext("No renewal base")}
            />
            <.widget
              id="finance-widget-committed-pipeline"
              title={gettext("Committed pipeline")}
              value={compact_amount(@overview.committed_pipeline_value, @overview.currency)}
              description={committed_pipeline_caption(@overview.next_committed_renewal)}
              tooltip_description={
                gettext(
                  "Sum of contracted-but-not-yet-collected renewals due before end of year, converted to the report currency. Excludes paused customers."
                )
              }
              legend_color="primary"
              empty={@overview.committed_pipeline_count == 0}
              empty_label={gettext("No renewals before EOY")}
            />
            <.widget
              id="finance-widget-projected-net-burn"
              title={gettext("Adjusted burn")}
              value={compact_amount(@overview.projected_net_burn_value, @overview.currency)}
              description={
                adjusted_burn_caption(
                  @overview.projected_monthly_expenses_value,
                  @overview.currency
                )
              }
              tooltip_description={
                gettext(
                  "Trailing monthly gross expenses minus the monthly equivalent of expected renewal revenue. Atlas floors this at zero when renewals cover expenses."
                )
              }
              legend_color={
                if(zero_decimal?(@overview.projected_net_burn_value), do: "success", else: "warning")
              }
            />
            <.widget
              id="finance-widget-projected-runway"
              title={gettext("Plan-adjusted runway")}
              value={
                runway_label(@overview.plan_adjusted_runway_months, gettext("No adjusted net burn"))
              }
              description={cash_plus_committed_caption(@overview.cash_plus_committed_runway_months)}
              tooltip_description={
                gettext(
                  "Estimated runway using trailing monthly expenses adjusted by the monthly renewal revenue currently modeled in Atlas. The sublabel adds the committed EOY pipeline as a one-off cash inflow."
                )
              }
              legend_color="attention"
              empty={@overview.account_count == 0}
              empty_label={gettext("Not enough data")}
            />
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Accounts")} icon="users" data-part="accounts-card">
        <.card_section data-part="accounts-table-section">
          <.table id="finance-accounts-table" rows={@accounts}>
            <:col :let={account} label={gettext("Account")}>
              <.text_and_description_cell
                label={account.name}
                description={account_description(account)}
              />
            </:col>
            <:col :let={account} label={gettext("Type")}>
              <.text_cell label={account_type_label(account)} />
            </:col>
            <:col :let={account} label={gettext("Available")}>
              <.text_cell label={
                format_amount(
                  account.available_balance_value || account.balance_value,
                  account.available_balance_currency || account.balance_currency
                )
              } />
            </:col>
            <:col :let={account} label={gettext("Balance")}>
              <.text_cell label={format_amount(account.balance_value, account.balance_currency)} />
            </:col>
            <:col :let={account} label={gettext("Status")}>
              <.badge_cell
                label={status_label(account.status)}
                color={status_color(account.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={account} label={gettext("Updated")}>
              <.text_cell label={format_datetime(account.refreshed_at)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="building"
                title={gettext("No synced accounts")}
                subtitle={
                  gettext("Run a finance sync and the connected bank accounts will appear here.")
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Vendor invoices")} icon="file" data-part="invoices-card">
        <:actions>
          <.link navigate={~p"/finance/vendors"}>
            <.button
              id="finance-vendors-button"
              label={gettext("Open vendor costs")}
              variant="secondary"
              size="small"
            />
          </.link>
        </:actions>
        <.card_section data-part="invoices-table-section">
          <.table id="finance-invoices-table" rows={@invoices}>
            <:col :let={invoice} label={gettext("Date")}>
              <.text_cell label={
                format_date(
                  invoice.invoice_date || (invoice.document && invoice.document.document_date)
                )
              } />
            </:col>
            <:col :let={invoice} label={gettext("Vendor")}>
              <.text_and_description_cell
                label={invoice.vendor_name}
                description={invoice_line_items_label(invoice)}
              />
            </:col>
            <:col :let={invoice} label={gettext("Number")}>
              <.text_cell label={invoice.invoice_number || "-"} />
            </:col>
            <:col :let={invoice} label={gettext("Amount")}>
              <.text_cell label={
                format_amount(invoice.total_amount_value, invoice.total_amount_currency)
              } />
            </:col>
            <:col :let={invoice} label={gettext("Status")}>
              <.badge_cell
                label={status_label(invoice.status)}
                color={status_color(invoice.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={invoice} label={gettext("Source")}>
              <.text_cell label={invoice.metadata["document_source"] || "-"} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="file"
                title={gettext("No extracted invoices")}
                subtitle={
                  gettext("Forward invoices or run the Qonto backfill to populate cost breakdowns.")
                }
              />
            </:empty_state>
          </.table>
          <div data-part="table-footer">
            <.link id="finance-vendors-link" navigate={~p"/finance/vendors"}>
              {gettext("View vendor cost analytics")}
            </.link>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Transactions")} icon="history" data-part="transactions-card">
        <:actions>
          <div data-part="transactions-actions">
            <.link patch={~p"/finance"}>
              <.button
                id="finance-reset-filters-button"
                label={gettext("Reset filters")}
                variant="secondary"
                size="small"
              />
            </.link>
          </div>
        </:actions>
        <.card_section data-part="transactions-table-section">
          <div data-part="filters">
            <.filter_dropdown
              id="finance-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <.date_picker
              id="finance-transactions-date-range-picker"
              label={gettext("Date range")}
              name="transactions-date-range"
              presets={transactions_date_range_presets()}
              selected_preset={@transactions_date_range_preset}
              period={@transactions_date_range_period}
              on_period_change="transactions_period_changed"
              max={Date.utc_today()}
            >
              <:actions>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  phx-click={
                    JS.dispatch("phx:date-picker-cancel",
                      detail: %{id: "finance-transactions-date-range-picker"}
                    )
                  }
                />
                <.button
                  label={gettext("Apply")}
                  phx-click={
                    JS.dispatch("phx:date-picker-apply",
                      detail: %{id: "finance-transactions-date-range-picker"}
                    )
                  }
                />
              </:actions>
            </.date_picker>

            <div data-part="search">
              <.form
                id="finance-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="finance-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={
                    gettext("Search counterparty, description, reference, account, or source")
                  }
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <div data-part="transactions-table">
            <.table id="finance-transactions-table" rows={@transactions}>
              <:col :let={transaction} label={gettext("Date")}>
                <.text_cell label={format_datetime(Transaction.occurred_at(transaction))} />
              </:col>
              <:col :let={transaction} label={gettext("Counterparty")}>
                <.text_and_description_cell
                  label={counterparty_label(transaction)}
                  description={transaction_description(transaction)}
                />
              </:col>
              <:col :let={transaction} label={gettext("Account")}>
                <.text_and_description_cell
                  label={transaction.account.name}
                  description={account_description(transaction.account)}
                />
              </:col>
              <:col :let={transaction} label={gettext("Direction")}>
                <.badge_cell
                  label={humanize_value(transaction.direction)}
                  color={direction_color(transaction.direction)}
                  style="light-fill"
                />
              </:col>
              <:col :let={transaction} label={gettext("Category")}>
                <.text_cell label={category_label(transaction)} />
              </:col>
              <:col :let={transaction} label={gettext("Amount")}>
                <.text_and_description_cell
                  label={
                    signed_amount_label(
                      transaction.amount_value,
                      transaction.amount_currency,
                      transaction.direction
                    )
                  }
                  description={transaction_amount_description(transaction)}
                />
              </:col>
              <:col :let={transaction} label={gettext("Status")}>
                <.badge_cell
                  label={status_label(transaction.status)}
                  color={status_color(transaction.status)}
                  style="light-fill"
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="history"
                  title={gettext("No matching transactions")}
                  subtitle={
                    gettext("Change the filters or run a sync to populate transaction history.")
                  }
                />
              </:empty_state>
            </.table>
            <div data-part="table-footer">
              <span id="finance-transactions-result-count" data-part="count">
                {ngettext(
                  "%{count} transaction",
                  "%{count} transactions",
                  @transactions_meta.total_count,
                  count: @transactions_meta.total_count
                )}
              </span>
              <.pagination_group
                :if={@transactions_meta.total_pages > 1}
                id="finance-transactions-pagination"
                current_page={@transactions_meta.current_page}
                number_of_pages={@transactions_meta.total_pages}
                page_patch={
                  fn page -> "?#{Query.put(@uri.query, transactions_page_param(), page)}" end
                }
              />
            </div>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> put_search_param(query)
      |> reset_transactions_page()

    {:noreply, push_patch(socket, to: ~p"/finance?#{query_params}", replace: true)}
  end

  def handle_event("select_overview_widget", %{"widget" => widget}, socket) do
    base = current_query_params(socket)

    query_params =
      cond do
        widget not in @overview_widgets -> base
        widget == @default_overview_widget -> Map.delete(base, "overview-widget")
        true -> Map.put(base, "overview-widget", widget)
      end

    {:noreply, push_patch(socket, to: ~p"/finance?#{query_params}", replace: true)}
  end

  def handle_event(
        "runway_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    base = current_query_params(socket)

    query_params =
      if preset == "custom" do
        base
        |> Map.put("runway-date-range", "custom")
        |> Map.put("runway-start-date", start_date)
        |> Map.put("runway-end-date", end_date)
      else
        base
        |> Map.put("runway-date-range", preset)
        |> Map.drop(["runway-start-date", "runway-end-date"])
      end

    {:noreply, push_patch(socket, to: ~p"/finance?#{query_params}")}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket, current_query_params(socket))
      |> reset_transactions_page()

    {:noreply,
     socket
     |> push_patch(to: ~p"/finance?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket, current_query_params(socket))
      |> reset_transactions_page()

    {:noreply,
     socket
     |> push_patch(to: ~p"/finance?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "transactions_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    base = current_query_params(socket)

    query_params =
      if preset == "custom" do
        base
        |> Map.put("#{@transactions_date_range_prefix}-date-range", "custom")
        |> Map.put("#{@transactions_date_range_prefix}-start-date", start_date)
        |> Map.put("#{@transactions_date_range_prefix}-end-date", end_date)
      else
        base
        |> Map.put("#{@transactions_date_range_prefix}-date-range", preset)
        |> Map.drop([
          "#{@transactions_date_range_prefix}-start-date",
          "#{@transactions_date_range_prefix}-end-date"
        ])
      end
      |> reset_transactions_page()

    {:noreply, push_patch(socket, to: ~p"/finance?#{query_params}")}
  end

  defp put_search_param(params, query) do
    case String.trim(to_string(query)) do
      "" -> Map.delete(params, "search")
      trimmed -> Map.put(params, "search", trimmed)
    end
  end

  defp reset_transactions_page(params) when is_map(params), do: Map.delete(params, transactions_page_param())
  defp reset_transactions_page(params) when is_binary(params), do: Query.drop(params, transactions_page_param())
end
