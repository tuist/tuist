defmodule AtlasWeb.HardwareLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias AtlasWeb.Utilities.Query, as: WebQuery
  alias Noora.Filter

  @page_size 50
  @sortable_fields ~w(name category state location acquisition_cost warranty_end_on)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Hardware"))
     |> assign(:available_filters, define_filters())
     |> assign(:active_filters, [])
     |> assign(:query, "")
     |> assign(:sort_by, "name")
     |> assign(:sort_order, "asc")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign_new_form()}
  end

  def handle_params(params, _uri, socket) do
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    query = WebQuery.present_string(params["q"]) || ""
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> load_assets()}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = String.trim(query || "")
    updated = socket |> current_params() |> WebQuery.put_present("q", WebQuery.present_string(query))

    {:noreply, push_patch(socket, to: ~p"/hardware?#{updated}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/hardware?#{updated}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/hardware?#{updated}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("validate_new_asset", %{"asset" => attrs}, socket) do
    form =
      attrs
      |> Assets.change_asset()
      |> Map.put(:action, :validate)
      |> to_form(as: :asset)

    {:noreply, assign(socket, :asset_form, form)}
  end

  def handle_event("create_asset", %{"asset" => attrs}, socket) do
    case Assets.create_asset(attrs) do
      {:ok, asset} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Asset registered."))
         |> assign_new_form()
         |> push_event("close-modal", %{id: "new-asset-modal"})
         |> push_navigate(to: ~p"/hardware/#{asset.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :asset_form, to_form(changeset, as: :asset))}
    end
  end

  def handle_event("close_new_asset_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_form()
     |> push_event("close-modal", %{id: "new-asset-modal"})}
  end

  def handle_event("new_asset_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_new_form(socket)}
  end

  def handle_event("new_asset_modal_open_changed", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div id="hardware">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Hardware")}</h1>
          <p data-part="description">
            {gettext("Devices, servers, network gear, and laptops that Tuist owns.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.modal
            id="new-asset-modal"
            title={gettext("Register asset")}
            description={gettext("Add a laptop, server, or other hardware to the inventory.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_asset_modal"
            on_open_change="new_asset_modal_open_changed"
            data-part="new-asset-modal"
          >
            <:header_icon><.server /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-asset-button"
                label={gettext("Register asset")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="new-asset-modal-content">
              <.form
                id="new-asset-form"
                for={@asset_form}
                phx-change="validate_new_asset"
                phx-submit="create_asset"
              >
                <div data-part="new-asset-form-grid">
                  <.text_input
                    id="new-asset-name"
                    field={@asset_form[:name]}
                    type="basic"
                    label={gettext("Name")}
                    required
                    show_required
                    show_suffix={false}
                  />

                  <div data-part="labeled-select">
                    <.label label={gettext("Category")} required />
                    <.select
                      id="new-asset-category"
                      field={@asset_form[:category]}
                      label={gettext("Select a category")}
                    >
                      <:item
                        :for={category <- Asset.categories()}
                        value={category}
                        label={humanize(category)}
                      />
                    </.select>
                  </div>

                  <.text_input
                    id="new-asset-manufacturer"
                    field={@asset_form[:manufacturer]}
                    type="basic"
                    label={gettext("Manufacturer")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-model"
                    field={@asset_form[:model]}
                    type="basic"
                    label={gettext("Model")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-serial-number"
                    field={@asset_form[:serial_number]}
                    type="basic"
                    label={gettext("Serial number")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-asset-tag"
                    field={@asset_form[:asset_tag]}
                    type="basic"
                    label={gettext("Asset tag")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-purchased-on"
                    field={@asset_form[:purchased_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Purchased on")}
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-warranty-end"
                    field={@asset_form[:warranty_end_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Warranty end")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-acquisition-cost"
                    field={@asset_form[:acquisition_cost]}
                    type="basic"
                    label={gettext("Acquisition cost")}
                    placeholder="0.00"
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-acquisition-currency"
                    field={@asset_form[:acquisition_currency]}
                    type="basic"
                    label={gettext("Currency (ISO 4217)")}
                    placeholder="EUR"
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-useful-life"
                    field={@asset_form[:useful_life_months]}
                    type="basic"
                    input_type="number"
                    label={gettext("Useful life (months)")}
                    min="1"
                    show_suffix={false}
                  />

                  <div data-part="labeled-select">
                    <.label label={gettext("Location")} />
                    <.select
                      id="new-asset-location"
                      field={@asset_form[:location]}
                      label={gettext("Select a location")}
                    >
                      <:item
                        :for={location <- Asset.locations()}
                        value={location}
                        label={humanize(location)}
                      />
                    </.select>
                  </div>

                  <.text_input
                    id="new-asset-location-detail"
                    field={@asset_form[:location_detail]}
                    type="basic"
                    label={gettext("Location detail")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-asset-vendor"
                    field={@asset_form[:vendor]}
                    type="basic"
                    label={gettext("Vendor")}
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
                    phx-click="close_new_asset_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-asset-submit"
                    label={gettext("Register asset")}
                    size="small"
                    type="submit"
                    form="new-asset-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Assets")} icon="server" data-part="assets-card">
        <.card_section data-part="assets-section">
          <div data-part="filters">
            <.filter_dropdown
              id="hardware-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="hardware-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="hardware-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search name, serial, tag, manufacturer...")}
                  aria-label={gettext("Search hardware")}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} id="hardware-active-filters" data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <.table
            id="hardware-table"
            rows={@assets}
            row_key={fn asset -> "hardware-row-#{asset.id}" end}
            row_navigate={fn asset -> ~p"/hardware/#{asset.id}" end}
          >
            <:col
              :let={asset}
              label={gettext("Asset")}
              patch={column_patch_sort(assigns, "name")}
              sort_order={column_sort_order(assigns, "name")}
            >
              <.text_and_description_cell
                label={asset.name}
                description={asset_description(asset)}
              />
            </:col>
            <:col
              :let={asset}
              label={gettext("Category")}
              patch={column_patch_sort(assigns, "category")}
              sort_order={column_sort_order(assigns, "category")}
            >
              <.badge_cell label={humanize(asset.category)} color="neutral" style="light-fill" />
            </:col>
            <:col
              :let={asset}
              label={gettext("State")}
              patch={column_patch_sort(assigns, "state")}
              sort_order={column_sort_order(assigns, "state")}
            >
              <.badge_cell
                label={humanize(asset.state)}
                color={state_color(asset.state)}
                style="light-fill"
              />
            </:col>
            <:col
              :let={asset}
              label={gettext("Location")}
              patch={column_patch_sort(assigns, "location")}
              sort_order={column_sort_order(assigns, "location")}
            >
              <.text_cell label={location_label(asset)} />
            </:col>
            <:col :let={asset} label={gettext("Holder")}>
              <.text_cell label={holder_label(asset)} />
            </:col>
            <:col
              :let={asset}
              label={gettext("Acquisition")}
              patch={column_patch_sort(assigns, "acquisition_cost")}
              sort_order={column_sort_order(assigns, "acquisition_cost")}
            >
              <.text_cell label={amount(asset.acquisition_cost, asset.acquisition_currency)} />
            </:col>
            <:col
              :let={asset}
              label={gettext("Warranty")}
              patch={column_patch_sort(assigns, "warranty_end_on")}
              sort_order={column_sort_order(assigns, "warranty_end_on")}
            >
              <.text_cell label={date_or_dash(asset.warranty_end_on)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={empty_title(@query, @active_filters)}
                subtitle={empty_subtitle(@query, @active_filters)}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp assign_new_form(socket) do
    defaults = %{
      "category" => "laptop",
      "location" => "office",
      "acquisition_currency" => "EUR"
    }

    form =
      defaults
      |> Assets.change_asset()
      |> to_form(as: :asset)

    assign(socket, :asset_form, form)
  end

  defp load_assets(socket) do
    params =
      %{
        page: 1,
        page_size: @page_size,
        filters: filters_to_flop(socket.assigns.active_filters)
      }
      |> Map.merge(sort_flop_params(socket.assigns.sort_by, socket.assigns.sort_order))

    {assets, _meta} = Assets.list_assets(params, query: socket.assigns.query)
    assign(socket, :assets, assets)
  end

  defp sort_flop_params(sort_by, sort_order) when is_binary(sort_by) do
    %{
      order_by: [String.to_existing_atom(sort_by)],
      order_directions: [sort_direction(sort_order)]
    }
  end

  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc

  defp normalize_sort_by(value) when value in @sortable_fields, do: value
  defp normalize_sort_by(_), do: "name"

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order("desc"), do: "desc"
  defp normalize_sort_order(_), do: "asc"

  @doc false
  def column_patch_sort(%{uri: uri, sort_by: current_sort_by, sort_order: current_sort_order}, column) do
    next_order =
      case {current_sort_by == column, current_sort_order} do
        {true, "asc"} -> "desc"
        {true, _other} -> "asc"
        {false, _other} -> "asc"
      end

    query_params =
      uri.query
      |> Kernel.||("")
      |> URI.decode_query()
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)

    "?" <> URI.encode_query(query_params)
  end

  @doc false
  def column_sort_order(%{sort_by: column, sort_order: sort_order}, column), do: sort_order
  def column_sort_order(_assigns, _column), do: false

  defp filters_to_flop(active_filters) do
    Enum.map(active_filters, fn %Filter.Filter{id: id, operator: op, value: value} ->
      %{field: String.to_existing_atom(id), op: op, value: value}
    end)
  end

  defp define_filters do
    [
      option_filter("category", gettext("Category"), Asset.categories(), &humanize/1),
      option_filter("state", gettext("State"), Asset.states(), &humanize/1),
      option_filter("location", gettext("Location"), Asset.locations(), &humanize/1)
    ]
  end

  defp option_filter(id, display_name, options, formatter) do
    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      value: nil
    }
  end

  defp current_params(socket) do
    socket.assigns.uri.query |> Kernel.||("") |> URI.decode_query()
  end

  defp asset_description(%Asset{} = a) do
    [a.manufacturer, a.model, a.serial_number]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      description -> description
    end
  end

  defp state_color("in_service"), do: "success"
  defp state_color("in_storage"), do: "neutral"
  defp state_color("in_repair"), do: "attention"
  defp state_color("lost"), do: "destructive"
  defp state_color("retired"), do: "neutral"
  defp state_color("disposed"), do: "neutral"
  defp state_color(_other), do: "neutral"

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp location_label(%Asset{location: location, location_detail: nil}), do: humanize(location)
  defp location_label(%Asset{location: location, location_detail: ""}), do: humanize(location)
  defp location_label(%Asset{location: location, location_detail: detail}), do: "#{humanize(location)} · #{detail}"

  defp holder_label(%Asset{assigned_to: %Ecto.Association.NotLoaded{}}), do: "-"
  defp holder_label(%Asset{assigned_to: nil}), do: "-"
  defp holder_label(%Asset{assigned_to: %{name: name, email: email}}) when is_binary(name), do: "#{name} <#{email}>"
  defp holder_label(%Asset{assigned_to: %{email: email}}), do: email

  defp amount(%Decimal{} = value, currency) when is_binary(currency) do
    "#{currency} #{Decimal.to_string(value, :normal)}"
  end

  defp amount(_value, _currency), do: "-"

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp empty_title("", []), do: gettext("No assets yet")
  defp empty_title(_query, _filters), do: gettext("No matches")

  defp empty_subtitle("", []), do: gettext("Register a device to start tracking hardware.")
  defp empty_subtitle(_query, _filters), do: gettext("Adjust the filters or search terms.")
end
