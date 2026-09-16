defmodule AtlasWeb.HardwareShowLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias Atlas.Finance.Financings

  def mount(%{"id" => id}, _session, socket) do
    case Assets.get_asset(id) do
      %Asset{} = asset ->
        {assignments, _} = Assets.list_assignments(asset)
        {events, _} = Assets.list_events(asset)
        financings = Financings.list_asset_financings(asset.id)
        book_value = Assets.book_value_at(asset, on: Date.utc_today())

        {:ok,
         socket
         |> assign(:page_title, asset.name)
         |> assign(:asset, asset)
         |> assign(:assignments, assignments)
         |> assign(:events, events)
         |> assign(:financings, financings)
         |> assign(:book_value, book_value)
         |> assign_edit_form(asset)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Asset not found."))
         |> push_navigate(to: ~p"/hardware")}
    end
  end

  def handle_event("validate_edit_asset", %{"asset" => attrs}, socket) do
    form =
      socket.assigns.asset
      |> Assets.change_asset(attrs)
      |> Map.put(:action, :validate)
      |> to_form(as: :asset)

    {:noreply, assign(socket, :edit_form, form)}
  end

  def handle_event("save_edit_asset", %{"asset" => attrs}, socket) do
    case Assets.edit_metadata(socket.assigns.asset, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Asset updated."))
         |> assign(:asset, updated)
         |> assign_edit_form(updated)
         |> push_event("close-modal", %{id: "edit-asset-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :asset))}
    end
  end

  def handle_event("close_edit_asset_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_edit_form(socket.assigns.asset)
     |> push_event("close-modal", %{id: "edit-asset-modal"})}
  end

  def handle_event("edit_asset_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_edit_form(socket, socket.assigns.asset)}
  end

  def handle_event("edit_asset_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_edit_form(socket, %Asset{} = asset) do
    form =
      asset
      |> Assets.change_asset(%{})
      |> to_form(as: :asset)

    assign(socket, :edit_form, form)
  end

  def render(assigns) do
    ~H"""
    <div id="hardware-show">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="hardware-breadcrumb-list"
              label={gettext("Hardware")}
              phx-click={JS.navigate(~p"/hardware")}
            />
            <.breadcrumb id="hardware-breadcrumb-current" label={@asset.name} />
          </.breadcrumbs>
          <h1 data-part="title">{@asset.name}</h1>
          <p data-part="description">{subtitle(@asset)}</p>
          <div data-part="summary">
            <.badge
              label={humanize(@asset.state)}
              color={state_color(@asset.state)}
              style="light-fill"
            />
            <.badge label={humanize(@asset.category)} color="neutral" style="light-fill" />
            <.badge label={humanize(@asset.ownership)} color="neutral" style="light-fill" />
          </div>
        </div>
        <div data-part="header-actions">
          <.modal
            id="edit-asset-modal"
            title={gettext("Edit asset")}
            description={gettext("Update non-lifecycle metadata. Lifecycle actions live elsewhere.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_edit_asset_modal"
            on_open_change="edit_asset_modal_open_changed"
            data-part="edit-asset-modal"
          >
            <:header_icon><.server /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="edit-asset-button"
                label={gettext("Edit")}
                variant="secondary"
                size="medium"
                type="button"
                {modal_attrs}
              />
            </:trigger>

            <div data-part="edit-asset-modal-content">
              <.form
                id="edit-asset-form"
                for={@edit_form}
                phx-change="validate_edit_asset"
                phx-submit="save_edit_asset"
              >
                <div data-part="edit-asset-form-grid">
                  <.text_input
                    id="edit-asset-name"
                    field={@edit_form[:name]}
                    type="basic"
                    label={gettext("Name")}
                    show_suffix={false}
                  />

                  <div data-part="labeled-select">
                    <.label label={gettext("Category")} />
                    <.select
                      id="edit-asset-category"
                      field={@edit_form[:category]}
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
                    id="edit-asset-manufacturer"
                    field={@edit_form[:manufacturer]}
                    type="basic"
                    label={gettext("Manufacturer")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="edit-asset-model"
                    field={@edit_form[:model]}
                    type="basic"
                    label={gettext("Model")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="edit-asset-serial-number"
                    field={@edit_form[:serial_number]}
                    type="basic"
                    label={gettext("Serial number")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="edit-asset-asset-tag"
                    field={@edit_form[:asset_tag]}
                    type="basic"
                    label={gettext("Asset tag")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="edit-asset-warranty-end"
                    field={@edit_form[:warranty_end_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Warranty end")}
                    show_suffix={false}
                  />

                  <div data-part="labeled-select">
                    <.label label={gettext("Location")} />
                    <.select
                      id="edit-asset-location"
                      field={@edit_form[:location]}
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
                    id="edit-asset-location-detail"
                    field={@edit_form[:location_detail]}
                    type="basic"
                    label={gettext("Location detail")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="edit-asset-vendor"
                    field={@edit_form[:vendor]}
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
                    phx-click="close_edit_asset_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="edit-asset-submit"
                    label={gettext("Save changes")}
                    size="small"
                    type="submit"
                    form="edit-asset-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Details")} icon="file" data-part="details-card">
        <.card_section>
          <dl data-part="details">
            <div data-part="detail">
              <dt>{gettext("Location")}</dt>
              <dd>{location_label(@asset)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Manufacturer")}</dt>
              <dd>{value_or_dash(@asset.manufacturer)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Model")}</dt>
              <dd>{value_or_dash(@asset.model)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Serial")}</dt>
              <dd>{value_or_dash(@asset.serial_number)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Tag")}</dt>
              <dd>{value_or_dash(@asset.asset_tag)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Vendor")}</dt>
              <dd>{value_or_dash(@asset.vendor)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Purchased on")}</dt>
              <dd>{date_or_dash(@asset.purchased_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Placed in service")}</dt>
              <dd>{date_or_dash(@asset.placed_in_service_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Acquisition cost")}</dt>
              <dd>{amount(@asset.acquisition_cost, @asset.acquisition_currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Estimated book value")}</dt>
              <dd>{book_value_label(@book_value)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Warranty")}</dt>
              <dd>{date_or_dash(@asset.warranty_end_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Holder")}</dt>
              <dd>{holder_label(@asset)}</dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.card title={gettext("Financing")} icon="file" data-part="financings-card">
        <.card_section>
          <.table
            id="hardware-financings-table"
            rows={@financings}
            row_key={fn line -> "hardware-financing-#{line.id}" end}
            row_navigate={fn line -> ~p"/hardware/financings/#{line.financing_id}" end}
          >
            <:col :let={line} label={gettext("Provider")}>
              <.text_and_description_cell
                label={line.financing.provider}
                description={line.financing.reference}
              />
            </:col>
            <:col :let={line} label={gettext("Supplier")}>
              <.text_cell label={value_or_dash(line.financing.supplier)} />
            </:col>
            <:col :let={line} label={gettext("Type")}>
              <.badge_cell label={humanize(line.financing.type)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={line} label={gettext("Share")}>
              <.text_cell label={share_label(line.share_bps)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No financing linked")}
                subtitle={gettext("Financing arrangements connected to this asset appear here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Custody history")} icon="user" data-part="assignments-card">
        <.card_section>
          <.table
            id="hardware-assignments-table"
            rows={@assignments}
            row_key={fn a -> "hardware-assignment-#{a.id}" end}
          >
            <:col :let={a} label={gettext("Holder")}>
              <.text_cell label={a.user_label_snapshot} />
            </:col>
            <:col :let={a} label={gettext("Assigned")}>
              <.text_cell label={format_date(a.assigned_on)} />
            </:col>
            <:col :let={a} label={gettext("Returned")}>
              <.text_cell label={date_or_dash(a.returned_on)} />
            </:col>
            <:col :let={a} label={gettext("Notes")}>
              <.text_cell label={value_or_dash(a.notes)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No assignments yet")}
                subtitle={
                  gettext("Custody intervals appear here after the asset is assigned to a person.")
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Events")} icon="file_text" data-part="events-card">
        <.card_section>
          <.table
            id="hardware-events-table"
            rows={@events}
            row_key={fn e -> "hardware-event-#{e.id}" end}
          >
            <:col :let={e} label={gettext("Type")}>
              <.badge_cell
                label={humanize(e.event_type)}
                color={event_color(e.event_type)}
                style="light-fill"
              />
            </:col>
            <:col :let={e} label={gettext("Occurred")}>
              <.text_cell label={format_date(e.occurred_on)} />
            </:col>
            <:col :let={e} label={gettext("Expenditure")}>
              <.text_cell label={amount(e.expenditure, e.expenditure_currency)} />
            </:col>
            <:col :let={e} label={gettext("Notes")}>
              <.text_cell label={value_or_dash(e.notes)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No events yet")}
                subtitle={gettext("Repairs, incidents, and warranty extensions appear here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp subtitle(%Asset{} = a) do
    [a.manufacturer, a.model]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> gettext("Hardware asset")
      description -> description
    end
  end

  defp value_or_dash(nil), do: "-"
  defp value_or_dash(""), do: "-"
  defp value_or_dash(value), do: to_string(value)

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = d), do: format_date(d)

  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp state_color("in_service"), do: "success"
  defp state_color("in_storage"), do: "neutral"
  defp state_color("in_repair"), do: "attention"
  defp state_color("lost"), do: "destructive"
  defp state_color("retired"), do: "neutral"
  defp state_color("disposed"), do: "neutral"
  defp state_color(_other), do: "neutral"

  defp event_color("repaired"), do: "information"
  defp event_color("warranty_extended"), do: "success"
  defp event_color("incident"), do: "destructive"
  defp event_color(_other), do: "neutral"

  defp location_label(%Asset{location: location, location_detail: nil}), do: humanize(location)
  defp location_label(%Asset{location: location, location_detail: ""}), do: humanize(location)
  defp location_label(%Asset{location: location, location_detail: detail}), do: "#{humanize(location)} · #{detail}"

  defp amount(%Decimal{} = value, currency) when is_binary(currency) do
    "#{currency} #{Decimal.to_string(value, :normal)}"
  end

  defp amount(_value, _currency), do: "-"

  defp share_label(basis_points) do
    percent = div(basis_points, 100)
    remainder = rem(basis_points, 100)
    "#{percent}.#{String.pad_leading(Integer.to_string(remainder), 2, "0")}%"
  end

  defp holder_label(%Asset{assigned_to: %Ecto.Association.NotLoaded{}}), do: "-"
  defp holder_label(%Asset{assigned_to: nil}), do: "-"
  defp holder_label(%Asset{assigned_to: %{name: name, email: email}}) when is_binary(name), do: "#{name} <#{email}>"
  defp holder_label(%Asset{assigned_to: %{email: email}}), do: email

  defp book_value_label({:ok, value, currency}), do: "#{currency} #{Decimal.to_string(value, :normal)}"
  defp book_value_label({:error, :missing_valuation}), do: gettext("Unknown")
  defp book_value_label({:error, reason}), do: to_string(reason)
end
