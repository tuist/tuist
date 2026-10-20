defmodule AtlasWeb.SalesLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.PaginationComponents
  import AtlasWeb.RevenueComponents
  import AtlasWeb.Widget

  alias Atlas.Accounts
  alias Atlas.Accounts.Amounts
  alias AtlasWeb.Utilities.Query

  @upcoming_renewals_limit 8
  @invoices_limit 15

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Sales"))}
  end

  def handle_params(_params, uri, socket) do
    parsed_uri = URI.parse(uri)
    query_params = Query.query_params(uri)

    upcoming_renewals = Accounts.list_upcoming_renewals(limit: @upcoming_renewals_limit)
    revenue_snapshot = Accounts.revenue_snapshot()

    {invoices, invoices_meta} =
      Accounts.sales_overview_invoices(
        limit: @invoices_limit,
        after: query_params["invoices-after"],
        before: query_params["invoices-before"],
        stripe_fixture: query_params["_stripe_fixture"]
      )

    outstanding = Accounts.outstanding_invoices_summary()

    {:noreply,
     socket
     |> assign(:uri, parsed_uri)
     |> assign(:upcoming_renewals, upcoming_renewals)
     |> assign(:revenue_snapshot, revenue_snapshot)
     |> assign(:invoices, invoices)
     |> assign(:invoices_meta, invoices_meta)
     |> assign(:outstanding, outstanding)}
  end

  def render(assigns) do
    ~H"""
    <div id="sales">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Sales")}</h1>
          <p data-part="description">
            {gettext("Where the deal is now and what should move it next.")}
          </p>
        </div>
      </div>

      <.card title={gettext("Revenue snapshot")} icon="building" data-part="revenue-card">
        <.card_section data-part="revenue-section">
          <div data-part="widgets">
            <.widget
              id="sales-widget-mrr"
              title={gettext("MRR Equivalent")}
              value={Amounts.format(@revenue_snapshot.monthly_revenue_eur, "EUR")}
              tooltip_description={mrr_tooltip_description(@revenue_snapshot)}
              legend_color="primary"
            />
            <.widget
              id="sales-widget-arr"
              title={gettext("Estimated ARR")}
              value={Amounts.format(@revenue_snapshot.estimated_arr_eur, "EUR")}
              tooltip_description={arr_tooltip_description(@revenue_snapshot)}
              legend_color="secondary"
            />
            <.widget
              id="sales-widget-outstanding"
              title={gettext("Outstanding")}
              value={Amounts.format(@outstanding.total_eur, "EUR")}
              description={outstanding_description(@outstanding)}
              legend_color={if(@outstanding.overdue_count > 0, do: "destructive", else: "primary")}
            />
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Upcoming renewals")} icon="calendar_week" data-part="renewals-card">
        <.card_section data-part="renewals-table-section">
          <.table
            id="sales-renewals-table"
            rows={@upcoming_renewals}
            row_navigate={fn account -> ~p"/commercial/sales/accounts/#{account.id}" end}
          >
            <:col :let={account} label={gettext("Account")}>
              <.text_and_description_cell
                label={account.name}
                description={account.primary_domain || account.legal_name || "-"}
              >
                <:image>
                  <img
                    :if={account.primary_domain}
                    src={domain_favicon_url(account.primary_domain, 128)}
                    alt=""
                    referrerpolicy="no-referrer"
                    loading="lazy"
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={account} label={gettext("Renewal Date")}>
              <.text_and_description_cell
                label={renewal_date_label(account.next_renewal_date)}
                description={renewal_countdown_label(account.next_renewal_date)}
              />
            </:col>
            <:col :let={account} label={gettext("Value")}>
              <.text_cell label={contract_value_label(account)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="calendar_week"
                title={gettext("No upcoming renewals")}
                subtitle={
                  gettext("Active customer accounts with a future renewal date will show up here.")
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card
        :if={false}
        title={gettext("Customer outcome health")}
        icon="chart_dots"
        data-part="outcome-health-card"
      >
        <.card_section data-part="pipeline-section">
          <div data-part="widgets">
            <.widget
              id="sales-widget-on-track"
              title={gettext("On track")}
              value={Integer.to_string(@counts.on_track)}
              description={gettext("Evidence supports success")}
              legend_color="primary"
            />
            <.widget
              id="sales-widget-at-risk"
              title={gettext("At risk")}
              value={Integer.to_string(@counts.at_risk)}
              description={gettext("Needs intervention")}
              legend_color="attention"
            />
            <.widget
              id="sales-widget-off-track"
              title={gettext("Off track")}
              value={Integer.to_string(@counts.off_track)}
              description={gettext("Outcome is blocked")}
              legend_color="destructive"
            />
            <.widget
              id="sales-widget-missing-outcome"
              title={gettext("Missing outcome")}
              value={Integer.to_string(@counts.accounts_without_outcomes)}
              description={gettext("Active accounts without a result")}
              legend_color="neutral"
            />
          </div>
        </.card_section>
      </.card>

      <.card
        :if={false}
        title={gettext("Outcomes needing attention")}
        icon="checkup_list"
        data-part="attention-card"
      >
        <:actions>
          <div data-part="attention-card-actions">
            <.badge
              id="sales-overdue-badge"
              label={gettext("%{count} overdue", count: @counts.overdue_outcomes)}
              color={if(@counts.overdue_outcomes > 0, do: "destructive", else: "neutral")}
              style="light-fill"
            />
            <.badge
              id="sales-at-risk-badge"
              label={gettext("%{count} at risk", count: @counts.at_risk)}
              color="warning"
              style="light-fill"
            />
          </div>
        </:actions>
        <.card_section data-part="attention-table-section">
          <.table
            id="sales-attention-items-table"
            rows={@attention_items}
          >
            <:col :let={outcome} label={gettext("Account")}>
              <.link navigate={~p"/commercial/sales/accounts/#{outcome.account.id}"} data-part="link">
                <.text_and_description_cell
                  label={outcome.account.name}
                  description={outcome.account.primary_domain || "-"}
                >
                  <:image>
                    <img
                      :if={outcome.account.primary_domain}
                      src={domain_favicon_url(outcome.account.primary_domain, 128)}
                      alt=""
                      referrerpolicy="no-referrer"
                      loading="lazy"
                    />
                  </:image>
                </.text_and_description_cell>
              </.link>
            </:col>
            <:col :let={outcome} label={gettext("Health")}>
              <.badge_cell
                label={outcome_health_label(outcome.health)}
                color={outcome_health_color(outcome.health)}
                style="light-fill"
              />
            </:col>
            <:col :let={outcome} label={gettext("Outcome")}>
              <.text_and_description_cell
                label={outcome.title}
                description={outcome.success_measure || outcome.description || "-"}
              />
            </:col>
            <:col :let={outcome} label={gettext("Target")}>
              <.text_and_description_cell
                label={outcome.target || "-"}
                description={target_date_label(outcome.target_date)}
              />
            </:col>
            <:col :let={outcome} label={gettext("Recommended next move")}>
              <.text_cell label={latest_recommendation(outcome) || gettext("Review this outcome")} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="checkup_list"
                title={gettext("Nothing needs attention right now")}
                subtitle={gettext("At-risk and off-track customer outcomes will show up here.")}
              />
            </:empty_state>
          </.table>
          <.pagination
            :if={@attention_meta.has_previous_page? or @attention_meta.has_next_page?}
            uri={@uri}
            has_previous_page={@attention_meta.has_previous_page?}
            has_next_page={@attention_meta.has_next_page?}
            start_cursor={@attention_meta.start_cursor}
            end_cursor={@attention_meta.end_cursor}
            before_param="attention-before"
            after_param="attention-after"
          />
        </.card_section>
      </.card>

      <.card title={gettext("Invoices")} icon="file" data-part="invoices-card">
        <.card_section data-part="invoices-table-section">
          <.table
            id="sales-invoices-table"
            rows={@invoices}
            row_key={fn row -> "sales-invoices-row-#{row.invoice.id}" end}
          >
            <:col :let={row} label={gettext("Account")}>
              <.text_and_description_cell
                label={invoice_account_name(row)}
                description={invoice_account_description(row)}
              >
                <:image>
                  <img
                    :if={row.account && row.account.primary_domain}
                    src={domain_favicon_url(row.account.primary_domain, 128)}
                    alt=""
                    referrerpolicy="no-referrer"
                    loading="lazy"
                  />
                  <.avatar
                    :if={!(row.account && row.account.primary_domain)}
                    id={"sales-invoices-avatar-#{row.invoice.id}"}
                    name={invoice_avatar_name(row)}
                    size="medium"
                    color="gray"
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={row} label={gettext("Number")}>
              <.text_cell label={row.invoice.number || "-"} />
            </:col>
            <:col :let={row} label={gettext("Amount")}>
              <.text_cell label={
                Amounts.format_or_nil(row.invoice.amount_value, row.invoice.amount_currency) || "-"
              } />
            </:col>
            <:col :let={row} label={gettext("Due")}>
              <.text_cell label={invoice_due_label(row.invoice)} />
            </:col>
            <:col :let={row} label={gettext("Status")}>
              <.badge_cell
                label={invoice_status_label(row.invoice.status)}
                color={invoice_status_color(row.invoice.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={row} label={gettext("Reference")}>
              <.button
                :if={invoice_url(row.invoice)}
                label={gettext("Open in Stripe")}
                variant="secondary"
                size="small"
                href={invoice_url(row.invoice)}
                target="_blank"
                rel="noopener noreferrer"
              >
                <:icon_right><.icon name="external_link" /></:icon_right>
              </.button>
              <span :if={!invoice_url(row.invoice)}>-</span>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="file"
                title={gettext("No open or scheduled invoices")}
                subtitle={
                  gettext(
                    "Open invoices with a balance and draft invoices scheduled to be sent from Stripe will show up here."
                  )
                }
              />
            </:empty_state>
          </.table>
          <.pagination
            :if={@invoices_meta.has_previous_page? or @invoices_meta.has_next_page?}
            uri={@uri}
            has_previous_page={@invoices_meta.has_previous_page?}
            has_next_page={@invoices_meta.has_next_page?}
            start_cursor={@invoices_meta.start_cursor}
            end_cursor={@invoices_meta.end_cursor}
            before_param="invoices-before"
            after_param="invoices-after"
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  defp invoice_account_name(%{account: %{name: name}}) when is_binary(name), do: name
  defp invoice_account_name(%{invoice: %{customer_name: name}}) when is_binary(name), do: name
  defp invoice_account_name(%{invoice: %{customer_email: email}}) when is_binary(email), do: email
  defp invoice_account_name(_row), do: gettext("Unlinked customer")

  defp invoice_account_description(%{account: %{primary_domain: domain}}) when is_binary(domain), do: domain

  defp invoice_account_description(%{invoice: %{customer_name: name, customer_email: email}})
       when is_binary(name) and is_binary(email), do: email

  defp invoice_account_description(%{invoice: %{customer_id: customer_id}}) when is_binary(customer_id), do: customer_id

  defp invoice_account_description(_row), do: "-"

  defp invoice_avatar_name(%{account: %{name: name}}) when is_binary(name), do: name
  defp invoice_avatar_name(%{invoice: %{customer_name: name}}) when is_binary(name), do: name
  defp invoice_avatar_name(%{invoice: %{customer_email: email}}) when is_binary(email), do: email
  defp invoice_avatar_name(_row), do: gettext("Unlinked customer")

  defp invoice_due_label(%{due_date: %Date{} = due_date}) do
    today = Date.utc_today()

    case Date.compare(due_date, today) do
      :lt -> gettext("Overdue %{date}", date: format_date(due_date))
      :eq -> gettext("Due today")
      :gt -> gettext("Due %{date}", date: format_date(due_date))
    end
  end

  defp invoice_due_label(_invoice), do: "-"

  defp invoice_status_label("open"), do: gettext("Open")
  defp invoice_status_label("draft"), do: gettext("Scheduled")
  defp invoice_status_label(status) when is_binary(status), do: String.capitalize(status)
  defp invoice_status_label(_status), do: "-"

  defp invoice_status_color("open"), do: "primary"
  defp invoice_status_color("draft"), do: "neutral"
  defp invoice_status_color(_status), do: "neutral"

  defp invoice_url(%{id: id}) when is_binary(id), do: "https://dashboard.stripe.com/invoices/#{id}"
  defp invoice_url(_invoice), do: nil

  defp contract_value_label(account) do
    {value, currency} = Accounts.contract_value(account)
    Amounts.format(value, currency)
  end

  defp renewal_date_label(%Date{} = renewal_date), do: format_date(renewal_date)
  defp renewal_date_label(_renewal_date), do: "-"

  defp renewal_countdown_label(%Date{} = renewal_date) do
    today = Date.utc_today()
    days = Date.diff(renewal_date, today)

    cond do
      days == 0 -> gettext("Renews today")
      days == 1 -> gettext("Renews tomorrow")
      days > 1 -> gettext("Renews in %{days} days", days: days)
      true -> gettext("Renewal date passed")
    end
  end

  defp renewal_countdown_label(_renewal_date), do: "-"

  defp outcome_health_label("on_track"), do: gettext("On track")
  defp outcome_health_label("at_risk"), do: gettext("At risk")
  defp outcome_health_label("off_track"), do: gettext("Off track")
  defp outcome_health_label(_health), do: gettext("Unknown")

  defp outcome_health_color("on_track"), do: "success"
  defp outcome_health_color("at_risk"), do: "warning"
  defp outcome_health_color("off_track"), do: "destructive"
  defp outcome_health_color(_health), do: "neutral"

  defp target_date_label(%Date{} = date), do: gettext("By %{date}", date: format_date(date))
  defp target_date_label(_date), do: gettext("No target date")

  defp latest_recommendation(%{reviews: [%{recommendation: recommendation} | _reviews]})
       when is_binary(recommendation) and recommendation != "", do: recommendation

  defp latest_recommendation(_outcome), do: nil

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp outstanding_description(%{count: 0}), do: gettext("No open invoices")

  defp outstanding_description(%{count: count, overdue_count: 0}),
    do: gettext("Across %{count} open invoices", count: count)

  defp outstanding_description(%{count: count, overdue_count: overdue}),
    do: gettext("Across %{count} open invoices, %{overdue} overdue", count: count, overdue: overdue)

  defp mrr_tooltip_description(_snapshot) do
    gettext("Normalizes each renewable customer contract by term length to estimate monthly recurring revenue in EUR.")
  end

  defp arr_tooltip_description(%{published_on: %Date{} = published_on}) do
    gettext(
      "Annualizes the MRR equivalent and assumes those renewable customer contracts renew. USD-denominated contracts are converted to EUR using the latest ECB reference published on %{date}.",
      date: format_date(published_on)
    )
  end

  defp arr_tooltip_description(_snapshot) do
    gettext("Annualizes the MRR equivalent and assumes those renewable customer contracts renew.")
  end
end
