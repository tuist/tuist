defmodule AtlasWeb.FinanceVendorLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.FinanceLive.Charts
  import AtlasWeb.FinanceLive.Formatters
  import AtlasWeb.Widget
  import Noora.Filter

  alias Atlas.Finance
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter
  alias Noora.Filter.Filter, as: FilterDefinition
  alias Phoenix.LiveView.JS

  @date_range_prefix "vendors"
  @stale_currency_param "vendors-currency"
  @expenses_after_param "vendors-expenses-after"
  @expenses_before_param "vendors-expenses-before"
  @expenses_page_param "vendors-expenses-page"
  @expenses_search_param "vendors-expenses-search"
  @default_date_range_preset "last-12-months"
  @chart_widgets ~w(spend vendors categories)
  @default_chart_widget "spend"
  @expenses_page_size 10
  @vendor_chart_limit 12

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Vendor costs"))}
  end

  def handle_params(params, uri, socket) do
    %{preset: date_range_preset, period: date_range_period} = date_picker_params(params)

    analytics =
      date_range_period
      |> analytics_filters()
      |> Finance.vendor_cost_analytics()

    selected_chart = normalize_chart_widget(params["vendors-chart"])
    spend_scale = humanize_scale(monthly_values(analytics))
    vendor_chart_vendors = chart_vendor_summaries(analytics.vendors)
    vendor_chart_overflow = vendor_chart_overflow_summary(analytics.vendors)
    vendor_scale = humanize_scale(Enum.map(vendor_chart_vendors, & &1.total_amount_value))
    category_scale = humanize_scale(Enum.map(analytics.categories, & &1.amount_value))
    available_filters = expense_filter_definitions(analytics.expenses)
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    expenses_search = Query.present_string(params[@expenses_search_param]) || ""
    filtered_expenses = filter_expenses(analytics.expenses, expenses_search, active_filters)
    {expenses, expenses_meta} = paginate_expenses(filtered_expenses, expense_page(params))

    {:noreply,
     socket
     |> assign(:uri, sanitized_uri(uri))
     |> assign(:analytics, analytics)
     |> assign(:date_range_preset, date_range_preset)
     |> assign(:date_range_period, date_range_period)
     |> assign(:selected_chart, selected_chart)
     |> assign(:spend_chart_dates, monthly_series_dates(analytics.monthly_spend, date_range_period))
     |> assign(:spend_chart_data, scaled_monthly_series(analytics.monthly_spend, date_range_period, spend_scale))
     |> assign(:spend_chart_format, currency_format(spend_scale, analytics.currency))
     |> assign(:vendor_chart_labels, Enum.map(vendor_chart_vendors, & &1.vendor_name))
     |> assign(:vendor_chart_data, scaled_vendor_spend(vendor_chart_vendors, vendor_scale))
     |> assign(:vendor_chart_format, currency_format(vendor_scale, analytics.currency))
     |> assign(:vendor_chart_overflow_label, vendor_chart_overflow_label(vendor_chart_overflow))
     |> assign(:category_chart_labels, Enum.map(analytics.categories, & &1.category_name))
     |> assign(:category_chart_data, scaled_category_spend(analytics.categories, category_scale))
     |> assign(:category_chart_format, currency_format(category_scale, analytics.currency))
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:expenses_search, expenses_search)
     |> assign(:expenses_search_form, to_form(%{"query" => expenses_search}, as: :expenses_search))
     |> assign(:expenses, expenses)
     |> assign(:expenses_meta, expenses_meta)
     |> assign(:expenses_page_param, @expenses_page_param)}
  end

  def render(assigns) do
    ~H"""
    <div id="finance-vendors">
      <div data-part="header">
        <div data-part="text">
          <div data-part="breadcrumbs">
            <.link navigate={~p"/finance"}>{gettext("Finance")}</.link>
            <span>{gettext("Vendor costs")}</span>
          </div>
          <h1 data-part="title">{gettext("Vendor costs")}</h1>
          <p data-part="description">
            {gettext(
              "Invoice-level spend, cost categories, and vendor concentration for understanding the operating cost structure behind bank transactions."
            )}
          </p>
          <div data-part="summary">
            <span id="finance-vendors-invoice-count" data-part="summary-item">
              {ngettext(
                "%{count} invoice",
                "%{count} invoices",
                @analytics.invoice_count,
                count: @analytics.invoice_count
              )}
            </span>
            <span id="finance-vendors-vendor-count" data-part="summary-item">
              {ngettext(
                "%{count} vendor",
                "%{count} vendors",
                @analytics.vendor_count,
                count: @analytics.vendor_count
              )}
            </span>
          </div>
        </div>
      </div>

      <.card title={gettext("Cost overview")} icon="chart_donut_4" data-part="overview-card">
        <:actions>
          <div data-part="overview-actions">
            <.date_picker
              id="finance-vendors-date-range-picker"
              label={gettext("Date range")}
              name="vendors-date-range"
              presets={date_range_presets()}
              selected_preset={@date_range_preset}
              period={@date_range_period}
              on_period_change="vendors_period_changed"
              max={Date.utc_today()}
            >
              <:actions>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  phx-click={
                    JS.dispatch("phx:date-picker-cancel",
                      detail: %{id: "finance-vendors-date-range-picker"}
                    )
                  }
                />
                <.button
                  label={gettext("Apply")}
                  phx-click={
                    JS.dispatch("phx:date-picker-apply",
                      detail: %{id: "finance-vendors-date-range-picker"}
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
              id="finance-vendors-widget-spend"
              title={gettext("Invoice spend")}
              value={compact_amount(@analytics.total_spend_value, @analytics.currency)}
              description={gettext("Total extracted invoice spend")}
              legend_color="destructive"
              empty={@analytics.invoice_count == 0}
              empty_label={gettext("No extracted spend")}
              phx_click="select_chart"
              phx_value_widget="spend"
              selected={@selected_chart == "spend"}
            />
            <.widget
              id="finance-vendors-widget-top-vendor"
              title={gettext("Vendor concentration")}
              value={top_vendor_value(@analytics.top_vendor, @analytics.currency)}
              description={
                top_vendor_caption(
                  @analytics.top_vendor,
                  @analytics.total_spend_value,
                  @analytics.concentration_percent
                )
              }
              legend_color="primary"
              empty={is_nil(@analytics.top_vendor)}
              empty_label={gettext("No vendors yet")}
              phx_click="select_chart"
              phx_value_widget="vendors"
              selected={@selected_chart == "vendors"}
            />
            <.widget
              id="finance-vendors-widget-categories"
              title={gettext("Cost structure")}
              value={top_category_value(@analytics.categories)}
              description={top_category_caption(@analytics.categories, @analytics.currency)}
              legend_color="secondary"
              empty={@analytics.categories == []}
              empty_label={gettext("No categorized spend")}
              phx_click="select_chart"
              phx_value_widget="categories"
              selected={@selected_chart == "categories"}
            />
          </div>
        </.card_section>
      </.card>

      <.card title={chart_title(@selected_chart)} icon="chart_arcs" data-part="spend-card">
        <.card_section data-part="overview-chart-section">
          <div
            :if={
              chart_empty?(
                @selected_chart,
                @spend_chart_dates,
                @vendor_chart_labels,
                @category_chart_labels
              )
            }
            data-part="chart-empty"
          >
            {chart_empty_label(@selected_chart)}
          </div>
          <div
            :if={@selected_chart == "spend" and @spend_chart_dates != []}
            data-part="chart"
            id="finance-vendors-spend-chart-wrapper"
          >
            <.chart
              id="finance-vendors-spend-chart"
              type="line"
              extra_options={
                chart_options(@spend_chart_dates, @spend_chart_format, x_axis_label_count: 5)
              }
              series={[
                %{
                  color: "var:noora-chart-destructive",
                  data: @spend_chart_data,
                  name: gettext("Invoice spend"),
                  type: "line",
                  smooth: 0.2,
                  symbol: "none",
                  areaStyle: %{opacity: 0.12}
                }
              ]}
              y_axis_min={0}
            />
          </div>
          <div
            :if={@selected_chart == "vendors" and @vendor_chart_labels != []}
            data-part="chart"
            id="finance-vendors-vendor-chart-wrapper"
          >
            <.chart
              id="finance-vendors-vendor-chart"
              type="bar"
              extra_options={ranked_bar_chart_options(@vendor_chart_labels, @vendor_chart_format)}
              series={[
                %{
                  color: "var:noora-chart-secondary",
                  data: @vendor_chart_data,
                  name: gettext("Vendor spend"),
                  type: "bar",
                  barWidth: 12,
                  barRadius: 2
                }
              ]}
              y_axis_min={0}
            />
          </div>
          <p
            :if={@selected_chart == "vendors" and @vendor_chart_overflow_label}
            id="finance-vendors-vendor-chart-note"
            data-part="chart-note"
          >
            {@vendor_chart_overflow_label}
          </p>
          <div
            :if={@selected_chart == "categories" and @category_chart_labels != []}
            data-part="chart"
            id="finance-vendors-category-chart-wrapper"
          >
            <.chart
              id="finance-vendors-category-chart"
              type="bar"
              extra_options={ranked_bar_chart_options(@category_chart_labels, @category_chart_format)}
              series={[
                %{
                  color: "var:noora-chart-secondary",
                  data: @category_chart_data,
                  name: gettext("Category spend"),
                  type: "bar",
                  barWidth: 10,
                  barRadius: 2
                }
              ]}
              y_axis_min={0}
            />
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Expenses")} icon="file_text" data-part="expenses-card">
        <.card_section data-part="expenses-section">
          <div data-part="filters">
            <.filter_dropdown
              id="finance-vendors-expenses-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
            <div data-part="search">
              <.form
                id="finance-vendors-expenses-search-form"
                for={@expenses_search_form}
                phx-change="search_expenses"
                phx-submit="search_expenses"
              >
                <.text_input
                  id="finance-vendors-expenses-search"
                  field={@expenses_search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search vendor, invoice, transaction, category, or line item")}
                />
              </.form>
            </div>
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div id="finance-vendors-expenses-list" data-part="expenses-list">
            <div
              :if={@expenses_meta.total_count == 0}
              id="finance-vendors-expenses-empty"
              data-part="expenses-empty"
            >
              <div data-part="expenses-empty-icon" aria-hidden="true">
                <.icon name="file_text" />
              </div>
              <div data-part="expenses-empty-content">
                <span data-part="expenses-empty-title">
                  {expenses_empty_title(@analytics.expenses, @expenses_search, @active_filters)}
                </span>
                <span data-part="expenses-empty-subtitle">
                  {expenses_empty_subtitle(@analytics.expenses, @expenses_search, @active_filters)}
                </span>
              </div>
            </div>
            <article
              :for={expense <- @expenses}
              id={"finance-vendors-expense-#{expense.id}"}
              data-part="expense"
            >
              <div
                id={"finance-vendors-expense-collapsible-#{expense.id}"}
                data-part="collapsible"
                phx-hook="NooraCollapsible"
                data-open="false"
              >
                <div data-part="root">
                  <div data-part="trigger">
                    <div data-part="expense-header">
                      <div data-part="expense-vendor">
                        <span data-part="expense-kicker">{gettext("Vendor")}</span>
                        <.link
                          :if={expense.document_id}
                          navigate={~p"/documents/#{expense.document_id}"}
                          data-part="vendor-link"
                        >
                          {expense.vendor_name}
                        </.link>
                        <span :if={is_nil(expense.document_id)} data-part="vendor">
                          {expense.vendor_name}
                        </span>
                        <span data-part="number">
                          {expense.invoice_number || gettext("No invoice number")}
                        </span>
                        <span data-part="expense-categories">
                          {expense_categories_label(expense)}
                        </span>
                      </div>
                      <div data-part="expense-transaction">
                        <span data-part="expense-kicker">{gettext("Transaction")}</span>
                        <span
                          :if={expense.finance_transaction_id}
                          data-part="transaction-reference"
                        >
                          {transaction_label(expense)}
                        </span>
                        <span
                          :if={is_nil(expense.finance_transaction_id)}
                          data-part="transaction-empty"
                        >
                          {gettext("Not linked")}
                        </span>
                      </div>
                      <div data-part="expense-meta">
                        <span data-part="date">{format_date(expense.invoice_date)}</span>
                        <span data-part="amount">
                          {format_amount(expense.total_amount_value, expense.total_amount_currency)}
                        </span>
                        <.badge
                          label={status_label(expense.status)}
                          color={status_color(expense.status)}
                          style="light-fill"
                        />
                      </div>
                      <div data-part="expense-toggle">
                        <.neutral_button
                          data-part="closed-collapsible-button"
                          variant="secondary"
                          size="small"
                        >
                          <.chevron_down />
                        </.neutral_button>
                        <.neutral_button
                          data-part="open-collapsible-button"
                          variant="secondary"
                          size="small"
                        >
                          <.chevron_up />
                        </.neutral_button>
                      </div>
                    </div>
                  </div>
                  <div data-part="content">
                    <div data-part="line-items">
                      <div :if={expense.line_items == []} data-part="line-item-empty">
                        {gettext("No extracted line items")}
                      </div>
                      <div
                        :for={line_item <- expense.line_items}
                        id={"finance-vendors-expense-line-#{line_item.id}"}
                        data-part="line-item"
                      >
                        <div data-part="line-item-text">
                          <span data-part="description">{line_item.description}</span>
                          <span data-part="line-item-category">{line_item.category_name}</span>
                        </div>
                        <span data-part="line-item-amount">
                          {format_amount(line_item.amount_value, line_item.amount_currency)}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </article>
          </div>
          <div data-part="expenses-footer">
            <span id="finance-vendors-expenses-result-count" data-part="count">
              {ngettext(
                "%{count} expense",
                "%{count} expenses",
                @expenses_meta.total_count,
                count: @expenses_meta.total_count
              )}
            </span>
            <div
              :if={@expenses_meta.total_pages > 1}
              id="finance-vendors-expenses-pagination"
              data-part="expenses-pagination"
            >
              <.pagination_group
                id="finance-vendors-expenses-pagination-group"
                current_page={@expenses_meta.current_page}
                number_of_pages={@expenses_meta.total_pages}
                page_patch={fn page -> "?#{Query.put(@uri.query, @expenses_page_param, page)}" end}
              />
            </div>
            <span data-part="footer-spacer"></span>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event(
        "vendors_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    base = socket |> current_query_params() |> reset_expense_pagination()

    query_params =
      if preset == "custom" do
        base
        |> Map.put("#{@date_range_prefix}-date-range", "custom")
        |> Map.put("#{@date_range_prefix}-start-date", start_date)
        |> Map.put("#{@date_range_prefix}-end-date", end_date)
      else
        base
        |> Map.put("#{@date_range_prefix}-date-range", preset)
        |> Map.drop(["#{@date_range_prefix}-start-date", "#{@date_range_prefix}-end-date"])
      end

    {:noreply, push_patch(socket, to: ~p"/finance/vendors?#{query_params}")}
  end

  def handle_event("select_chart", %{"widget" => widget}, socket) do
    base = current_query_params(socket)

    query_params =
      cond do
        widget not in @chart_widgets -> base
        widget == @default_chart_widget -> Map.delete(base, "vendors-chart")
        true -> Map.put(base, "vendors-chart", widget)
      end

    {:noreply, push_patch(socket, to: ~p"/finance/vendors?#{query_params}", replace: true)}
  end

  def handle_event("search_expenses", %{"expenses_search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> put_expenses_search_param(query)
      |> reset_expense_pagination()

    {:noreply, push_patch(socket, to: ~p"/finance/vendors?#{query_params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket, current_query_params(socket))
      |> reset_expense_pagination()

    {:noreply,
     socket
     |> push_patch(to: ~p"/finance/vendors?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket, current_query_params(socket))
      |> reset_expense_pagination()

    {:noreply,
     socket
     |> push_patch(to: ~p"/finance/vendors?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp monthly_values(%{monthly_spend: monthly_spend}), do: Enum.map(monthly_spend, & &1.amount_value)

  defp expense_page(params), do: Query.parse_page(params[@expenses_page_param])

  defp paginate_expenses(expenses, page) do
    total_count = length(expenses)
    total_pages = max(ceil_div(total_count, @expenses_page_size), 1)
    current_page = page |> max(1) |> min(total_pages)
    offset = (current_page - 1) * @expenses_page_size

    {Enum.slice(expenses, offset, @expenses_page_size),
     %{
       total_count: total_count,
       total_pages: total_pages,
       current_page: current_page
     }}
  end

  defp ceil_div(0, _denominator), do: 0
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
    |> drop_stale_query_params()
  end

  defp reset_expense_pagination(params) do
    Map.drop(params, [@expenses_page_param, @expenses_after_param, @expenses_before_param])
  end

  defp put_expenses_search_param(params, query) do
    case String.trim(to_string(query)) do
      "" -> Map.delete(params, @expenses_search_param)
      trimmed -> Map.put(params, @expenses_search_param, trimmed)
    end
  end

  defp sanitized_uri(uri) do
    parsed = URI.parse(uri)

    query =
      parsed.query
      |> Kernel.||("")
      |> URI.decode_query()
      |> drop_stale_query_params()
      |> URI.encode_query()

    %{parsed | query: empty_to_nil(query)}
  end

  defp drop_stale_query_params(params) do
    Map.drop(params, [@stale_currency_param, @expenses_after_param, @expenses_before_param])
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp transaction_label(expense) do
    label =
      expense.transaction_counterparty_name ||
        expense.transaction_reference ||
        expense.transaction_external_id ||
        expense.finance_transaction_id ||
        gettext("Linked transaction")

    truncate_transaction_label(label)
  end

  defp truncate_transaction_label(label) when is_binary(label) do
    if String.length(label) > 32 do
      prefix = String.slice(label, 0, 16)

      suffix =
        label
        |> String.reverse()
        |> String.slice(0, 8)
        |> String.reverse()

      "#{prefix}...#{suffix}"
    else
      label
    end
  end

  defp truncate_transaction_label(_label), do: gettext("Linked transaction")

  defp expense_categories_label(%{categories: []}), do: gettext("No categorized lines")
  defp expense_categories_label(%{categories: categories}), do: Enum.join(categories, " · ")

  defp expenses_empty_title([], _search, _filters), do: gettext("No expenses in this period")

  defp expenses_empty_title(_expenses, search, filters) do
    if expenses_filtered?(search, filters) do
      gettext("No matching expenses")
    else
      gettext("No expenses in this period")
    end
  end

  defp expenses_empty_subtitle([], _search, _filters) do
    gettext("Change the period or process invoices to see line-item spend.")
  end

  defp expenses_empty_subtitle(_expenses, search, filters) do
    if expenses_filtered?(search, filters) do
      gettext("Change the filters or search to widen the expense list.")
    else
      gettext("Change the period or process invoices to see line-item spend.")
    end
  end

  defp expenses_filtered?(search, filters), do: Query.present_string(search) != nil or filters != []

  defp expense_filter_definitions(expenses) do
    [
      option_filter("vendor", gettext("Vendor"), expense_options(expenses, & &1.vendor_name), & &1, searchable: true),
      option_filter("category", gettext("Category"), expense_category_options(expenses), & &1, searchable: true),
      option_filter("status", gettext("Status"), expense_options(expenses, & &1.status), &status_label/1)
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, options_or_formatter, opts \\ [])

  defp option_filter(id, display_name, options, formatter, opts) when is_function(formatter, 1) do
    option_filter(id, display_name, options, Map.new(options, &{&1, formatter.(&1)}), opts)
  end

  defp option_filter(id, display_name, options, options_display_names, opts) when is_map(options_display_names) do
    %FilterDefinition{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: options_display_names,
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false)
    }
  end

  defp expense_options(expenses, mapper) do
    expenses
    |> Enum.map(mapper)
    |> Enum.reject(&blank_value?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp expense_category_options(expenses) do
    expenses
    |> Enum.flat_map(& &1.categories)
    |> Enum.reject(&blank_value?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filter_expenses(expenses, search, active_filters) do
    vendor = active_filter_value(active_filters, "vendor")
    category = active_filter_value(active_filters, "category")
    status = active_filter_value(active_filters, "status")
    search = normalize_search(search)

    Enum.filter(expenses, fn expense ->
      matches_value?(expense.vendor_name, vendor) and
        matches_value?(expense.status, status) and
        matches_category?(expense, category) and
        matches_search?(expense, search)
    end)
  end

  defp active_filter_value(filters, filter_id) do
    filters
    |> Enum.find(&(&1.id == filter_id))
    |> case do
      nil -> nil
      %{value: value} -> normalize_filter_value(value)
    end
  end

  defp normalize_filter_value(nil), do: nil
  defp normalize_filter_value(value) when is_binary(value), do: Query.present_string(value)
  defp normalize_filter_value(value), do: value |> to_string() |> Query.present_string()

  defp matches_value?(_value, nil), do: true
  defp matches_value?(value, filter_value), do: value == filter_value

  defp matches_category?(_expense, nil), do: true
  defp matches_category?(expense, category), do: category in expense.categories

  defp matches_search?(_expense, ""), do: true

  defp matches_search?(expense, search) do
    expense
    |> expense_search_values()
    |> Enum.any?(fn value -> String.contains?(normalize_search(value), search) end)
  end

  defp expense_search_values(expense) do
    [
      expense.vendor_name,
      expense.invoice_number,
      expense.transaction_reference,
      expense.transaction_external_id,
      expense.transaction_counterparty_name,
      expense.status
    ] ++ expense.categories ++ Enum.flat_map(expense.line_items, &[&1.description, &1.category_name])
  end

  defp normalize_search(nil), do: ""

  defp normalize_search(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.trim()
  end

  defp blank_value?(nil), do: true
  defp blank_value?(""), do: true
  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(_value), do: false

  defp normalize_chart_widget(value) when value in @chart_widgets, do: value
  defp normalize_chart_widget(_value), do: @default_chart_widget

  defp chart_title("vendors"), do: gettext("Vendor breakdown")
  defp chart_title("categories"), do: gettext("Cost structure")
  defp chart_title(_chart), do: gettext("Spend trend")

  defp chart_empty_label("vendors"), do: gettext("No vendor spend in this period.")
  defp chart_empty_label("categories"), do: gettext("No categorized spend in this period.")
  defp chart_empty_label(_chart), do: gettext("Not enough invoice history yet to chart vendor spend.")

  defp chart_empty?("spend", spend_dates, _vendor_labels, _category_labels), do: spend_dates == []

  defp chart_empty?("vendors", _spend_dates, vendor_labels, _category_labels), do: vendor_labels == []

  defp chart_empty?("categories", _spend_dates, _vendor_labels, category_labels), do: category_labels == []

  defp chart_empty?(_chart, _spend_dates, _vendor_labels, _category_labels), do: true

  defp date_range_presets do
    [
      %{id: "last-30-days", label: gettext("Last 30 days"), period: {30, :day}},
      %{id: "last-90-days", label: gettext("Last 90 days"), period: {90, :day}},
      %{id: "last-12-months", label: gettext("Last 12 months"), period: {12, :month}},
      %{id: "custom", label: gettext("Custom")}
    ]
  end

  defp date_picker_params(params) do
    preset = Query.present_string(params["#{@date_range_prefix}-date-range"]) || @default_date_range_preset

    if preset == "custom" do
      custom_period(params, preset)
    else
      %{preset: preset, period: period_for_preset(preset)}
    end
  end

  defp custom_period(params, preset) do
    case {
      parse_date(params["#{@date_range_prefix}-start-date"], ~T[00:00:00]),
      parse_date(params["#{@date_range_prefix}-end-date"], ~T[23:59:59])
    } do
      {%DateTime{} = start_datetime, %DateTime{} = end_datetime} ->
        %{preset: preset, period: {start_datetime, end_datetime}}

      _other ->
        %{preset: @default_date_range_preset, period: period_for_preset(@default_date_range_preset)}
    end
  end

  defp period_for_preset(preset) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    start_datetime =
      case preset do
        "last-30-days" -> DateTime.add(now, -30, :day)
        "last-90-days" -> DateTime.add(now, -90, :day)
        "last-12-months" -> DateTime.add(now, -365, :day)
        _other -> DateTime.add(now, -365, :day)
      end

    {start_datetime, now}
  end

  defp analytics_filters({%DateTime{} = start_datetime, %DateTime{} = end_datetime}) do
    [
      date_from: DateTime.to_date(start_datetime),
      date_to: DateTime.to_date(end_datetime)
    ]
  end

  defp parse_date(nil, _fallback_time), do: nil

  defp parse_date(value, fallback_time) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        DateTime.new!(date, fallback_time, "Etc/UTC")

      {:error, _reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          {:error, _reason} -> nil
        end
    end
  end

  defp chart_vendor_summaries(vendors) do
    Enum.take(vendors, @vendor_chart_limit)
  end

  defp vendor_chart_overflow_summary(vendors) do
    {_visible_vendors, overflow_vendors} = Enum.split(vendors, @vendor_chart_limit)

    case overflow_vendors do
      [] ->
        nil

      vendors ->
        %{
          count: length(vendors),
          total_amount_value: sum_amounts(vendors, & &1.total_amount_value),
          total_amount_currency: dominant_currency(vendors, & &1.total_amount_currency)
        }
    end
  end

  defp vendor_chart_overflow_label(nil), do: nil

  defp vendor_chart_overflow_label(%{count: count, total_amount_value: amount, total_amount_currency: currency}) do
    ngettext(
      "Showing the top %{limit} vendors. %{count} additional vendor accounts for %{amount}.",
      "Showing the top %{limit} vendors. %{count} additional vendors account for %{amount}.",
      count,
      limit: @vendor_chart_limit,
      count: count,
      amount: format_amount(amount, currency)
    )
  end

  defp sum_amounts(items, mapper) do
    Enum.reduce(items, Decimal.new("0"), fn item, acc ->
      case mapper.(item) do
        %Decimal{} = value -> Decimal.add(acc, value)
        _value -> acc
      end
    end)
  end

  defp dominant_currency(items, mapper) do
    items
    |> Enum.map(mapper)
    |> Enum.reject(&blank_value?/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {currency, count} -> {count, currency} end, fn -> {"EUR", 0} end)
    |> elem(0)
  end

  defp scaled_category_spend(categories, {scale, _suffix}) do
    Enum.map(categories, fn category -> scaled_float(category.amount_value, scale) end)
  end

  defp scaled_vendor_spend(vendors, {scale, _suffix}) do
    Enum.map(vendors, fn vendor -> scaled_float(vendor.total_amount_value, scale) end)
  end

  defp scaled_float(%Decimal{} = value, scale) do
    value
    |> Decimal.div(Decimal.new(scale))
    |> Decimal.round(2)
    |> Decimal.to_float()
  end

  defp top_vendor_value(nil, _currency), do: "-"
  defp top_vendor_value(vendor, _currency), do: vendor.vendor_name

  defp top_vendor_caption(nil, _total_spend, _concentration), do: nil

  defp top_vendor_caption(vendor, total_spend, concentration) do
    gettext("%{amount} across %{count} invoices · %{share} of spend · top 5 %{concentration}",
      amount: format_amount(vendor.total_amount_value, vendor.total_amount_currency),
      count: vendor.invoice_count,
      share: vendor_share_label(vendor, total_spend),
      concentration: percent_label(concentration)
    )
  end

  defp top_category_value([]), do: "-"

  defp top_category_value([category | _rest]), do: category.category_name

  defp top_category_caption([], _currency), do: nil

  defp top_category_caption([category | _rest], _currency) do
    gettext("%{amount} across %{count} lines",
      amount: format_amount(category.amount_value, category.amount_currency),
      count: category.line_item_count
    )
  end

  defp percent_label(nil), do: "-"
  defp percent_label(%Decimal{} = value), do: "#{Decimal.to_string(value, :normal)}%"

  defp vendor_share_label(%{total_amount_value: %Decimal{} = amount}, %Decimal{} = total_spend) do
    if Decimal.equal?(total_spend, Decimal.new("0")) do
      "-"
    else
      amount
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.div(total_spend)
      |> Decimal.round(1)
      |> percent_label()
    end
  end

  defp vendor_share_label(_vendor, _total_spend), do: "-"

  defp ranked_bar_chart_options(labels, value_format) do
    %{
      grid: %{left: "24", right: "32", top: "6%", bottom: "10%", height: "82%", containLabel: true},
      legend: %{show: false},
      xAxis: %{
        type: "value",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: value_format
        },
        splitLine: %{lineStyle: %{color: "var:noora-surface-border-primary", type: "dashed"}}
      },
      yAxis: %{
        type: "category",
        inverse: true,
        splitNumber: 4,
        data: labels,
        splitLine: %{lineStyle: %{color: "var:noora-surface-border-primary", type: "dashed"}},
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          interval: 0,
          overflow: "truncate",
          width: 180
        }
      },
      tooltip: %{valueFormat: value_format}
    }
  end
end
