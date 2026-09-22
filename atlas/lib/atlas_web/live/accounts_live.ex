defmodule AtlasWeb.AccountsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.RevenueComponents
  import Noora.Filter

  alias Atlas.Accounts
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Query
  alias AtlasWeb.Utilities.Query, as: WebQuery
  alias Noora.Filter

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Accounts"))
     |> assign(:available_filters, define_filters())
     |> assign_new_account_form()}
  end

  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    uri = URI.new!("?" <> URI.encode_query(params))

    active_filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    list_opts =
      [
        filters: active_filters,
        query: query,
        sort_by: sort_by,
        sort_order: sort_order
      ]

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign(:accounts, Accounts.list_accounts(list_opts))}
  end

  def render(assigns) do
    ~H"""
    <div id="accounts">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Accounts")}</h1>
          <p data-part="description">
            {gettext(
              "Customers, leads, and prospects stored in Atlas so the product can operate from local revenue data."
            )}
          </p>
        </div>

        <div data-part="header-actions">
          <.modal
            id="new-account-modal"
            title={gettext("Create account")}
            description={
              gettext("Add a manually managed account to Atlas and fill in commercial details later.")
            }
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_account_modal"
            data-part="new-account-modal"
          >
            <:header_icon><.user /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-account-button"
                label={gettext("New account")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.circle_plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="account-create-modal-content">
              <.form
                id="new-account-form"
                for={@account_form}
                phx-change="validate_account"
                phx-submit="create_account"
              >
                <div data-part="account-create-form">
                  <div data-part="account-create-grid">
                    <.text_input
                      id="new-account-name-input"
                      field={@account_form[:name]}
                      type="basic"
                      label={gettext("Name")}
                      required
                      show_required
                      show_suffix={false}
                    />

                    <.text_input
                      id="new-account-primary-domain-input"
                      field={@account_form[:primary_domain]}
                      type="basic"
                      label={gettext("Primary domain")}
                      placeholder={gettext("example.com")}
                      show_suffix={false}
                    />

                    <div data-part="account-create-select">
                      <.label label={gettext("Lifecycle")} required />
                      <.select
                        id="new-account-segment-select"
                        name={@account_form[:segment].name}
                        label={gettext("Select lifecycle")}
                        value={select_value(@account_form[:segment].value)}
                      >
                        <:item value="prospect" label={gettext("Prospect")} />
                        <:item value="lead" label={gettext("Lead")} />
                        <:item value="customer" label={gettext("Customer")} />
                      </.select>
                    </div>

                    <div data-part="account-create-select">
                      <.label label={gettext("Deal stage")} />
                      <.select
                        id="new-account-deal-stage-select"
                        name={@account_form[:deal_stage].name}
                        label={gettext("Select deal stage")}
                        value={select_value(@account_form[:deal_stage].value)}
                      >
                        <:item value="_none" label={gettext("None")} />
                        <:item
                          :for={stage <- DealStage.all()}
                          value={stage.key}
                          label={stage.label}
                        />
                      </.select>
                    </div>

                    <.text_input
                      id="new-account-currency-input"
                      field={@account_form[:currency]}
                      type="basic"
                      label={gettext("Currency")}
                      placeholder={gettext("USD")}
                      show_suffix={false}
                    />

                    <.text_input
                      id="new-account-current-value-input"
                      field={@account_form[:current_value]}
                      type="basic"
                      input_type="number"
                      label={gettext("Current value")}
                      min="0"
                      step="0.01"
                      show_suffix={false}
                    />

                    <div data-part="account-create-grid-full">
                      <.text_area
                        id="new-account-description-input"
                        field={@account_form[:description]}
                        label={gettext("Description")}
                        placeholder={
                          gettext("Relationship context, commercial notes, or account summary")
                        }
                        rows={3}
                        max_length={600}
                      />
                    </div>
                  </div>
                </div>
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_new_account_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-account-submit"
                    label={gettext("Create account")}
                    size="small"
                    type="submit"
                    form="new-account-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Accounts")} icon="users" data-part="accounts-card">
        <.card_section data-part="accounts-table-section">
          <div data-part="filters">
            <.filter_dropdown
              id="accounts-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="accounts-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="accounts-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search by name, domain, or handle...")}
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <.table
            id="accounts-table"
            rows={@accounts}
            row_navigate={fn account -> ~p"/commercial/sales/accounts/#{account.id}" end}
          >
            <:col
              :let={account}
              label={gettext("Account")}
              patch={column_patch_sort(assigns, "name")}
              icon={sort_icon(assigns, "name")}
            >
              <.text_and_description_cell
                label={account.name}
                description={account.primary_domain || "-"}
              >
                <:image :if={account.primary_domain}>
                  <img
                    src={domain_favicon_url(account.primary_domain, 128)}
                    alt=""
                    referrerpolicy="no-referrer"
                    loading="lazy"
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col
              :let={account}
              label={gettext("Lifecycle")}
              patch={column_patch_sort(assigns, "lifecycle")}
              icon={sort_icon(assigns, "lifecycle")}
            >
              <.account_lifecycle_badge_cell segment={account.segment} />
            </:col>
            <:col
              :let={account}
              label={gettext("Deal Stage")}
              patch={column_patch_sort(assigns, "deal_stage")}
              icon={sort_icon(assigns, "deal_stage")}
            >
              <.account_deal_stage_badge_cell deal_stage={account.deal_stage} />
            </:col>
            <:col
              :let={account}
              label={gettext("Value")}
              patch={column_patch_sort(assigns, "value")}
              icon={sort_icon(assigns, "value")}
            >
              <.text_cell label={contract_value_label(account)} />
            </:col>
            <:col
              :let={account}
              label={gettext("Next Milestone")}
              patch={column_patch_sort(assigns, "next_milestone")}
              icon={sort_icon(assigns, "next_milestone")}
            >
              <.text_cell label={next_milestone_label(account)} />
            </:col>
            <:col
              :let={account}
              label={gettext("Contacts")}
              patch={column_patch_sort(assigns, "contacts")}
              icon={sort_icon(assigns, "contacts")}
            >
              <.badge_cell label={"#{account.contacts_count}"} color="neutral" />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="building"
                title={gettext("No accounts yet")}
                subtitle={gettext("Add account records to Atlas and they will appear here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         accounts_path(
           query,
           socket.assigns.active_filters,
           socket.assigns.sort_by,
           socket.assigns.sort_order
         ),
       replace: true
     )}
  end

  def handle_event("validate_account", %{"account" => params}, socket) do
    form =
      params
      |> Accounts.change_manual_account()
      |> Map.put(:action, :validate)
      |> to_form(as: "account")

    {:noreply, assign(socket, :account_form, form)}
  end

  def handle_event("create_account", %{"account" => params}, socket) do
    case Accounts.create_manual_account(params) do
      {:ok, account} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account created."))
         |> push_navigate(to: ~p"/commercial/sales/accounts/#{account.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :account_form, to_form(changeset, as: "account"))}
    end
  end

  def handle_event("close_new_account_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_account_form()
     |> push_event("close-modal", %{id: "new-account-modal"})}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/commercial/sales/accounts?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/commercial/sales/accounts?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def column_patch_sort(%{uri: uri, sort_by: current_sort_by, sort_order: current_sort_order}, column) do
    next_order =
      case {current_sort_by == column, current_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)

    "?" <> URI.encode_query(query_params)
  end

  def sort_icon(%{sort_by: column, sort_order: "asc"}, column), do: "square_rounded_arrow_up"
  def sort_icon(%{sort_by: column}, column), do: "square_rounded_arrow_down"
  def sort_icon(_assigns, _column), do: nil

  defp accounts_path(query, active_filters, sort_by, sort_order) do
    params =
      %{}
      |> WebQuery.put_present("q", WebQuery.present_string(query))
      |> WebQuery.put_present("sort-by", sort_by)
      |> WebQuery.put_present("sort-order", if(sort_by, do: sort_order))
      |> Map.merge(Filter.Operations.encode_filters_to_query(active_filters))

    ~p"/commercial/sales/accounts?#{params}"
  end

  defp assign_new_account_form(socket) do
    assign(socket, :account_form, to_form(Accounts.change_manual_account(), as: "account"))
  end

  defp select_value(nil), do: nil
  defp select_value(value) when is_atom(value), do: Atom.to_string(value)
  defp select_value(value), do: to_string(value)

  defp normalize_sort_by(value) when is_binary(value) do
    if value in Query.sortable_fields(), do: value
  end

  defp normalize_sort_by(_), do: nil

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order(_), do: "desc"

  defp next_milestone_label(account) do
    cond do
      account.next_renewal_date ->
        gettext("Renews %{date}", date: format_date(account.next_renewal_date))

      account.latest_activity_at ->
        gettext("Updated %{date}", date: format_datetime(account.latest_activity_at))

      true ->
        "-"
    end
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
  defp format_date(_date), do: "-"

  defp format_datetime(%DateTime{} = date_time), do: Calendar.strftime(date_time, "%b %d, %Y")
  defp format_datetime(_date_time), do: "-"

  defp contract_value_label(account) do
    {value, currency} = Accounts.contract_value(account)
    Amounts.format(value, currency)
  end

  defp define_filters do
    lifecycles = Accounts.account_filters().lifecycles

    lifecycle_filters =
      if lifecycles == [] do
        []
      else
        [
          %Filter.Filter{
            id: "lifecycle",
            field: :lifecycle,
            display_name: gettext("Lifecycle"),
            type: :option,
            searchable: true,
            options: Enum.map(lifecycles, & &1.key),
            options_display_names: Map.new(lifecycles, &{&1.key, &1.label}),
            operator: :==,
            value: nil
          }
        ]
      end

    deal_stages = DealStage.all()

    deal_stage_filter = %Filter.Filter{
      id: "deal_stage",
      field: :deal_stage,
      display_name: gettext("Deal stage"),
      type: :option,
      searchable: true,
      options: Enum.map(deal_stages, & &1.key),
      options_display_names: Map.new(deal_stages, &{&1.key, &1.label}),
      operator: :==,
      value: nil
    }

    needs_attention_filter = %Filter.Filter{
      id: "needs_attention",
      field: :needs_attention,
      display_name: gettext("Needs attention"),
      type: :option,
      options: ["true"],
      options_display_names: %{"true" => gettext("In legal or security review")},
      operator: :==,
      value: nil
    }

    lifecycle_filters ++ [deal_stage_filter, needs_attention_filter]
  end
end
