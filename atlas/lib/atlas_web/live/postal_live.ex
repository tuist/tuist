defmodule AtlasWeb.PostalLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.CheckboxControl, only: [checkbox_control: 1]
  import Noora.Filter

  alias Atlas.Letters
  alias Atlas.Letters.Letter
  alias AtlasWeb.Utilities.Query, as: WebQuery
  alias Noora.Filter

  @page_size 100
  @sortable_fields ~w(inserted_at sent_at delivered_at)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Postal"))
     |> assign(:postal_delivery_configured?, Letters.configured?())
     |> assign(:available_filters, [])
     |> assign(:active_letter, nil)
     |> assign(:letter_action, nil)
     |> allow_upload(:postal_letter,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 50_000_000,
       auto_upload: true
     )}
  end

  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    uri = URI.new!("?" <> URI.encode_query(params))
    available_filters = define_filters()
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> load_letters()}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         postal_path(
           query,
           socket.assigns.active_filters,
           socket.assigns.sort_by,
           socket.assigns.sort_order
         ),
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/outbound/postal?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/outbound/postal?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("open_letter_action", %{"id" => id, "data" => action}, socket) do
    case {Letters.get_letter(id), action} do
      {%Letter{status: "awaiting_delivery_confirmation"} = letter, "confirm_delivery"} ->
        {:noreply,
         socket
         |> assign(:active_letter, letter)
         |> assign(:letter_action, :confirm_delivery)
         |> push_event("open-modal", %{id: "postal-letter-action-modal"})}

      _other ->
        {:noreply, put_flash(socket, :error, gettext("This action is no longer available."))}
    end
  end

  def handle_event("close_letter_action_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_letter, nil)
     |> assign(:letter_action, nil)
     |> push_event("close-modal", %{id: "postal-letter-action-modal"})}
  end

  def handle_event("confirm_letter_delivery", %{"letter_delivery" => params}, socket) do
    case Letters.confirm_delivery(params["letter_id"], params, socket.assigns.current_user) do
      {:ok, _letter} ->
        {:noreply,
         socket
         |> load_letters()
         |> clear_letter_action()
         |> push_event("close-modal", %{id: "postal-letter-action-modal"})
         |> put_flash(:info, gettext("Letter queued for postal delivery."))}

      {:error, :confirmation_required} ->
        {:noreply, put_flash(socket, :error, gettext("Confirm the postal delivery before sending it."))}

      {:error, :postal_delivery_not_configured} ->
        {:noreply, put_flash(socket, :error, gettext("Postal delivery is not configured."))}

      {:error, :letter_not_ready_to_send} ->
        {:noreply, put_flash(socket, :error, gettext("This letter is not ready to send."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not queue this postal letter."))}
    end
  end

  def handle_event("check_letter_delivery", %{"id" => id}, socket) do
    case Letters.check_delivery(id, socket.assigns.current_user) do
      {:ok, _letter} ->
        {:noreply, load_letters(socket)}

      {:error, :letter_not_submitted} ->
        {:noreply, put_flash(socket, :info, gettext("This letter is waiting to be submitted."))}

      {:error, :postal_delivery_not_configured} ->
        {:noreply, put_flash(socket, :error, gettext("Postal delivery is not configured."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not check this letter's delivery status."))}
    end
  end

  # LiveView's live_file_input needs a phx-change on the enclosing form to
  # track selected entries and advance auto_upload to handle_progress. Entry
  # validation (accept, max size) is declared in allow_upload/3, so this
  # handler has nothing to do per change.
  def handle_event("validate_postal_letter_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("open_letter_document", %{"id" => id}, socket) do
    case Letters.get_letter(id) do
      %Letter{} = letter ->
        case letter_document(letter) do
          nil -> {:noreply, put_flash(socket, :error, gettext("This letter document is no longer available."))}
          document -> {:noreply, push_navigate(socket, to: ~p"/library/documents/#{document.id}")}
        end

      _letter ->
        {:noreply, put_flash(socket, :error, gettext("This letter document is no longer available."))}
    end
  end

  def handle_progress(:postal_letter, entry, socket) do
    if entry.done? do
      [result] =
        consume_uploaded_entries(socket, :postal_letter, fn %{path: path}, entry ->
          with {:ok, body} <- File.read(path),
               {:ok, letter} <-
                 Letters.upload_letter(
                   %{body: body, filename: entry.client_name},
                   socket.assigns.current_user
                 ) do
            {:ok, {:ok, letter}}
          else
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, _letter} ->
          {:noreply,
           socket
           |> load_letters()
           |> put_flash(
             :info,
             gettext("Letter uploaded. The delivery agent is matching it to an account and preparing its address.")
           )}

        {:error, :letter_document_must_be_a_pdf} ->
          {:noreply, put_flash(socket, :error, gettext("Upload a PDF letter."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not upload the letter."))}
      end
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="postal">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Postal")}</h1>
          <p data-part="description">
            {gettext("Send, track, and retain company correspondence.")}
          </p>
        </div>
        <div data-part="header-actions">
          <form
            id="postal-upload-letter-form"
            phx-change="validate_postal_letter_upload"
            phx-submit="validate_postal_letter_upload"
          >
            <label
              id="postal-upload-letter-button"
              class="noora-button"
              data-part="postal-letter-upload-button"
              data-variant="primary"
              data-size="medium"
            >
              <.live_file_input
                id="postal-letter-file-input"
                upload={@uploads.postal_letter}
                data-part="postal-letter-file-input"
              />
              <.file />
              <span>{gettext("Upload letter")}</span>
            </label>
          </form>
          <.button
            id="postal-open-documents-button"
            label={gettext("Open documents")}
            variant="secondary"
            size="medium"
            navigate={~p"/library/documents"}
          >
            <:icon_left><.file /></:icon_left>
          </.button>
        </div>
      </div>

      <.card title={gettext("Letters")} icon="mail" data-part="letters-card">
        <.card_section data-part="letters-table-section">
          <div data-part="filters">
            <.filter_dropdown
              id="postal-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="postal-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="postal-search-input"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search company, recipient, or subject")}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} id="postal-active-filters" data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <div data-part="letters-table">
            <.table id="postal-letters-table" rows={@letters}>
              <:col :let={letter} label={gettext("Letter")}>
                <.text_and_description_cell
                  label={letter.subject}
                  description={recipient_label(letter)}
                />
              </:col>
              <:col :let={letter} label={gettext("Company")}>
                <div data-part="account-cell">
                  <.link
                    :if={letter.account}
                    id={"postal-letter-account-#{letter.id}"}
                    data-part="account-link"
                    navigate={~p"/commercial/sales/accounts/#{letter.account.id}"}
                  >
                    {letter.account.name}
                  </.link>
                  <span :if={is_nil(letter.account)} data-part="muted">{"—"}</span>
                </div>
              </:col>
              <:col :let={letter} label={gettext("Status")}>
                <.badge_cell
                  label={status_label(letter.status)}
                  color={status_color(letter.status)}
                  style="light-fill"
                />
              </:col>
              <:col
                :let={letter}
                label={gettext("Created")}
                patch={column_patch_sort(assigns, "inserted_at")}
                sort_order={column_sort_order(assigns, "inserted_at")}
              >
                <.text_cell label={format_datetime(letter.inserted_at)} />
              </:col>
              <:col
                :let={letter}
                label={gettext("Sent")}
                patch={column_patch_sort(assigns, "sent_at")}
                sort_order={column_sort_order(assigns, "sent_at")}
              >
                <.text_cell label={format_datetime(letter.sent_at)} />
              </:col>
              <:col :let={letter} label="">
                <div data-part="letter-actions-cell">
                  <.button_dropdown
                    :if={letter_action_available?(letter)}
                    id={"postal-letter-actions-#{letter.id}"}
                    label={letter_document_label(letter)}
                    size="medium"
                    align="end"
                    phx-click="open_letter_document"
                    phx-value-id={letter.id}
                  >
                    <:icon_left><.file /></:icon_left>
                    <.dropdown_item
                      :if={letter.status == "awaiting_delivery_confirmation"}
                      value="confirm_delivery"
                      label={gettext("Send letter")}
                      on_click="open_letter_action"
                      phx-value-id={letter.id}
                    >
                      <:left_icon><.cube_send /></:left_icon>
                    </.dropdown_item>
                  </.button_dropdown>
                  <.button
                    :if={not letter_action_available?(letter)}
                    id={"postal-letter-document-#{letter.id}"}
                    label={letter_document_label(letter)}
                    variant="secondary"
                    size="medium"
                    navigate={~p"/library/documents/#{letter_document(letter).id}"}
                  >
                    <:icon_left><.file /></:icon_left>
                  </.button>
                </div>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="mail"
                  title={empty_title(@query)}
                  subtitle={empty_subtitle(@query)}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>

      <.modal
        id="postal-letter-action-modal"
        title={letter_action_title(@letter_action)}
        description={letter_action_description(@letter_action)}
        header_type="icon"
        header_size="small"
        on_dismiss="close_letter_action_modal"
        data-part="letter-action-modal"
      >
        <:header_icon><.file /></:header_icon>
        <:trigger :let={modal_attrs}>
          <button id="postal-letter-action-modal-trigger" type="button" hidden {modal_attrs}></button>
        </:trigger>

        <.form
          :if={@letter_action == :confirm_delivery and @active_letter}
          id="postal-letter-delivery-form"
          for={@letter_delivery_form}
          phx-submit="confirm_letter_delivery"
          data-part="modal-form"
        >
          <input type="hidden" name="letter_delivery[letter_id]" value={@active_letter.id} />
          <p data-part="modal-copy">
            {gettext("Review the prepared delivery details before sending this letter.")}
          </p>
          <div
            :if={@active_letter.delivery_details}
            id="postal-delivery-details"
            data-part="delivery-details"
          >
            <span data-part="delivery-details-label">{gettext("Recipient")}</span>
            <span data-part="delivery-details-address">
              {delivery_address(@active_letter.delivery_details, "recipient")}
            </span>
            <span data-part="delivery-details-label">{gettext("Delivery")}</span>
            <span data-part="delivery-details-address">
              {delivery_summary(@active_letter.delivery_details)}
            </span>
          </div>
          <div
            id="letter-delivery-confirmation"
            class="noora-checkbox"
            phx-hook="NooraCheckbox"
            data-part="delivery-confirmation"
          >
            <label data-part="root" for="confirm-letter-delivery">
              <input
                id="confirm-letter-delivery"
                type="checkbox"
                name={@letter_delivery_form[:confirmed].name}
                value="true"
                required
                data-part="hidden-input"
              />
              <.checkbox_control data-part="control" />
              <span data-part="label">{gettext("I approve this delivery")}</span>
            </label>
          </div>
        </.form>

        <:footer>
          <.modal_footer>
            <:action>
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="close_letter_action_modal"
              />
            </:action>
            <:action :if={@letter_action == :confirm_delivery}>
              <.button
                id="deliver-signed-letter"
                label={gettext("Send letter")}
                size="small"
                type="submit"
                form="postal-letter-delivery-form"
                disabled={not @postal_delivery_configured?}
              />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </div>
    """
  end

  defp load_letters(socket) do
    {letters, meta} =
      Letters.list_letters(
        page_size: @page_size,
        query: socket.assigns.query,
        status: active_filter_value(socket.assigns.active_filters, "status"),
        account_id: active_filter_value(socket.assigns.active_filters, "account_id"),
        sort_by: socket.assigns.sort_by,
        sort_order: socket.assigns.sort_order
      )

    socket
    |> assign(:letters, letters)
    |> assign(:letter_count, meta.total_count)
    |> assign(:letter_delivery_form, to_form(%{"confirmed" => false}, as: "letter_delivery"))
  end

  defp clear_letter_action(socket) do
    socket
    |> assign(:active_letter, nil)
    |> assign(:letter_action, nil)
  end

  defp active_filter_value(filters, id) do
    case Enum.find(filters, &(&1.id == id)) do
      %{operator: :==, value: value} -> WebQuery.present_string(value)
      _filter -> nil
    end
  end

  defp define_filters do
    [
      option_filter("status", gettext("Status"), Letter.statuses(), &status_label/1),
      account_filter()
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp account_filter do
    accounts = Letters.list_letter_accounts()

    %Filter.Filter{
      id: "account_id",
      field: :account_id,
      display_name: gettext("Company"),
      type: :option,
      searchable: true,
      options: Enum.map(accounts, & &1.id),
      options_display_names: Map.new(accounts, &{&1.id, &1.name}),
      operator: :==,
      value: nil
    }
  end

  defp option_filter(id, display_name, options, formatter) do
    options = options |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      searchable: true,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      value: nil
    }
  end

  defp column_patch_sort(%{uri: uri, sort_by: current_sort_by, sort_order: current_sort_order}, column) do
    next_order =
      case {current_sort_by == column, current_sort_order} do
        {true, "asc"} -> "desc"
        {true, _order} -> "asc"
        {false, _order} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)

    "?" <> URI.encode_query(query_params)
  end

  defp column_sort_order(%{sort_by: column, sort_order: sort_order}, column), do: sort_order
  defp column_sort_order(_assigns, _column), do: nil

  defp postal_path(query, active_filters, sort_by, sort_order) do
    params =
      %{}
      |> WebQuery.put_present("q", WebQuery.present_string(query))
      |> WebQuery.put_present("sort-by", sort_by)
      |> WebQuery.put_present("sort-order", if(sort_by, do: sort_order))
      |> Map.merge(Filter.Operations.encode_filters_to_query(active_filters))

    ~p"/outbound/postal?#{params}"
  end

  defp normalize_sort_by(value) when value in @sortable_fields, do: value
  defp normalize_sort_by(_value), do: nil

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order(_value), do: "desc"

  defp recipient_label(%{recipient_name: nil}), do: gettext("Delivery address is being prepared")

  defp recipient_label(letter) do
    "#{letter.recipient_name} · #{letter.recipient_postal_code} #{letter.recipient_city}"
  end

  defp status_label("awaiting_delivery_confirmation"), do: gettext("Ready to send")
  defp status_label(status) when status in ["sent", "delivered", "undeliverable"], do: gettext("Sent")
  defp status_label(_status), do: gettext("Processing")

  defp status_color("awaiting_delivery_confirmation"), do: "attention"
  defp status_color(status) when status in ["sent", "delivered", "undeliverable"], do: "success"
  defp status_color(_status), do: "neutral"

  defp empty_title(""), do: gettext("No letters")
  defp empty_title(_query), do: gettext("No matching letters")

  defp empty_subtitle(""), do: gettext("Upload a letter or prepare a tax certificate request from an account to begin.")
  defp empty_subtitle(_query), do: gettext("Try a different search or filter.")

  defp letter_action_title(:confirm_delivery), do: gettext("Send letter")
  defp letter_action_title(_action), do: gettext("Letter action")

  defp letter_action_description(:confirm_delivery), do: gettext("Delivery details are ready for your approval.")
  defp letter_action_description(_action), do: nil

  defp delivery_address(details, key) do
    case Map.get(details, key) do
      address when is_map(address) ->
        [
          address["name"],
          address["street"],
          [address["postal_code"], address["city"]] |> Enum.reject(&is_nil/1) |> Enum.join(" "),
          address["country"]
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(", ")

      _address ->
        gettext("Not available")
    end
  end

  defp delivery_summary(details) do
    [Map.get(details, "delivery_product"), Map.get(details, "print_mode"), Map.get(details, "print_spectrum")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join(" · ", &String.capitalize/1)
  end

  defp letter_document(letter), do: letter.signed_document || letter.document

  defp letter_document_label(_letter), do: gettext("Open document")

  defp letter_action_available?(%Letter{status: "awaiting_delivery_confirmation"}), do: true
  defp letter_action_available?(%Letter{}), do: false

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_datetime(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
end
