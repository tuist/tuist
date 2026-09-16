defmodule AtlasWeb.InsuranceLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Insurance.Policies
  alias Atlas.Insurance.Policy

  @page_size 50
  @sortable_fields ~w(provider product starts_on ends_on annual_premium inserted_at)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Insurance"))
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, "desc")
     |> assign(:uri, URI.new!("?"))
     |> assign(:policies, [])
     |> assign_new_form()}
  end

  def handle_params(params, _uri, socket) do
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])

    {rows, _meta} =
      Policies.list(Map.merge(%{page: 1, page_size: @page_size}, sort_flop_params(sort_by, sort_order)))

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:policies, rows)}
  end

  def handle_event("validate_new_policy", %{"policy" => attrs}, socket) do
    form =
      attrs
      |> Policies.change()
      |> Map.put(:action, :validate)
      |> to_form(as: :policy)

    {:noreply, assign(socket, :policy_form, form)}
  end

  def handle_event("create_policy", %{"policy" => attrs}, socket) do
    case Policies.create(attrs) do
      {:ok, policy} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Insurance policy registered."))
         |> assign_new_form()
         |> push_event("close-modal", %{id: "new-policy-modal"})
         |> push_navigate(to: ~p"/hardware/insurance/#{policy.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :policy_form, to_form(changeset, as: :policy))}
    end
  end

  def handle_event("close_new_policy_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_form()
     |> push_event("close-modal", %{id: "new-policy-modal"})}
  end

  def handle_event("new_policy_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, assign_new_form(socket)}
  end

  def handle_event("new_policy_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_new_form(socket) do
    defaults = %{
      "currency" => "EUR",
      "premium_frequency" => "annual",
      "provisional_cover_pct" => 0
    }

    form =
      defaults
      |> Policies.change()
      |> to_form(as: :policy)

    assign(socket, :policy_form, form)
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
  defp normalize_sort_by(_), do: "inserted_at"

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
    <div id="insurance">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Insurance")}</h1>
          <p data-part="description">
            {gettext(
              "Policies covering Tuist hardware. Each policy declares which assets it insures."
            )}
          </p>
        </div>
        <div data-part="header-actions">
          <.modal
            id="new-policy-modal"
            title={gettext("Register insurance policy")}
            description={gettext("Record a new policy from an insurer.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_new_policy_modal"
            on_open_change="new_policy_modal_open_changed"
            data-part="new-policy-modal"
          >
            <:header_icon><.file /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="new-policy-button"
                label={gettext("Register policy")}
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="new-policy-modal-content">
              <.form
                id="new-policy-form"
                for={@policy_form}
                phx-change="validate_new_policy"
                phx-submit="create_policy"
              >
                <div data-part="new-policy-form-grid">
                  <.text_input
                    id="new-policy-provider"
                    field={@policy_form[:provider]}
                    type="basic"
                    label={gettext("Provider")}
                    placeholder="Alte Leipziger"
                    required
                    show_required
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-product"
                    field={@policy_form[:product]}
                    type="basic"
                    label={gettext("Product")}
                    placeholder="Elektronikversicherung"
                    required
                    show_required
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-reference"
                    field={@policy_form[:reference]}
                    type="basic"
                    label={gettext("Policy number")}
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-currency"
                    field={@policy_form[:currency]}
                    type="basic"
                    label={gettext("Currency (ISO 4217)")}
                    placeholder="EUR"
                    required
                    show_required
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-sum-insured"
                    field={@policy_form[:sum_insured]}
                    type="basic"
                    label={gettext("Sum insured")}
                    placeholder="100000.00"
                    required
                    show_required
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-provisional-cover-pct"
                    field={@policy_form[:provisional_cover_pct]}
                    type="basic"
                    input_type="number"
                    label={gettext("Provisional cover (%)")}
                    min="0"
                    max="200"
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-annual-premium"
                    field={@policy_form[:annual_premium]}
                    type="basic"
                    label={gettext("Annual premium")}
                    placeholder="0.00"
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-deductible-per-claim"
                    field={@policy_form[:deductible_per_claim]}
                    type="basic"
                    label={gettext("Deductible per claim")}
                    placeholder="0.00"
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-starts-on"
                    field={@policy_form[:starts_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Starts on")}
                    show_suffix={false}
                  />
                  <.text_input
                    id="new-policy-ends-on"
                    field={@policy_form[:ends_on]}
                    type="basic"
                    input_type="date"
                    label={gettext("Ends on")}
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
                    phx-click="close_new_policy_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="new-policy-submit"
                    label={gettext("Register policy")}
                    size="small"
                    type="submit"
                    form="new-policy-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Policies")} icon="file" data-part="insurance-card">
        <.card_section>
          <.table
            id="insurance-table"
            rows={@policies}
            row_key={fn p -> "insurance-row-#{p.id}" end}
            row_navigate={fn p -> ~p"/hardware/insurance/#{p.id}" end}
          >
            <:col
              :let={p}
              label={gettext("Policy")}
              patch={column_patch_sort(assigns, "provider")}
              sort_order={column_sort_order(assigns, "provider")}
            >
              <.text_and_description_cell label={p.provider} description={policy_description(p)} />
            </:col>
            <:col :let={p} label={gettext("Sum insured")}>
              <.text_cell label={amount(p.sum_insured, p.currency)} />
            </:col>
            <:col
              :let={p}
              label={gettext("Premium")}
              patch={column_patch_sort(assigns, "annual_premium")}
              sort_order={column_sort_order(assigns, "annual_premium")}
            >
              <.text_cell label={premium_label(p)} />
            </:col>
            <:col :let={p} label={gettext("Deductible")}>
              <.text_cell label={amount(p.deductible_per_claim, p.currency)} />
            </:col>
            <:col :let={p} label={gettext("Status")}>
              <.badge_cell
                label={humanize(p.status)}
                color={status_color(p.status)}
                style="light-fill"
              />
            </:col>
            <:col
              :let={p}
              label={gettext("Starts")}
              patch={column_patch_sort(assigns, "starts_on")}
              sort_order={column_sort_order(assigns, "starts_on")}
            >
              <.text_cell label={date_or_dash(p.starts_on)} />
            </:col>
            <:col
              :let={p}
              label={gettext("Ends")}
              patch={column_patch_sort(assigns, "ends_on")}
              sort_order={column_sort_order(assigns, "ends_on")}
            >
              <.text_cell label={date_or_dash(p.ends_on)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No policies yet")}
                subtitle={gettext("Register a policy to start tracking coverage.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp policy_description(%Policy{product: product, reference: nil}), do: product

  defp policy_description(%Policy{product: product, reference: reference}) do
    [product, reference]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  defp premium_label(%Policy{annual_premium: nil}), do: "-"

  defp premium_label(%Policy{annual_premium: amount, currency: currency, premium_frequency: freq}) do
    "#{amount(amount, currency)}/#{humanize(freq)}"
  end

  defp humanize(nil), do: "-"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_color("active"), do: "success"
  defp status_color("quoted"), do: "attention"
  defp status_color("expired"), do: "neutral"
  defp status_color("cancelled"), do: "destructive"
  defp status_color("terminated"), do: "destructive"
  defp status_color(_), do: "neutral"

  defp amount(%Decimal{} = value, currency) when is_binary(currency),
    do: "#{currency} #{Decimal.to_string(value, :normal)}"

  defp amount(_, _), do: "-"

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
