defmodule AtlasWeb.FinancingShowLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingDocument
  alias Atlas.Finance.Financings

  def mount(%{"id" => id}, _session, socket) do
    case Financings.get(id) do
      %Financing{} = financing ->
        {schedules, _} = Financings.list_schedules(financing)
        lines = Financings.list_lines(financing)
        {payments, _} = Financings.list_payments(financing)

        {:ok,
         socket
         |> assign(:page_title, financing.provider)
         |> assign(:financing, financing)
         |> assign(:schedules, schedules)
         |> assign(:lines, lines)
         |> assign(:payments, payments)
         |> assign(:documents, Financings.list_documents(financing))
         |> assign_document_form()
         |> assign_document_picker()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Financing not found."))
         |> push_navigate(to: ~p"/hardware/financings")}
    end
  end

  def handle_event("attach_document", %{"document" => attrs}, socket) do
    opts = if attrs["notes"] in [nil, ""], do: [], else: [notes: attrs["notes"]]

    case Financings.attach_document(
           socket.assigns.financing,
           attrs["document_id"],
           attrs["kind"],
           opts
         ) do
      {:ok, _link} ->
        {:noreply,
         socket
         |> assign(:documents, Financings.list_documents(socket.assigns.financing))
         |> assign_document_form()
         |> assign_document_picker()
         |> put_flash(:info, gettext("Document attached."))
         |> push_event("close-modal", %{id: "attach-financing-document-modal"})}

      {:error, :document_not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Document not found."))}

      {:error, :document_not_ready} ->
        {:noreply, put_flash(socket, :error, gettext("Document upload is not complete."))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_changeset_errors(changeset))}
    end
  end

  def handle_event("detach_document", %{"id" => id}, socket) do
    case Financings.detach_document(id) do
      {:ok, _link} ->
        {:noreply,
         socket
         |> assign(:documents, Financings.list_documents(socket.assigns.financing))
         |> put_flash(:info, gettext("Document detached."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Document attachment not found."))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_changeset_errors(changeset))}
    end
  end

  def handle_event("search_financing_documents", %{"document_search" => params}, socket) do
    {:noreply,
     socket
     |> assign(:document_search_form, to_form(params, as: :document_search))
     |> assign(:document_matches, document_matches(socket, params["query"]))}
  end

  def handle_event("select_financing_document", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.document_matches, &(&1.id == id)) do
      %Document{} = document ->
        {:noreply,
         socket
         |> assign(:selected_document, document)
         |> assign_document_form(%{"document_id" => document.id, "kind" => "supplier_contract"})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("close_attach_document_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_document_form()
     |> assign_document_picker()
     |> push_event("close-modal", %{id: "attach-financing-document-modal"})}
  end

  def handle_event("attach_document_modal_open_changed", %{"open" => false}, socket) do
    {:noreply, socket |> assign_document_form() |> assign_document_picker()}
  end

  def handle_event("attach_document_modal_open_changed", _params, socket), do: {:noreply, socket}

  defp assign_document_form(socket, attrs \\ %{"kind" => "supplier_contract"}) do
    assign(socket, :document_form, to_form(attrs, as: :document))
  end

  defp assign_document_picker(socket) do
    socket
    |> assign(:document_search_form, to_form(%{"query" => ""}, as: :document_search))
    |> assign(:document_matches, document_matches(socket, nil))
    |> assign(:selected_document, nil)
  end

  defp document_matches(socket, query) do
    attached_document_ids = MapSet.new(socket.assigns.documents, & &1.document_id)

    [status: "ready", query: query, limit: 10]
    |> Documents.list_documents()
    |> Enum.reject(&MapSet.member?(attached_document_ids, &1.id))
  end

  def render(assigns) do
    ~H"""
    <div id="financing-show">
      <div data-part="header">
        <div data-part="text">
          <.breadcrumbs data-part="breadcrumbs">
            <.breadcrumb
              id="financing-breadcrumb-list"
              label={gettext("Financings")}
              phx-click={JS.navigate(~p"/hardware/financings")}
            />
            <.breadcrumb id="financing-breadcrumb-current" label={@financing.provider} />
          </.breadcrumbs>
          <h1 data-part="title">{@financing.provider}</h1>
          <p data-part="description">{@financing.reference || gettext("Financing arrangement")}</p>
          <div data-part="summary">
            <.badge label={humanize(@financing.type)} color="neutral" style="light-fill" />
            <.badge
              label={humanize(@financing.accounting_treatment)}
              color={treatment_color(@financing.accounting_treatment)}
              style="light-fill"
            />
            <.badge
              label={humanize(@financing.status)}
              color={status_color(@financing.status)}
              style="light-fill"
            />
          </div>
        </div>
      </div>

      <.card title={gettext("Details")} icon="file" data-part="details-card">
        <.card_section>
          <dl data-part="details">
            <div data-part="detail">
              <dt>{gettext("Supplier")}</dt>
              <dd>{value_or_dash(@financing.supplier)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Currency")}</dt>
              <dd>{@financing.currency}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Undiscounted commitment")}</dt>
              <dd>{amount(@financing.undiscounted_commitment, @financing.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Initial liability")}</dt>
              <dd>{amount(@financing.initial_liability, @financing.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Principal")}</dt>
              <dd>{amount(@financing.principal_amount, @financing.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Purchase option")}</dt>
              <dd>{amount(@financing.purchase_option_amount, @financing.currency)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Option available from")}</dt>
              <dd>{date_or_dash(@financing.purchase_option_available_from)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Commencement")}</dt>
              <dd>{date_or_dash(@financing.disbursement_or_commencement_on)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Term")}</dt>
              <dd>{term_label(@financing)}</dd>
            </div>
            <div data-part="detail">
              <dt>{gettext("Interest rate")}</dt>
              <dd>{rate_label(@financing.interest_rate)}</dd>
            </div>
          </dl>
        </.card_section>
      </.card>

      <.card title={gettext("Documents")} icon="file" data-part="documents-card">
        <:actions>
          <.modal
            id="attach-financing-document-modal"
            title={gettext("Attach document")}
            description={gettext("Link an existing document to this financing arrangement.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_attach_document_modal"
            on_open_change="attach_document_modal_open_changed"
            data-part="attach-financing-document-modal"
          >
            <:header_icon><.file /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="attach-financing-document-button"
                label={gettext("Attach document")}
                variant="secondary"
                size="medium"
                type="button"
                {modal_attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="attach-financing-document-modal-content">
              <div data-part="financing-document-picker">
                <.label label={gettext("Document")} required />
                <.form
                  id="financing-document-search-form"
                  for={@document_search_form}
                  phx-change="search_financing_documents"
                >
                  <.text_input
                    id="financing-document-search"
                    field={@document_search_form[:query]}
                    type="search"
                    placeholder={gettext("Search by title or filename")}
                    phx-debounce="200"
                  />
                </.form>

                <div data-part="financing-document-options">
                  <button
                    :for={document <- @document_matches}
                    id={"financing-document-option-#{document.id}"}
                    type="button"
                    data-part="financing-document-option"
                    data-selected={@selected_document && @selected_document.id == document.id}
                    aria-pressed={@selected_document && @selected_document.id == document.id}
                    phx-click="select_financing_document"
                    phx-value-id={document.id}
                  >
                    <span data-part="document-option-text">
                      <span data-part="document-option-title">{document_picker_title(document)}</span>
                      <span data-part="document-option-filename">{document.original_filename}</span>
                    </span>
                    <span data-part="document-option-indicator">
                      <.check :if={@selected_document && @selected_document.id == document.id} />
                    </span>
                  </button>
                  <p :if={@document_matches == []} data-part="document-options-empty">
                    {gettext("No matching documents found.")}
                  </p>
                </div>
              </div>

              <.form
                id="attach-financing-document-form"
                for={@document_form}
                phx-submit="attach_document"
              >
                <div data-part="attach-financing-document-form-fields">
                  <input
                    id="financing-document-id"
                    type="hidden"
                    name={@document_form[:document_id].name}
                    value={@document_form[:document_id].value}
                  />
                  <div data-part="labeled-select">
                    <.label label={gettext("Document kind")} required />
                    <.select
                      id="financing-document-kind"
                      field={@document_form[:kind]}
                      label={gettext("Select a kind")}
                    >
                      <:item
                        :for={kind <- FinancingDocument.kinds()}
                        value={kind}
                        label={humanize(kind)}
                      />
                    </.select>
                  </div>
                  <.text_input
                    id="financing-document-notes"
                    field={@document_form[:notes]}
                    type="basic"
                    label={gettext("Notes")}
                    show_suffix={false}
                  />
                </div>
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    id="cancel-attach-financing-document"
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_attach_document_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="attach-financing-document-submit"
                    label={gettext("Attach document")}
                    size="small"
                    type="submit"
                    form="attach-financing-document-form"
                    disabled={is_nil(@selected_document)}
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </:actions>

        <.card_section>
          <.table
            id="financing-documents-table"
            rows={@documents}
            row_key={fn link -> "financing-document-#{link.id}" end}
            row_navigate={fn link -> ~p"/documents/#{link.document_id}" end}
          >
            <:col :let={link} label={gettext("Kind")}>
              <.badge_cell label={humanize(link.kind)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={link} label={gettext("Document")}>
              <.text_cell label={document_title(link)} />
            </:col>
            <:col :let={link} label={gettext("Notes")}>
              <.text_cell label={value_or_dash(link.notes)} />
            </:col>
            <:col :let={link} label={gettext("Actions")}>
              <.button
                id={"detach-financing-document-#{link.id}"}
                label={gettext("Detach")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="detach_document"
                phx-value-id={link.id}
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No documents attached")}
                subtitle={gettext("Attach the supplier contract, financing agreement, or guarantee.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Assets")} icon="server" data-part="lines-card">
        <.card_section>
          <.table
            id="financing-lines-table"
            rows={@lines}
            row_key={fn line -> "financing-line-#{line.id}" end}
            row_navigate={fn line -> ~p"/hardware/#{line.asset_id}" end}
          >
            <:col :let={line} label={gettext("Asset")}>
              <.text_cell label={asset_label(line)} />
            </:col>
            <:col :let={line} label={gettext("Share")}>
              <.text_cell label={share_label(line)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No linked assets")}
                subtitle={
                  gettext("Use set_financing_lines to allocate this arrangement across assets.")
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Schedule")} icon="file_text" data-part="schedules-card">
        <.card_section>
          <.table
            id="financing-schedules-table"
            rows={@schedules}
            row_key={fn s -> "financing-schedule-#{s.id}" end}
          >
            <:col :let={s} label={gettext("Seq")}>
              <.text_cell label={"##{s.sequence}"} />
            </:col>
            <:col :let={s} label={gettext("Due")}>
              <.text_cell label={date_or_dash(s.due_on)} />
            </:col>
            <:col :let={s} label={gettext("Total")}>
              <.text_cell label={amount(s.expected_total, @financing.currency)} />
            </:col>
            <:col :let={s} label={gettext("Principal / Interest")}>
              <.text_cell label={
                component_pair(s.principal_amount, s.interest_amount, @financing.currency)
              } />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No schedule")}
                subtitle={gettext("Import an accountant-provided schedule when available.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card title={gettext("Payments")} icon="mail" data-part="payments-card">
        <.card_section>
          <.table
            id="financing-payments-table"
            rows={@payments}
            row_key={fn p -> "financing-payment-#{p.id}" end}
          >
            <:col :let={p} label={gettext("Paid on")}>
              <.text_cell label={date_or_dash(p.paid_on)} />
            </:col>
            <:col :let={p} label={gettext("Direction")}>
              <.badge_cell label={humanize(p.direction)} color="neutral" style="light-fill" />
            </:col>
            <:col :let={p} label={gettext("Amount")}>
              <.text_cell label={amount(p.settlement_amount, p.settlement_currency)} />
            </:col>
            <:col :let={p} label={gettext("Status")}>
              <.badge_cell
                label={humanize(p.resolution_status)}
                color={resolution_color(p.resolution_status)}
                style="light-fill"
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                title={gettext("No matched payments")}
                subtitle={gettext("Payments matched from Finance transactions appear here.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </div>
    """
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

  defp resolution_color("resolved"), do: "success"
  defp resolution_color("partial"), do: "attention"
  defp resolution_color("unresolved"), do: "neutral"
  defp resolution_color(_), do: "neutral"

  defp amount(nil, _), do: "-"

  defp amount(%Decimal{} = value, currency) when is_binary(currency),
    do: "#{currency} #{Decimal.to_string(value, :normal)}"

  defp amount(_, _), do: "-"

  defp date_or_dash(nil), do: "-"
  defp date_or_dash(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")

  defp term_label(%Financing{term_months: nil}), do: "-"
  defp term_label(%Financing{term_months: months}), do: "#{months} #{gettext("months")}"

  defp rate_label(nil), do: "-"
  defp rate_label(%Decimal{} = d), do: "#{Decimal.to_string(Decimal.mult(d, Decimal.new(100)), :normal)}%"

  defp component_pair(nil, nil, _currency), do: "-"

  defp component_pair(p, i, currency), do: "#{amount(p, currency)} / #{amount(i, currency)}"

  defp asset_label(%{asset: %{name: name}}) when is_binary(name), do: name
  defp asset_label(%{asset_id: id}), do: id

  defp share_label(%{share_bps: bps}) do
    percent = bps |> div(100)
    remainder = bps |> rem(100)
    "#{percent}.#{String.pad_leading(Integer.to_string(remainder), 2, "0")}%"
  end

  defp value_or_dash(nil), do: "-"
  defp value_or_dash(""), do: "-"
  defp value_or_dash(value), do: to_string(value)

  defp document_title(%{document: %{title: title}}) when is_binary(title) and title != "", do: title
  defp document_title(%{document: %{original_filename: name}}) when is_binary(name), do: name
  defp document_title(_link), do: "-"

  defp document_picker_title(%Document{title: title}) when is_binary(title) and title != "", do: title

  defp document_picker_title(%Document{original_filename: filename}), do: filename

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join(", ")
  end
end
