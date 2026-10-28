defmodule AtlasWeb.EmailMailboxLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.EmailHeader
  import Noora.Filter

  alias Atlas.Mailbox
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @page_size 25
  @kind_filter "kind"
  @status_filter "status"

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Email"))
     |> assign(:uri, %URI{query: ""})
     |> assign(:available_filters, [])}
  end

  def handle_params(params, uri, socket) do
    socket = assign(socket, :uri, normalized_uri(uri))

    case socket.assigns.live_action do
      :inbox -> {:noreply, assign_inbox(socket, params)}
      :outbox -> {:noreply, assign_outbox(socket, params)}
      :sent_email -> {:noreply, assign_sent_email(socket, params["id"])}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> put_search_query(query)

    {:noreply, push_patch(socket, to: list_path(socket, query_params), replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: list_path(socket, updated_params))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: list_path(socket, updated_params))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def render(assigns) do
    ~H"""
    <div id="email" data-part="email-page">
      <%= case @live_action do %>
        <% :inbox -> %>
          <.inbox_view
            entries={@entries}
            meta={@meta}
            search_form={@search_form}
            uri={@uri}
          />
        <% :outbox -> %>
          <.outbox_view
            entries={@entries}
            meta={@meta}
            search_form={@search_form}
            available_filters={@available_filters}
            active_filters={@active_filters}
            uri={@uri}
          />
        <% :sent_email -> %>
          <.sent_email_view email={@email} />
      <% end %>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :meta, :map, required: true
  attr :search_form, :map, required: true
  attr :uri, URI, required: true

  defp inbox_view(assigns) do
    ~H"""
    <.email_header selected={:inbox} />

    <.card title={gettext("Inbox")} icon="mail" data-part="email-inbox-card">
      <.card_section>
        <div data-part="filters">
          <div data-part="search">
            <.form
              id="email-inbox-search-form"
              for={@search_form}
              phx-change="search"
              phx-submit="search"
            >
              <.text_input
                id="email-inbox-search"
                field={@search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search by sender or subject")}
              />
            </.form>
          </div>
        </div>

        <.table
          id="email-inbox-table"
          rows={@entries}
          row_key={& &1.id}
          row_navigate={fn entry -> ~p"/commercial/support/#{entry.thread_id}" end}
        >
          <:col :let={entry} label={gettext("Email")}>
            <.text_and_description_cell
              label={entry.subject || gettext("(No subject)")}
              description={participant(entry.from_name, entry.from_email)}
            />
          </:col>
          <:col :let={entry} label={gettext("Account")}>
            <.text_cell label={entry.account_name || "—"} />
          </:col>
          <:col :let={entry} label={gettext("Conversation")}>
            <.badge_cell
              label={thread_status_label(entry.thread_status)}
              color={thread_status_color(entry.thread_status)}
              style="light-fill"
            />
          </:col>
          <:col :let={entry} label={gettext("Received")}>
            <.text_cell label={format_datetime(entry.received_at)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="mail"
              title={gettext("No emails received")}
              subtitle={
                gettext("Emails sent to %{address} will appear here.", address: Mailbox.address())
              }
            />
          </:empty_state>
        </.table>

        <.pagination_group
          :if={@meta.total_pages > 1}
          id="email-inbox-pagination"
          current_page={@meta.current_page}
          number_of_pages={@meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "page", page)}" end}
        />
      </.card_section>
    </.card>
    """
  end

  attr :entries, :list, required: true
  attr :meta, :map, required: true
  attr :search_form, :map, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true
  attr :uri, URI, required: true

  defp outbox_view(assigns) do
    ~H"""
    <.email_header selected={:outbox} />

    <.card title={gettext("Outbox")} icon="mail" data-part="email-outbox-card">
      <.card_section>
        <div data-part="filters">
          <div data-part="search">
            <.form
              id="email-outbox-search-form"
              for={@search_form}
              phx-change="search"
              phx-submit="search"
            >
              <.text_input
                id="email-outbox-search"
                field={@search_form[:query]}
                type="search"
                show_suffix={false}
                placeholder={gettext("Search by recipient or subject")}
              />
            </.form>
          </div>

          <.filter_dropdown
            id="email-outbox-filters-dropdown"
            available_filters={@available_filters}
            active_filters={@active_filters}
            on_select="add_filter"
          />
        </div>

        <div :if={@active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @active_filters} filter={filter} />
        </div>

        <.table
          id="email-outbox-table"
          rows={@entries}
          row_key={& &1.id}
          row_navigate={fn entry -> ~p"/outbound/email/outbox/#{entry.id}" end}
        >
          <:col :let={entry} label={gettext("Email")}>
            <.text_and_description_cell
              label={entry.subject}
              description={gettext("From %{sender}", sender: entry.from_email)}
            />
          </:col>
          <:col :let={entry} label={gettext("To")}>
            <.text_and_description_cell
              label={Enum.join(entry.to_emails, ", ")}
              description={entry.recipient_name || entry.account_name}
            />
          </:col>
          <:col :let={entry} label={gettext("Kind")}>
            <.badge_cell label={kind_label(entry.kind)} color="neutral" style="light-fill" />
          </:col>
          <:col :let={entry} label={gettext("Status")}>
            <.badge_cell
              label={status_label(entry.status)}
              color={status_color(entry.status)}
              style="light-fill"
            />
          </:col>
          <:col :let={entry} label={gettext("Sent")}>
            <.text_cell label={format_datetime(entry.delivered_at || entry.queued_at)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="mail"
              title={gettext("No emails sent")}
              subtitle={gettext("Broadcasts, direct emails, and support replies will appear here.")}
            />
          </:empty_state>
        </.table>

        <.pagination_group
          :if={@meta.total_pages > 1}
          id="email-outbox-pagination"
          current_page={@meta.current_page}
          number_of_pages={@meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "page", page)}" end}
        />
      </.card_section>
    </.card>
    """
  end

  attr :email, :map, required: true

  defp sent_email_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{@email.subject}</h1>
        <p data-part="description">
          {gettext("%{kind} to %{recipients}",
            kind: kind_label(@email.kind),
            recipients: recipients(@email)
          )}
        </p>
      </div>
      <div data-part="header-actions">
        <.button
          :if={@email.thread_id}
          id="sent-email-conversation-button"
          label={gettext("View conversation")}
          variant="secondary"
          size="medium"
          navigate={~p"/commercial/support/#{@email.thread_id}"}
        />
        <.button
          :if={@email.audience_id}
          id="sent-email-audience-button"
          label={gettext("View audience")}
          variant="secondary"
          size="medium"
          navigate={~p"/outbound/email/audiences/#{@email.audience_id}"}
        />
        <.button
          id="sent-email-back-button"
          label={gettext("Back to outbox")}
          variant="secondary"
          size="medium"
          navigate={~p"/outbound/email/outbox"}
        >
          <:icon_left><.arrow_left /></:icon_left>
        </.button>
      </div>
    </div>

    <.card title={gettext("Details")} icon="mail" data-part="email-details-card">
      <.card_section>
        <dl data-part="details">
          <div data-part="detail">
            <dt>{gettext("From")}</dt>
            <dd>{participant(@email.from_name, @email.from_email)}</dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("To")}</dt>
            <dd>{recipients(@email)}</dd>
          </div>
          <div :if={@email.cc_emails != []} data-part="detail">
            <dt>{gettext("Cc")}</dt>
            <dd>{Enum.join(@email.cc_emails, ", ")}</dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("Reply-to")}</dt>
            <dd>{@email.reply_to_email || "—"}</dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("Kind")}</dt>
            <dd>
              <.badge
                id="sent-email-kind"
                label={kind_label(@email.kind)}
                color="neutral"
                style="light-fill"
              />
            </dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("Status")}</dt>
            <dd>
              <.badge
                id="sent-email-status"
                label={status_label(@email.status)}
                color={status_color(@email.status)}
                style="light-fill"
              />
            </dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("Queued")}</dt>
            <dd>{format_datetime(@email.queued_at)}</dd>
          </div>
          <div data-part="detail">
            <dt>{gettext("Delivered")}</dt>
            <dd>{format_datetime(@email.delivered_at)}</dd>
          </div>
          <div :if={@email.account_id} data-part="detail">
            <dt>{gettext("Account")}</dt>
            <dd>
              <.link
                id="sent-email-account-link"
                data-part="account-link"
                navigate={~p"/commercial/sales/accounts/#{@email.account_id}"}
              >
                {@email.account_name || @email.account_id}
              </.link>
            </dd>
          </div>
          <div :if={@email.audience_name} data-part="detail">
            <dt>{gettext("Audience")}</dt>
            <dd>{@email.audience_name}</dd>
          </div>
          <div :if={@email.provider_message_id} data-part="detail">
            <dt>{gettext("Provider message ID")}</dt>
            <dd>{@email.provider_message_id}</dd>
          </div>
          <div :if={@email.error} data-part="detail">
            <dt>{gettext("Last error")}</dt>
            <dd id="sent-email-error">{@email.error}</dd>
          </div>
        </dl>
      </.card_section>
    </.card>

    <.card title={gettext("Message")} icon="file_text" data-part="email-body-card">
      <.card_section>
        <%= cond do %>
          <% @email.body_markdown -> %>
            <AtlasWeb.Markdown.content id="sent-email-body" body={@email.body_markdown} />
          <% @email.template -> %>
            <p id="sent-email-template" data-part="description">
              {gettext("Rendered from the %{template} template.", template: @email.template)}
            </p>
          <% true -> %>
            <p data-part="description">{gettext("The body of this email was not recorded.")}</p>
        <% end %>
      </.card_section>
    </.card>
    """
  end

  defp assign_inbox(socket, params) do
    query = Query.present_string(params["query"])

    {entries, meta} =
      Mailbox.list_inbox(
        query: query,
        page: Query.parse_page(params["page"]),
        page_size: @page_size
      )

    socket
    |> assign(:page_title, gettext("Inbox"))
    |> assign(:available_filters, [])
    |> assign(:entries, entries)
    |> assign(:meta, meta)
    |> assign(:search_form, to_form(%{"query" => query || ""}, as: :search))
  end

  defp assign_outbox(socket, params) do
    query = Query.present_string(params["query"])
    available_filters = define_outbox_filters()
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {entries, meta} =
      Mailbox.list_outbox(
        query: query,
        kind: filter_value(active_filters, @kind_filter),
        status: filter_value(active_filters, @status_filter),
        page: Query.parse_page(params["page"]),
        page_size: @page_size
      )

    socket
    |> assign(:page_title, gettext("Outbox"))
    |> assign(:available_filters, available_filters)
    |> assign(:active_filters, active_filters)
    |> assign(:entries, entries)
    |> assign(:meta, meta)
    |> assign(:search_form, to_form(%{"query" => query || ""}, as: :search))
  end

  defp assign_sent_email(socket, id) do
    case Mailbox.get_sent_email(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Email not found."))
        |> push_navigate(to: ~p"/outbound/email/outbox")

      email ->
        socket
        |> assign(:page_title, email.subject)
        |> assign(:email, email)
    end
  end

  defp define_outbox_filters do
    [
      option_filter(@kind_filter, gettext("Kind"), Mailbox.outbox_kinds(), &kind_label/1),
      option_filter(@status_filter, gettext("Status"), Mailbox.outbox_statuses(), &status_label/1)
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
      searchable: false,
      value: nil
    }
  end

  defp filter_value(active_filters, filter_id) do
    with %{operator: operator, value: value} <- Enum.find(active_filters, &(&1.id == filter_id)),
         value when not is_nil(value) <- Query.present_string(value) do
      {operator, value}
    else
      _other -> nil
    end
  end

  defp list_path(socket, query_params) do
    case socket.assigns.live_action do
      :inbox -> ~p"/outbound/email/inbox?#{query_params}"
      :outbox -> ~p"/outbound/email/outbox?#{query_params}"
    end
  end

  defp normalized_uri(uri) do
    %URI{query: URI.parse(uri).query || ""}
  end

  defp current_query_params(socket), do: URI.decode_query(socket.assigns.uri.query || "")

  defp put_search_query(params, value) do
    case Query.present_string(value) do
      nil -> Map.delete(params, "query")
      trimmed -> Map.put(params, "query", trimmed)
    end
  end

  defp participant(name, email) when is_binary(name) and name != "", do: "#{name} <#{email}>"
  defp participant(_name, email), do: email

  defp recipients(%{recipient_name: name, to_emails: [email]}) when is_binary(name) and name != "",
    do: participant(name, email)

  defp recipients(%{to_emails: emails}), do: Enum.join(emails, ", ")

  defp kind_label("broadcast"), do: gettext("Broadcast")
  defp kind_label("direct"), do: gettext("Direct")
  defp kind_label("transactional"), do: gettext("Transactional")
  defp kind_label("welcome"), do: gettext("Welcome")
  defp kind_label("confirmation"), do: gettext("Confirmation")
  defp kind_label("support_reply"), do: gettext("Support reply")
  defp kind_label(kind), do: kind

  defp status_label("queued"), do: gettext("Queued")
  defp status_label("sent"), do: gettext("Sent")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label("skipped"), do: gettext("Skipped")
  defp status_label(status), do: status

  defp status_color("sent"), do: "success"
  defp status_color("failed"), do: "destructive"
  defp status_color("queued"), do: "warning"
  defp status_color(_status), do: "neutral"

  defp thread_status_label("open"), do: gettext("Needs reply")
  defp thread_status_label("waiting"), do: gettext("Waiting")
  defp thread_status_label("resolved"), do: gettext("Resolved")
  defp thread_status_label(status), do: status

  defp thread_status_color("open"), do: "attention"
  defp thread_status_color("waiting"), do: "information"
  defp thread_status_color("resolved"), do: "success"
  defp thread_status_color(_status), do: "neutral"

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  defp format_datetime(_datetime), do: "—"
end
