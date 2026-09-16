defmodule AtlasWeb.DataCentersLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Assets
  alias Atlas.Assets.DataCenter

  @page_size 50
  @sortable_fields ~w(name provider city country status)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Data centers"))
     |> assign(:sort_by, "name")
     |> assign(:sort_order, "asc")
     |> assign(:uri, URI.new!("?"))
     |> assign(:data_centers, [])
     |> assign_new_form()}
  end

  def handle_params(params, _uri, socket) do
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    {rows, _meta} =
      Assets.list_data_centers(Map.merge(%{page: 1, page_size: @page_size}, sort_flop_params(sort_by, sort_order)))

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:data_centers, rows)}
  end

  def handle_event("validate_new_data_center", %{"data_center" => attrs}, socket) do
    form =
      attrs
      |> Assets.change_data_center()
      |> Map.put(:action, :validate)
      |> to_form(as: :data_center)

    {:noreply, assign(socket, :data_center_form, form)}
  end

  def handle_event("create_data_center", %{"data_center" => attrs}, socket) do
    case Assets.create_data_center(attrs) do
      {:ok, dc} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Data center registered."))
         |> assign_new_form()
         |> push_event("close-modal", %{id: "new-data-center-modal"})
         |> push_navigate(to: ~p"/hardware/data-centers/#{dc.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :data_center_form, to_form(changeset, as: :data_center))}
    end
  end

  def handle_event("close_new_data_center_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_form()
     |> push_event("close-modal", %{id: "new-data-center-modal"})}
  end

  def handle_event("new_data_center_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_new_form(socket)}
  end

  def handle_event("new_data_center_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_new_form(socket) do
    form =
      %{}
      |> Assets.change_data_center()
      |> to_form(as: :data_center)

    assign(socket, :data_center_form, form)
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

  def column_sort_order(%{sort_by: column, sort_order: sort_order}, column), do: sort_order
  def column_sort_order(_assigns, _column), do: false

  def render(assigns) do
    ~H"""
    <div id="data-centers">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Data centers")}</h1>
          <p data-part="description">
            {gettext("Colocation and private data centers hosting Tuist hardware.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.modal
            id="new-data-center-modal"
            title={gettext("Register data center")}
            description={gettext("Add a colocation or private facility.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_data_center_modal"
            on_open_change="new_data_center_modal_open_changed"
            data-part="new-data-center-modal"
          >
            <:header_icon><.server /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-data-center-button"
                label={gettext("Register data center")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="new-data-center-modal-content">
              <.form
                id="new-data-center-form"
                for={@data_center_form}
                phx-change="validate_new_data_center"
                phx-submit="create_data_center"
              >
                <div data-part="new-data-center-form-grid">
                  <.text_input
                    id="new-data-center-name"
                    field={@data_center_form[:name]}
                    type="basic"
                    label={gettext("Name")}
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-data-center-provider"
                    field={@data_center_form[:provider]}
                    type="basic"
                    label={gettext("Provider")}
                    placeholder="TARGO, Hetzner, ..."
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-data-center-city"
                    field={@data_center_form[:city]}
                    type="basic"
                    label={gettext("City")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-data-center-country"
                    field={@data_center_form[:country]}
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
                    phx-click="close_new_data_center_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-data-center-submit"
                    label={gettext("Register data center")}
                    size="small"
                    type="submit"
                    form="new-data-center-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Facilities")} icon="server" data-part="data-centers-card">
        <.card_section>
          <.table
            id="data-centers-table"
            rows={@data_centers}
            row_key={fn dc -> "data-center-row-#{dc.id}" end}
            row_navigate={fn dc -> ~p"/hardware/data-centers/#{dc.id}" end}
          >
            <:col
              :let={dc}
              label={gettext("Name")}
              patch={column_patch_sort(assigns, "name")}
              sort_order={column_sort_order(assigns, "name")}
            >
              <.text_and_description_cell label={dc.name} description={description(dc)} />
            </:col>
            <:col
              :let={dc}
              label={gettext("Provider")}
              patch={column_patch_sort(assigns, "provider")}
              sort_order={column_sort_order(assigns, "provider")}
            >
              <.text_cell label={dash(dc.provider)} />
            </:col>
            <:col
              :let={dc}
              label={gettext("City")}
              patch={column_patch_sort(assigns, "city")}
              sort_order={column_sort_order(assigns, "city")}
            >
              <.text_cell label={dash(dc.city)} />
            </:col>
            <:col
              :let={dc}
              label={gettext("Country")}
              patch={column_patch_sort(assigns, "country")}
              sort_order={column_sort_order(assigns, "country")}
            >
              <.text_cell label={dash(dc.country)} />
            </:col>
            <:col
              :let={dc}
              label={gettext("Status")}
              patch={column_patch_sort(assigns, "status")}
              sort_order={column_sort_order(assigns, "status")}
            >
              <.badge_cell
                label={humanize(dc.status)}
                color={status_color(dc.status)}
                style="light-fill"
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No data centers yet")}
                subtitle={gettext("Register the first colocation or private facility.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp description(%DataCenter{provider: nil, city: nil, country: nil}), do: nil

  defp description(%DataCenter{} = dc) do
    [dc.provider, [dc.city, dc.country] |> Enum.reject(&is_nil/1) |> Enum.join(", ")]
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
end
