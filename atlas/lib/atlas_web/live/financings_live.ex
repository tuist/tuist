defmodule AtlasWeb.FinancingsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Finance.Financing
  alias Atlas.Finance.Financings

  @page_size 50
  @sortable_fields ~w(provider disbursement_or_commencement_on inserted_at)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Financings"))
     |> assign(:sort_by, "disbursement_or_commencement_on")
     |> assign(:sort_order, "desc")
     |> assign(:uri, URI.new!("?"))
     |> assign(:financings, [])
     |> assign_new_form()}
  end

  def handle_event("validate_new_financing", %{"financing" => attrs}, socket) do
    form =
      attrs
      |> Financings.change_financing()
      |> Map.put(:action, :validate)
      |> to_form(as: :financing)

    {:noreply, assign(socket, :financing_form, form)}
  end

  def handle_event("create_financing", %{"financing" => attrs}, socket) do
    case Financings.create(attrs) do
      {:ok, financing} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Financing arrangement registered."))
         |> assign_new_form()
         |> push_event("close-modal", %{id: "new-financing-modal"})
         |> push_navigate(to: ~p"/hardware/financings/#{financing.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :financing_form, to_form(changeset, as: :financing))}
    end
  end

  def handle_event("close_new_financing_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_form()
     |> push_event("close-modal", %{id: "new-financing-modal"})}
  end

  def handle_event("new_financing_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_new_form(socket)}
  end

  def handle_event("new_financing_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_new_form(socket) do
    defaults = %{
      "type" => "loan",
      "currency" => "EUR",
      "accounting_treatment" => "undetermined"
    }

    form =
      defaults
      |> Financings.change_financing()
      |> to_form(as: :financing)

    assign(socket, :financing_form, form)
  end

  def handle_params(params, _uri, socket) do
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    {financings, _meta} =
      Financings.list(
        Map.merge(
          %{page: 1, page_size: @page_size},
          sort_flop_params(sort_by, sort_order)
        )
      )

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:financings, financings)}
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
  defp normalize_sort_by(_), do: "disbursement_or_commencement_on"

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order("desc"), do: "desc"
  defp normalize_sort_order(_), do: "desc"

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
    <div id="financings">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Financings")}</h1>
          <p data-part="description">
            {gettext(
              "Loans and leases funding hardware. Each arrangement links to the assets it funds."
            )}
          </p>
        </div>
        <div data-part="header-actions">
          <.modal
            id="new-financing-modal"
            title={gettext("Register financing arrangement")}
            description={gettext("Record a new loan or lease funding hardware.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_financing_modal"
            on_open_change="new_financing_modal_open_changed"
            data-part="new-financing-modal"
          >
            <:header_icon><.credit_card /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-financing-button"
                label={gettext("Register financing")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="new-financing-modal-content">
              <.form
                id="new-financing-form"
                for={@financing_form}
                phx-change="validate_new_financing"
                phx-submit="create_financing"
              >
                <div data-part="new-financing-form-grid">
                  <div data-part="labeled-select">
                    <.label label={gettext("Type")} required />
                    <.select
                      id="new-financing-type"
                      field={@financing_form[:type]}
                      label={gettext("Select a type")}
                    >
                      <:item :for={type <- Financing.types()} value={type} label={humanize(type)} />
                    </.select>
                  </div>

                  <.text_input
                    id="new-financing-provider"
                    field={@financing_form[:provider]}
                    type="basic"
                    label={gettext("Provider")}
                    placeholder="LeasePlan, KfW, ..."
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-supplier"
                    field={@financing_form[:supplier]}
                    type="basic"
                    label={gettext("Supplier")}
                    placeholder="Apple, Dell, ..."
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-reference"
                    field={@financing_form[:reference]}
                    type="basic"
                    label={gettext("Reference")}
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-currency"
                    field={@financing_form[:currency]}
                    type="basic"
                    label={gettext("Currency (ISO 4217)")}
                    placeholder="EUR"
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-commencement"
                    field={@financing_form[:disbursement_or_commencement_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Commencement / disbursement")}
                    required
                    show_required
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-term"
                    field={@financing_form[:term_months]}
                    type="basic"
                    input_type="number"
                    label={gettext("Term (months)")}
                    min="1"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-undiscounted"
                    field={@financing_form[:undiscounted_commitment]}
                    type="basic"
                    label={gettext("Undiscounted commitment")}
                    placeholder="0.00"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-initial-liability"
                    field={@financing_form[:initial_liability]}
                    type="basic"
                    label={gettext("Initial liability (leases)")}
                    placeholder="0.00"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-interest-rate"
                    field={@financing_form[:interest_rate]}
                    type="basic"
                    label={gettext("Interest rate (%)")}
                    placeholder="0.0000"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-principal"
                    field={@financing_form[:principal_amount]}
                    type="basic"
                    label={gettext("Principal amount (loans)")}
                    placeholder="0.00"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-option-amount"
                    field={@financing_form[:purchase_option_amount]}
                    type="basic"
                    label={gettext("Purchase option amount (option lease)")}
                    placeholder="0.00"
                    show_suffix={false}
                  />

                  <.text_input
                    id="new-financing-option-available-from"
                    field={@financing_form[:purchase_option_available_from]}
                    type="basic"
                    input_type="date"
                    label={gettext("Option available from")}
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
                    phx-click="close_new_financing_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-financing-submit"
                    label={gettext("Register financing")}
                    size="small"
                    type="submit"
                    form="new-financing-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Arrangements")} icon="server" data-part="financings-card">
        <.card_section>
          <.table
            id="financings-table"
            rows={@financings}
            row_key={fn f -> "financings-row-#{f.id}" end}
            row_navigate={fn f -> ~p"/hardware/financings/#{f.id}" end}
          >
            <:col
              :let={f}
              label={gettext("Arrangement")}
              patch={column_patch_sort(assigns, "provider")}
              sort_order={column_sort_order(assigns, "provider")}
            >
              <.text_and_description_cell
                label={f.provider}
                description={arrangement_description(f)}
              />
            </:col>
            <:col :let={f} label={gettext("Type")}>
              <.badge_cell label={humanize(f.type)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={f} label={gettext("Treatment")}>
              <.badge_cell
                label={humanize(f.accounting_treatment)}
                color={treatment_color(f.accounting_treatment)}
                style="light-fill"
              />
            </:col>
            <:col :let={f} label={gettext("Status")}>
              <.badge_cell
                label={humanize(f.status)}
                color={status_color(f.status)}
                style="light-fill"
              />
            </:col>
            <:col
              :let={f}
              label={gettext("Commencement")}
              patch={column_patch_sort(assigns, "disbursement_or_commencement_on")}
              sort_order={column_sort_order(assigns, "disbursement_or_commencement_on")}
            >
              <.text_cell label={date_or_dash(f.disbursement_or_commencement_on)} />
            </:col>
            <:col :let={f} label={gettext("Commitment")}>
              <.text_cell label={amount(f.undiscounted_commitment, f.currency)} />
            </:col>
            <:col :let={f} label={gettext("Term")}>
              <.text_cell label={term_label(f)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No arrangements yet")}
                subtitle={gettext("Register a loan or lease with the button above, or via MCP.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp arrangement_description(%Financing{} = f) do
    [f.reference, humanize(f.currency)]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      description -> description
    end
  end

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp treatment_color("capitalized"), do: "success"
  defp treatment_color("expensed"), do: "information"
  defp treatment_color("undetermined"), do: "attention"
  defp treatment_color(_), do: "neutral"

  defp status_color("active"), do: "success"
  defp status_color("paid_off"), do: "information"
  defp status_color("option_exercised"), do: "success"
  defp status_color("returned"), do: "neutral"
  defp status_color("terminated"), do: "destructive"
  defp status_color(_), do: "neutral"

  defp amount(%Decimal{} = value, currency) when is_binary(currency),
    do: "#{currency} #{Decimal.to_string(value, :normal)}"

  defp amount(_, _), do: "-"

  defp term_label(%Financing{term_months: nil}), do: "-"
  defp term_label(%Financing{term_months: months}), do: "#{months} #{gettext("months")}"

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
