defmodule AtlasWeb.LicensesLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Accounts.Query
  alias Atlas.Licenses
  alias Atlas.Licenses.License
  alias AtlasWeb.Utilities.Query, as: WebQuery
  alias Noora.Filter
  alias Phoenix.HTML.Form

  @page_size 25

  def mount(_params, _session, socket) do
    customers = Query.list_license_eligible_accounts()

    {:ok,
     socket
     |> assign(:page_title, gettext("Licenses"))
     |> assign(:customers, customers)
     |> assign(:available_filters, define_filters(customers))
     |> assign(:extension_license, nil)
     |> assign(:extension_form, to_form(%{}, as: :extension))
     |> assign_license_form()}
  end

  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    uri = URI.new!("?" <> URI.encode_query(params))

    active_filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])
    page = WebQuery.parse_page(params["page"])

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:licenses_page, page)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign_licenses()}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         licenses_path(
           query,
           socket.assigns.active_filters,
           socket.assigns.sort_by,
           socket.assigns.sort_order
         ),
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = filter_id |> Filter.Operations.add_filter_to_query(socket) |> WebQuery.drop("page")

    {:noreply,
     socket
     |> push_patch(to: ~p"/sales/licenses?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = params |> Filter.Operations.update_filters_in_query(socket) |> WebQuery.drop("page")

    {:noreply,
     socket
     |> push_patch(to: ~p"/sales/licenses?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("validate_license", %{"license" => params}, socket) do
    form =
      params
      |> Licenses.change_license_request()
      |> Map.put(:action, :validate)
      |> to_form(as: :license)

    {:noreply, assign(socket, :license_form, form)}
  end

  def handle_event("filter_license_customers", %{"license_customer" => %{"query" => query}}, socket)
      when is_binary(query) do
    {:noreply, assign(socket, :customer_filter, query)}
  end

  def handle_event("select_license_customer", %{"data" => account_id}, socket) do
    select_license_customer(socket, account_id)
  end

  def handle_event("create_license", %{"license" => params}, socket) do
    case Licenses.create_license(params) do
      {:ok, _license} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("License created."))
         |> assign_license_form()
         |> assign_licenses()
         |> push_event("close-modal", %{id: "new-license-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not create the license."))
         |> assign(:license_form, to_form(changeset, as: :license))}
    end
  end

  def handle_event("close_new_license_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_license_form()
     |> push_event("close-modal", %{id: "new-license-modal"})}
  end

  def handle_event("new_license_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_license_form(socket)}
  end

  def handle_event("new_license_modal_open_changed", _params, socket), do: {:noreply, socket}

  def handle_event("open_extend_license", %{"id" => id}, socket) do
    case Licenses.get_license(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("License not found."))}

      license ->
        {:noreply,
         socket
         |> assign(:extension_license, license)
         |> assign_extension_form(license)
         |> push_event("open-modal", %{id: "extend-license-modal"})}
    end
  end

  def handle_event("validate_extension", %{"extension" => params}, socket) do
    case socket.assigns.extension_license do
      nil ->
        {:noreply, socket}

      license ->
        form =
          license
          |> Licenses.change_license_extension(params)
          |> Map.put(:action, :validate)
          |> to_form(as: :extension)

        {:noreply, assign(socket, :extension_form, form)}
    end
  end

  def handle_event("extend_license", %{"extension" => params}, socket) do
    case socket.assigns.extension_license do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("License not found."))}

      license ->
        case Licenses.extend_license(license, params) do
          {:ok, _license} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("License extended."))
             |> assign(:extension_license, nil)
             |> assign(:extension_form, to_form(%{}, as: :extension))
             |> assign_licenses()
             |> push_event("close-modal", %{id: "extend-license-modal"})}

          {:error, changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not extend the license."))
             |> assign(:extension_form, to_form(changeset, as: :extension))}
        end
    end
  end

  def handle_event("close_extend_license_modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "extend-license-modal"})}
  end

  def render(assigns) do
    ~H"""
    <div
      id="licenses"
      data-sort-by={@sort_by}
      data-sort-order={@sort_order}
      phx-hook=".LicenseAccessibility"
    >
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Licenses")}</h1>
          <p data-part="description">
            {gettext(
              "Issue online Tuist licenses and check out license files for air-gapped environments."
            )}
          </p>
        </div>

        <div data-part="header-actions">
          <.modal
            id="new-license-modal"
            title={gettext("Create license")}
            description={
              gettext("Connect the license to a customer or POC account and choose when it expires.")
            }
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_license_modal"
            on_open_change="new_license_modal_open_changed"
            data-part="new-license-modal"
          >
            <:header_icon><.lock /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-license-button"
                label={gettext("New license")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="license-create-modal-content">
              <.form
                id="new-license-form"
                for={@license_form}
                phx-submit="create_license"
              >
                <div data-part="license-create-form">
                  <div data-part="license-create-grid">
                    <div data-part="license-create-select">
                      <input
                        id="new-license-account-id"
                        type="hidden"
                        name={@license_form[:account_id].name}
                        value={Form.input_value(@license_form, :account_id)}
                      />

                      <.label label={gettext("Account")} required />
                      <.text_input
                        id="new-license-account-search"
                        type="search"
                        name="license_customer[query]"
                        value={@customer_filter}
                        placeholder={gettext("Filter accounts...")}
                        show_suffix={false}
                        phx-change="filter_license_customers"
                        phx-debounce="200"
                        data-part="license-create-customer-search"
                      />

                      <div
                        id="new-license-account-results"
                        data-part="license-create-customer-results"
                        role="listbox"
                        aria-label={gettext("Accounts")}
                      >
                        <.dropdown_item
                          :for={customer <- matching_customers(@customers, @customer_filter)}
                          id={"new-license-account-option-#{customer.id}"}
                          value={customer.id}
                          label={customer_option_label(customer)}
                          on_click="select_license_customer"
                          role="option"
                          aria-selected={customer.id == Form.input_value(@license_form, :account_id)}
                          data-selected={customer.id == Form.input_value(@license_form, :account_id)}
                        >
                          <:right_icon :if={
                            customer.id == Form.input_value(@license_form, :account_id)
                          }>
                            <.check />
                          </:right_icon>
                        </.dropdown_item>
                        <span
                          :if={matching_customers(@customers, @customer_filter) == []}
                          data-part="license-create-customer-empty"
                        >
                          {gettext("No accounts match your filter.")}
                        </span>
                      </div>
                      <span
                        :for={error <- field_errors(@license_form, :account_id)}
                        data-part="field-error"
                      >
                        {error}
                      </span>
                    </div>

                    <.text_input
                      id="new-license-expires-on-input"
                      field={@license_form[:expires_on]}
                      type="basic"
                      input_type="date"
                      label={gettext("Expiration date")}
                      required
                      show_required
                      show_suffix={false}
                    />
                  </div>

                  <div
                    :for={error <- field_errors(@license_form, :base)}
                    data-part="form-error"
                  >
                    {error}
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
                    phx-click="close_new_license_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-license-submit"
                    label={gettext("Create license")}
                    size="small"
                    type="submit"
                    form="new-license-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Customer licenses")} icon="lock" data-part="licenses-card">
        <.card_section data-part="licenses-table-section">
          <div data-part="filters">
            <.filter_dropdown
              id="licenses-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="licenses-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="licenses-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search by customer or domain...")}
                  aria-label={gettext("Search licenses")}
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} id="licenses-active-filters" data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <div :if={@licenses_empty?} id="licenses-empty-state" data-part="licenses-empty-state">
            <div data-part="icon" aria-hidden="true">
              <.lock />
            </div>
            <div data-part="title">{gettext("No matching licenses")}</div>
            <div data-part="subtitle">
              {gettext("Adjust the filters or create a customer license from this page.")}
            </div>
          </div>

          <.table
            :if={!@licenses_empty?}
            id="licenses-table"
            rows={@streams.licenses}
            row_key={fn {id, _license} -> id end}
          >
            <:col
              :let={{_id, license}}
              label={gettext("Customer")}
              patch={column_patch_sort(assigns, "customer")}
              sort_order={column_sort_order(assigns, "customer")}
            >
              <.link
                id={"license-account-link-#{license.id}"}
                navigate={~p"/sales/accounts/#{license.account.id}"}
                data-part="customer-link"
              >
                <.text_and_description_cell
                  label={license.account.name}
                  description={license.account.primary_domain || gettext("Customer account")}
                  icon="building"
                />
              </.link>
            </:col>
            <:col :let={{_id, license}} label={gettext("Online license key")}>
              <div data-part="license-key-cell">
                <code
                  id={"license-key-#{license.id}"}
                  data-part="license-key"
                  title={license.key}
                >
                  {license.key}
                </code>
                <.button
                  id={"copy-license-key-#{license.id}"}
                  variant="secondary"
                  size="small"
                  icon_only
                  type="button"
                  aria-label={gettext("Copy online license key")}
                  data-copy-value={license.key}
                  data-copy-success={gettext("License key copied")}
                  data-copy-error={gettext("Could not copy license key")}
                  data-part="copy-license-key"
                  phx-hook=".CopyLicenseKey"
                >
                  <.copy />
                </.button>
                <span
                  id={"copy-license-status-#{license.id}"}
                  data-part="copy-license-status"
                  aria-live="polite"
                >
                </span>
              </div>
            </:col>
            <:col
              :let={{_id, license}}
              label={gettext("Expiration date")}
              patch={column_patch_sort(assigns, "expires_on")}
              sort_order={column_sort_order(assigns, "expires_on")}
            >
              <.text_cell label={format_date(license.expires_on)} />
            </:col>
            <:col
              :let={{_id, license}}
              label={gettext("Status")}
              patch={column_patch_sort(assigns, "status")}
              sort_order={column_sort_order(assigns, "status")}
            >
              <.badge_cell
                id={"license-status-#{license.id}"}
                label={status_label(license)}
                color={status_color(license)}
                style="light-fill"
              />
            </:col>
            <:col :let={{_id, license}} label={gettext("Actions")}>
              <.button_cell>
                <:button>
                  <div
                    data-part="license-actions"
                    data-trigger-label={
                      gettext("More actions for %{customer}", customer: license.account.name)
                    }
                  >
                    <.button_dropdown
                      id={"license-actions-#{license.id}"}
                      label={gettext("Extend")}
                      size="medium"
                      align="end"
                      phx-click="open_extend_license"
                      phx-value-id={license.id}
                    >
                      <.dropdown_item
                        id={"air-gapped-checkout-#{license.id}"}
                        value={"air-gapped-checkout-#{license.id}"}
                        label={gettext("Check out air-gapped")}
                        href={~p"/sales/licenses/#{license.id}/air-gapped"}
                      >
                        <:left_icon><.download /></:left_icon>
                      </.dropdown_item>
                    </.button_dropdown>
                  </div>
                </:button>
              </.button_cell>
            </:col>
          </.table>

          <.pagination_group
            :if={@licenses_meta.total_pages > 1}
            id="licenses-pagination"
            data-part="licenses-pagination"
            current_page={@licenses_meta.current_page}
            number_of_pages={@licenses_meta.total_pages}
            page_patch={fn page -> "?#{WebQuery.put(@uri.query, "page", page)}" end}
          />
        </.card_section>
      </.card>

      <.modal
        id="extend-license-modal"
        title={gettext("Extend license")}
        description={gettext("Choose a later expiration date for this license.")}
        header_type="icon"
        header_size="large"
        on_dismiss="close_extend_license_modal"
        data-part="extend-license-modal"
      >
        <:header_icon><.lock /></:header_icon>
        <:trigger :let={modal_attrs}>
          <button id="extend-license-modal-trigger" type="button" hidden {modal_attrs}></button>
        </:trigger>

        <div data-part="license-extension-modal-content">
          <.form
            id="extend-license-form"
            for={@extension_form}
            phx-change="validate_extension"
            phx-submit="extend_license"
          >
            <div data-part="license-extension-form">
              <div :if={@extension_license} data-part="license-extension-summary">
                <div data-part="license-extension-detail">
                  <span data-part="label">{gettext("Customer")}</span>
                  <span data-part="value">{@extension_license.account.name}</span>
                </div>
                <div data-part="license-extension-detail">
                  <span data-part="label">{gettext("Current expiration")}</span>
                  <span data-part="value">{format_date(@extension_license.expires_on)}</span>
                </div>
              </div>

              <.text_input
                id="extend-license-expires-on-input"
                field={@extension_form[:expires_on]}
                type="basic"
                input_type="date"
                label={gettext("New expiration date")}
                required
                show_required
                show_suffix={false}
              />
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
                phx-click="close_extend_license_modal"
              />
            </:action>
            <:action>
              <.button
                id="extend-license-submit"
                label={gettext("Extend license")}
                size="small"
                type="submit"
                form="extend-license-form"
              />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLicenseKey">
        export default {
          mounted() {
            this.status = this.el.parentElement.querySelector("[data-part='copy-license-status']")
            this.copy = async () => {
              window.clearTimeout(this.clearStatusTimer)

              try {
                if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable")
                await navigator.clipboard.writeText(this.el.dataset.copyValue)
                this.el.dataset.copyState = "success"
                this.status.textContent = this.el.dataset.copySuccess
                this.clearStatusTimer = window.setTimeout(() => {
                  delete this.el.dataset.copyState
                  this.status.textContent = ""
                }, 2000)
              } catch (_error) {
                this.el.dataset.copyState = "error"
                this.status.textContent = this.el.dataset.copyError
              }
            }
            this.el.addEventListener("click", this.copy)
          },
          destroyed() {
            window.clearTimeout(this.clearStatusTimer)
            this.el.removeEventListener("click", this.copy)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LicenseAccessibility">
        export default {
          mounted() { this.updateAccessibleState() },
          updated() { this.updateAccessibleState() },
          updateAccessibleState() {
            this.el.querySelectorAll("[data-part='license-actions']").forEach(actions => {
              const trigger = actions.querySelector("[data-part='trigger']")
              if (trigger) trigger.setAttribute("aria-label", actions.dataset.triggerLabel)
            })

            const columnIndexes = {customer: 0, expires_on: 2, status: 3}
            const headers = this.el.querySelectorAll("#licenses-table thead th")
            headers.forEach(header => header.removeAttribute("aria-sort"))
            const columnIndex = columnIndexes[this.el.dataset.sortBy]
            if (columnIndex !== undefined && headers[columnIndex]) {
              headers[columnIndex].setAttribute(
                "aria-sort",
                this.el.dataset.sortOrder === "asc" ? "ascending" : "descending"
              )
            }
          }
        }
      </script>
    </div>
    """
  end

  defp assign_licenses(socket) do
    {licenses, meta} = list_licenses(socket, socket.assigns.licenses_page)

    {licenses, meta, clamped?} =
      if licenses == [] and meta.total_pages > 0 and socket.assigns.licenses_page > meta.total_pages do
        {last_page_licenses, last_page_meta} = list_licenses(socket, meta.total_pages)
        {last_page_licenses, last_page_meta, true}
      else
        {licenses, meta, false}
      end

    socket =
      socket
      |> assign(:licenses_page, meta.current_page)
      |> assign(:licenses_empty?, licenses == [])
      |> assign(:licenses_meta, meta)
      |> stream(:licenses, licenses, reset: true)

    if clamped? do
      push_patch(socket,
        to: "/sales/licenses?#{WebQuery.put(socket.assigns.uri.query, "page", meta.current_page)}",
        replace: true
      )
    else
      socket
    end
  end

  defp list_licenses(socket, page) do
    Licenses.list_licenses_page(
      filters: socket.assigns.active_filters,
      query: socket.assigns.query,
      sort_by: socket.assigns.sort_by,
      sort_order: socket.assigns.sort_order,
      page: page,
      page_size: @page_size
    )
  end

  defp assign_license_form(socket) do
    defaults = %{"expires_on" => Date.utc_today() |> Date.add(365) |> Date.to_iso8601()}

    socket
    |> assign(:customer_filter, "")
    |> assign(:license_form, Licenses.change_license_request(defaults) |> to_form(as: :license))
  end

  defp assign_extension_form(socket, license) do
    base_date =
      if Date.before?(license.expires_on, Date.utc_today()), do: Date.utc_today(), else: license.expires_on

    defaults = %{"expires_on" => base_date |> Date.add(365) |> Date.to_iso8601()}

    assign(
      socket,
      :extension_form,
      license |> Licenses.change_license_extension(defaults) |> to_form(as: :extension)
    )
  end

  defp field_errors(form, field) do
    form[field].errors
    |> Enum.map(&AtlasWeb.CoreComponents.translate_error/1)
  end

  defp license_request_params(form) do
    %{
      "account_id" => Form.input_value(form, :account_id),
      "expires_on" => Form.input_value(form, :expires_on)
    }
  end

  defp select_license_customer(socket, account_id) do
    case Enum.find(socket.assigns.customers, &(&1.id == account_id)) do
      nil ->
        {:noreply, socket}

      customer ->
        form =
          socket.assigns.license_form
          |> license_request_params()
          |> Map.put("account_id", account_id)
          |> Licenses.change_license_request()
          |> Map.put(:action, :validate)
          |> to_form(as: :license)

        {:noreply,
         socket
         |> assign(:customer_filter, customer_option_label(customer))
         |> assign(:license_form, form)}
    end
  end

  defp matching_customers(customers, customer_filter) do
    case String.trim(customer_filter) do
      "" ->
        customers

      query ->
        normalized_query = String.downcase(query)

        Enum.filter(customers, fn customer ->
          customer
          |> customer_option_label()
          |> String.downcase()
          |> String.contains?(normalized_query)
        end)
    end
  end

  def column_patch_sort(%{uri: uri, sort_by: current_sort_by, sort_order: current_sort_order}, column) do
    next_order =
      case {current_sort_by == column, current_sort_order} do
        {true, "asc"} -> "desc"
        {true, _other_order} -> "asc"
        {false, _other_order} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)
      |> Map.delete("page")

    "?" <> URI.encode_query(query_params)
  end

  defp column_sort_order(%{sort_by: column, sort_order: sort_order}, column), do: sort_order
  defp column_sort_order(_assigns, _column), do: nil

  defp licenses_path(query, active_filters, sort_by, sort_order) do
    params =
      %{}
      |> WebQuery.put_present("q", WebQuery.present_string(query))
      |> WebQuery.put_present("sort-by", sort_by)
      |> WebQuery.put_present("sort-order", if(sort_by, do: sort_order))
      |> Map.merge(Filter.Operations.encode_filters_to_query(active_filters))

    ~p"/sales/licenses?#{params}"
  end

  defp normalize_sort_by(value) when is_binary(value) do
    if value in Licenses.sortable_fields(), do: value
  end

  defp normalize_sort_by(_value), do: nil

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order(_value), do: "desc"

  def customer_option_label(%{name: name, primary_domain: domain}) when is_binary(domain) and domain != "" do
    "#{name} (#{domain})"
  end

  def customer_option_label(%{name: name, account_key: account_key})
      when is_binary(account_key) and account_key != "" do
    "#{name} (#{account_key})"
  end

  def customer_option_label(customer), do: customer.name

  defp define_filters(customers) do
    customer_filter = %Filter.Filter{
      id: "customer",
      field: :account_id,
      display_name: gettext("Customer"),
      type: :option,
      searchable: true,
      options: Enum.map(customers, & &1.id),
      options_display_names: Map.new(customers, &{&1.id, customer_option_label(&1)}),
      operator: :==,
      value: nil
    }

    status_filter = %Filter.Filter{
      id: "status",
      field: :status,
      display_name: gettext("Status"),
      type: :option,
      options: ["active", "expired"],
      options_display_names: %{
        "active" => gettext("Active"),
        "expired" => gettext("Expired")
      },
      operator: :==,
      value: nil
    }

    [customer_filter, status_filter]
  end

  defp format_date(date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp status_label(%License{expires_on: expires_on}) do
    if Date.before?(expires_on, Date.utc_today()), do: gettext("Expired"), else: gettext("Active")
  end

  defp status_color(%License{expires_on: expires_on}) do
    if Date.before?(expires_on, Date.utc_today()), do: "destructive", else: "success"
  end
end
