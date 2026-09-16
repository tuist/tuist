defmodule AtlasWeb.DataCenterShowLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias Atlas.Assets.DataCenter

  def mount(%{"id" => id}, _session, socket) do
    case Assets.get_data_center(id) do
      %DataCenter{} = dc ->
        assets = Assets.list_assets_in_data_center(dc)

        {:ok,
         socket
         |> assign(:page_title, dc.name)
         |> assign(:data_center, dc)
         |> assign(:assets, assets)
         |> assign_edit_form(dc)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Data center not found."))
         |> push_navigate(to: ~p"/hardware/data-centers")}
    end
  end

  def handle_event("validate_edit_data_center", %{"data_center" => attrs}, socket) do
    form =
      socket.assigns.data_center
      |> Assets.change_data_center(attrs)
      |> Map.put(:action, :validate)
      |> to_form(as: :data_center)

    {:noreply, assign(socket, :edit_form, form)}
  end

  def handle_event("save_edit_data_center", %{"data_center" => attrs}, socket) do
    case Assets.edit_data_center(socket.assigns.data_center, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Data center updated."))
         |> assign(:data_center, updated)
         |> assign_edit_form(updated)
         |> push_event("close-modal", %{id: "edit-data-center-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :data_center))}
    end
  end

  def handle_event("close_edit_data_center_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_edit_form(socket.assigns.data_center)
     |> push_event("close-modal", %{id: "edit-data-center-modal"})}
  end

  def handle_event("edit_data_center_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_edit_form(socket, socket.assigns.data_center)}
  end

  def handle_event("edit_data_center_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_edit_form(socket, %DataCenter{} = dc) do
    form =
      dc
      |> Assets.change_data_center(%{})
      |> to_form(as: :data_center)

    assign(socket, :edit_form, form)
  end

  def render(assigns) do
    ~H"""
    <div id="data-center-show">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="data-center-breadcrumb-list"
              label={gettext("Data centers")}
              phx-click={JS.navigate(~p"/hardware/data-centers")}
            />
            <.breadcrumb id="data-center-breadcrumb-current" label={@data_center.name} />
          </.breadcrumbs>
          <h1 data-part="title">{@data_center.name}</h1>
          <p data-part="description">{header_description(@data_center)}</p>
          <div data-part="summary">
            <.badge
              label={humanize(@data_center.status)}
              color={status_color(@data_center.status)}
              style="light-fill"
            />
          </div>
        </div>
        <div data-part="header-actions">
          <.modal
            id="edit-data-center-modal"
            title={gettext("Edit data center")}
            description={gettext("Update the facility's metadata.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_edit_data_center_modal"
            on_open_change="edit_data_center_modal_open_changed"
            data-part="edit-data-center-modal"
          >
            <:header_icon><.server /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="edit-data-center-button"
                label={gettext("Edit")}
                size="medium"
                type="button"
                variant="secondary"
                {modal_attrs}
              />
            </:trigger>

            <div data-part="edit-data-center-modal-content">
              <.form
                id="edit-data-center-form"
                for={@edit_form}
                phx-change="validate_edit_data_center"
                phx-submit="save_edit_data_center"
              >
                <div data-part="edit-data-center-form-grid">
                  <.text_input
                    id="edit-data-center-name"
                    field={@edit_form[:name]}
                    type="basic"
                    label={gettext("Name")}
                    required
                    show_required
                    show_suffix={false}
                  />
                  <.text_input
                    id="edit-data-center-provider"
                    field={@edit_form[:provider]}
                    type="basic"
                    label={gettext("Provider")}
                    show_suffix={false}
                  />
                  <.text_input
                    id="edit-data-center-city"
                    field={@edit_form[:city]}
                    type="basic"
                    label={gettext("City")}
                    show_suffix={false}
                  />
                  <.text_input
                    id="edit-data-center-country"
                    field={@edit_form[:country]}
                    type="basic"
                    label={gettext("Country")}
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
                    phx-click="close_edit_data_center_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="edit-data-center-submit"
                    label={gettext("Save")}
                    size="small"
                    type="submit"
                    form="edit-data-center-form"
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
              <dt>{gettext("Provider")}</dt>
              <dd>{dash(@data_center.provider)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("City")}</dt>
              <dd>{dash(@data_center.city)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Country")}</dt>
              <dd>{dash(@data_center.country)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Assets hosted")}</dt>
              <dd>{length(@assets)}</dd>
            </div>
          </dl>
          <p :if={@data_center.notes} data-part="notes">{@data_center.notes}</p>
        </.card_section>
      </.card>

      <.card title={gettext("Assets")} icon="server" data-part="assets-card">
        <.card_section>
          <.table
            id="data-center-assets-table"
            rows={@assets}
            row_key={fn asset -> "data-center-asset-#{asset.id}" end}
            row_navigate={fn asset -> ~p"/hardware/#{asset.id}" end}
          >
            <:col :let={asset} label={gettext("Asset")}>
              <.text_and_description_cell label={asset.name} description={asset_description(asset)} />
            </:col>
            <:col :let={asset} label={gettext("Category")}>
              <.badge_cell label={humanize(asset.category)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={asset} label={gettext("State")}>
              <.badge_cell
                label={humanize(asset.state)}
                color={asset_state_color(asset.state)}
                style="light-fill"
              />
            </:col>
            <:col :let={asset} label={gettext("Rack / detail")}>
              <.text_cell label={dash(asset.location_detail)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No assets installed")}
                subtitle={gettext("Install a server or switch here to see it listed.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp header_description(%DataCenter{provider: nil, city: nil, country: nil}), do: gettext("Facility")

  defp header_description(%DataCenter{} = dc) do
    [dc.provider, [dc.city, dc.country] |> Enum.reject(&is_nil/1) |> Enum.join(", ")]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> gettext("Facility")
      value -> value
    end
  end

  defp asset_description(%Asset{} = a) do
    [a.manufacturer, a.model, a.serial_number]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp dash(nil), do: "-"
  defp dash(""), do: "-"
  defp dash(value), do: value

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_color("active"), do: "success"
  defp status_color("decommissioned"), do: "neutral"
  defp status_color(_), do: "neutral"

  defp asset_state_color("in_service"), do: "success"
  defp asset_state_color("in_storage"), do: "neutral"
  defp asset_state_color("in_repair"), do: "attention"
  defp asset_state_color("lost"), do: "destructive"
  defp asset_state_color(_other), do: "neutral"
end
