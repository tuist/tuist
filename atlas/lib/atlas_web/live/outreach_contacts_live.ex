defmodule AtlasWeb.OutreachContactsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Accounts.Agents.ScreenshotNoteAgent
  alias Atlas.Accounts.Contact
  alias Atlas.Outreach
  alias AtlasWeb.AccountLive.Screenshots
  alias AtlasWeb.Utilities.Avatar
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  require Logger

  @candidates_page_size 20
  @recommendation_poll_ms 750
  @recommendation_poll_timeout_ms 120_000
  @screenshot_min_processing_ms 600

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:event_form, event_form())
     |> assign(:contacts_empty?, true)
     |> assign(:candidates_empty?, true)
     |> assign(:events_empty?, true)
     |> assign(:screenshot_processing, false)
     |> assign(:recommendation_processing, false)
     |> assign(:recommendation_poll_deadline, nil)
     |> assign(:recommendation_notice, nil)
     |> assign(:screenshot_error, nil)
     |> assign(:staged_screenshots, [])
     |> assign(:candidate_result, nil)
     |> assign(:available_filters, define_filters())}
  end

  def handle_params(params, uri, socket) do
    {:noreply, assign_page(socket, socket.assigns.live_action, params, uri)}
  end

  def render(assigns) do
    ~H"""
    <div id={@page_id} data-part="outreach-contacts-page">
      <%= case @live_action do %>
        <% :index -> %>
          <.contacts_view
            contacts={@streams.contacts}
            contacts_empty?={@contacts_empty?}
            candidates={@streams.candidates}
            candidates_empty?={@candidates_empty?}
            candidates_meta={@candidates_meta}
            search_form={@search_form}
            available_filters={@available_filters}
            active_filters={@active_filters}
            sort_by={@sort_by}
            sort_order={@sort_order}
            uri={@uri}
            candidate_result={@candidate_result}
          />
        <% :show -> %>
          <.contact_view
            contact={@contact}
            events={@streams.events}
            events_empty?={@events_empty?}
            event_form={@event_form}
            staged_screenshots={@staged_screenshots}
            screenshot_processing={@screenshot_processing}
            screenshot_error={@screenshot_error}
            recommendation={@recommendation}
            recommendation_form={@recommendation_form}
            recommendation_processing={@recommendation_processing}
            recommendation_notice={@recommendation_notice}
          />
      <% end %>
    </div>
    """
  end

  def handle_event("filter_contacts", %{"search" => params}, socket) do
    query = params["query"] |> to_string() |> String.trim()

    {:noreply,
     push_patch(socket,
       to:
         outreach_path(
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
     |> push_patch(to: ~p"/gtm/outreach?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/gtm/outreach?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("enroll_candidate", %{"id" => id}, socket) do
    case Outreach.enroll_candidate(id, socket.assigns.current_user) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> assign(:candidate_result, gettext("%{name} was added to outreach.", name: contact.full_name))
         |> refresh_outreach_data()}

      {:error, reason} ->
        {:noreply, assign(socket, :candidate_result, candidate_action_error_message(reason))}
    end
  end

  def handle_event("reject_candidate", %{"id" => id}, socket) do
    case Outreach.reject_candidate(id, nil, socket.assigns.current_user) do
      {:ok, _candidate} ->
        {:noreply,
         socket
         |> assign(:candidate_result, gettext("Candidate dismissed."))
         |> refresh_outreach_data()}

      {:error, reason} ->
        {:noreply, assign(socket, :candidate_result, candidate_action_error_message(reason))}
    end
  end

  def handle_event("record_quick_event", %{"kind" => kind}, socket) do
    persist_event(socket, %{"kind" => kind})
  end

  def handle_event("record_event", %{"event" => params}, socket) do
    persist_event(socket, params)
  end

  def handle_event("complete_recommendation", params, socket) do
    id = params["id"] || params["recommendation_id"]
    attrs = Map.get(params, "completion", %{})

    case Outreach.complete_recommendation(id, socket.assigns.current_user, attrs) do
      {:ok, %{contact: contact}} ->
        recommendation = Outreach.current_recommendation(contact)
        # Completing a step enqueues the follow-up generation, so pick the poll
        # back up instead of dropping the operator on the empty state.
        processing? = Outreach.recommendation_generation_pending?(contact)

        {:noreply,
         socket
         |> assign(:contact, contact)
         |> assign_recommendation(recommendation)
         |> assign(:recommendation_processing, processing?)
         |> assign(:events_empty?, contact.events == [])
         |> stream(:events, contact.events, reset: true)
         |> maybe_schedule_recommendation_poll(processing?)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not complete the suggested next step."))}
    end
  end

  def handle_event("dismiss_recommendation", %{"id" => id}, socket) do
    case Outreach.dismiss_recommendation(
           id,
           "Dismissed from the outreach contact page",
           socket.assigns.current_user
         ) do
      {:ok, _recommendation} ->
        {:noreply, assign_recommendation(socket, nil)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not dismiss the suggestion."))}
    end
  end

  def handle_event("refresh_recommendation", _params, socket) do
    if socket.assigns.recommendation_processing do
      {:noreply, socket}
    else
      case Outreach.request_recommendation_generation(
             socket.assigns.contact,
             socket.assigns.current_user,
             "dashboard"
           ) do
        {:ok, _job} ->
          {:noreply,
           socket
           |> assign(:recommendation_processing, true)
           |> start_recommendation_poll()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not prepare a new suggestion."))}
      end
    end
  end

  def handle_event("screenshot_pasted", params, socket) do
    handle_event("screenshots_pasted", %{"screenshots" => [params]}, socket)
  end

  def handle_event("screenshots_pasted", %{"screenshots" => screenshots}, socket) when is_list(screenshots) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      {staged_screenshots, error} =
        Screenshots.stage(socket.assigns.staged_screenshots, screenshots)

      socket =
        socket
        |> assign(:staged_screenshots, staged_screenshots)
        |> assign(:screenshot_error, error)

      socket =
        if staged_screenshots != [] and is_nil(error) do
          start_screenshot_analysis(socket)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  def handle_event("remove_staged_screenshot", %{"id" => id}, socket) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      staged_screenshots =
        Enum.reject(socket.assigns.staged_screenshots, fn screenshot -> screenshot.id == id end)

      {:noreply, assign(socket, :staged_screenshots, staged_screenshots)}
    end
  end

  def handle_event("clear_staged_screenshots", _params, socket) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:staged_screenshots, [])
       |> assign(:screenshot_error, nil)}
    end
  end

  def handle_event("draft_from_screenshots", _params, socket) do
    {:noreply, start_screenshot_analysis(socket)}
  end

  def handle_info(:poll_recommendation, %{assigns: %{live_action: :show}} = socket) do
    contact_id = socket.assigns.contact.id

    case Outreach.recommendation_generation_status(contact_id) do
      :pending -> {:noreply, keep_polling_recommendation(socket)}
      status -> {:noreply, finish_recommendation_poll(socket, contact_id, status)}
    end
  end

  def handle_info(:poll_recommendation, socket), do: {:noreply, socket}

  def handle_async(:screenshot_analysis, {:ok, {:ok, draft}}, socket) when is_binary(draft) do
    body = String.trim(draft)

    socket
    |> assign(:screenshot_processing, false)
    |> persist_event(%{"kind" => "note", "body" => body})
  end

  def handle_async(:screenshot_analysis, {:ok, {:error, :llm_not_configured}}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(
       :screenshot_error,
       gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
     )}
  end

  def handle_async(:screenshot_analysis, {:ok, {:error, reason}}, socket) do
    Logger.error("Outreach screenshot drafting failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(:screenshot_error, gettext("Could not analyze screenshot. Please try again."))}
  end

  def handle_async(:screenshot_analysis, {:exit, reason}, socket) do
    Logger.error("Outreach screenshot drafting crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(:screenshot_error, gettext("Could not analyze screenshot. Please try again."))}
  end

  defp assign_page(socket, :index, params, uri) do
    query = params["q"] || ""
    parsed_uri = URI.parse(uri)
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    status = active_filter_value(active_filters, "stage")
    sort_by = normalize_sort_by(params["sort-by"])
    sort_order = normalize_sort_order(params["sort-order"])
    candidates_page = Query.parse_page(params["candidates-page"])

    {contacts, _meta} =
      Outreach.list_contacts(
        query: query,
        status: status,
        sort_by: sort_by,
        sort_order: sort_order,
        limit: 100
      )

    {candidates, candidates_meta} = list_candidate_page(candidates_page)

    socket
    |> assign(:page_id, "gtm-outreach")
    |> assign(:page_title, gettext("Outreach"))
    |> assign(:uri, parsed_uri)
    |> assign(:query, query)
    |> assign(:contacts_empty?, contacts == [])
    |> assign(:candidates_empty?, candidates == [])
    |> assign(:candidates_meta, candidates_meta)
    |> assign(:search_form, to_form(%{"query" => query}, as: :search))
    |> assign(:active_filters, active_filters)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
    |> stream(:candidates, candidates, reset: true)
    |> stream(:contacts, contacts, reset: true)
  end

  defp assign_page(socket, :show, %{"id" => id}, _uri) do
    case Outreach.get_contact(id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Contact not found."))
        |> push_navigate(to: ~p"/gtm/outreach")

      contact ->
        recommendation = Outreach.current_recommendation(contact)
        recommendation_processing = Outreach.recommendation_generation_pending?(contact)

        socket
        |> assign(:page_id, "outreach-contact")
        |> assign(:page_title, contact.full_name)
        |> assign(:contact, contact)
        |> assign_recommendation(recommendation)
        |> assign(:recommendation_processing, recommendation_processing)
        |> assign(:recommendation_notice, nil)
        |> assign(:events_empty?, contact.events == [])
        |> assign(:event_form, event_form())
        |> assign(:screenshot_processing, false)
        |> assign(:screenshot_error, nil)
        |> assign(:staged_screenshots, [])
        |> stream(:events, contact.events, reset: true)
        |> maybe_schedule_recommendation_poll(recommendation_processing)
    end
  end

  defp persist_event(socket, attrs) do
    case Outreach.record_event(socket.assigns.contact, attrs, socket.assigns.current_user) do
      {:ok, _event, contact} ->
        recommendation = Outreach.current_recommendation(contact)

        {:noreply,
         socket
         |> assign(:contact, contact)
         |> assign_recommendation(recommendation)
         |> assign(:events_empty?, contact.events == [])
         |> assign(:event_form, event_form())
         |> assign(:screenshot_processing, false)
         |> assign(:staged_screenshots, [])
         |> assign(:screenshot_error, nil)
         |> push_event("set-note-body", %{body: ""})
         |> stream(:events, contact.events, reset: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :event_form, to_form(changeset, as: :event))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not record the outreach activity."))}
    end
  end

  attr :contacts, :any, required: true
  attr :contacts_empty?, :boolean, required: true
  attr :candidates, :any, required: true
  attr :candidates_empty?, :boolean, required: true
  attr :candidates_meta, :any, required: true
  attr :search_form, :map, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true
  attr :sort_by, :string, default: nil
  attr :sort_order, :string, required: true
  attr :uri, URI, required: true
  attr :candidate_result, :string, default: nil

  defp contacts_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Outreach")}</h1>
        <p data-part="description">
          {gettext(
            "Move from a thoughtful connection request into a real conversation, while keeping every touch in one history."
          )}
        </p>
      </div>
    </div>

    <p :if={@candidate_result} id="candidate-action-result" data-part="sync-result">
      {@candidate_result}
    </p>

    <.card title={gettext("Candidates")} icon="search" data-part="outreach-candidates-card">
      <.card_section data-part="outreach-candidates-section">
        <div id="outreach-candidates-table-region" data-part="outreach-table-region">
          <.table
            id={
              if(@candidates_empty?,
                do: "outreach-candidates-empty-table",
                else: "outreach-candidates-table"
              )
            }
            rows={if(@candidates_empty?, do: [], else: @candidates)}
          >
            <:col :let={{_dom_id, candidate}} label={gettext("Candidate")}>
              <.text_and_description_cell
                label={candidate.full_name || gettext("Name unavailable")}
                description={candidate.title || gettext("No title")}
              >
                <:image>
                  <.avatar
                    id={"outreach-candidate-avatar-#{candidate.id}"}
                    name={candidate.full_name || candidate.title || "Apollo"}
                    image_href={Avatar.gravatar_url(candidate.email)}
                    size="small"
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={{_dom_id, candidate}} label={gettext("Company")}>
              <.text_and_description_cell
                label={candidate.organization_name || gettext("Company unavailable")}
                description={candidate.organization_domain || candidate_location(candidate)}
              />
            </:col>
            <:col :let={{_dom_id, candidate}} label={gettext("Segment")}>
              <.text_cell label={search_segment_label(candidate.search_segment)} />
            </:col>
            <:col :let={{_dom_id, candidate}} label={gettext("Actions")}>
              <div data-part="candidate-actions">
                <.button_dropdown
                  id={"outreach-candidate-actions-#{candidate.id}"}
                  label={gettext("Add to outreach")}
                  size="medium"
                  align="end"
                  phx-click="enroll_candidate"
                  phx-value-id={candidate.id}
                >
                  <.dropdown_item
                    id={"reject-outreach-candidate-#{candidate.id}"}
                    value="dismiss"
                    label={gettext("Dismiss")}
                    on_click="reject_candidate"
                    phx-value-id={candidate.id}
                  >
                    <:left_icon><.circle_x /></:left_icon>
                  </.dropdown_item>
                </.button_dropdown>
              </div>
            </:col>
            <:empty_state :if={@candidates_empty?}>
              <.table_empty_state
                icon="search"
                title={gettext("No candidates to review")}
                subtitle={gettext("New people from the daily discovery run will appear here.")}
              />
            </:empty_state>
          </.table>

          <.pagination_group
            :if={@candidates_meta.total_pages > 1}
            id="outreach-candidates-pagination"
            data-part="outreach-candidates-pagination"
            current_page={@candidates_meta.current_page}
            number_of_pages={@candidates_meta.total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "candidates-page", page)}" end}
          />
        </div>
      </.card_section>
    </.card>

    <.card title={gettext("Contacts")} icon="users" data-part="outreach-contacts-card">
      <.card_section data-part="outreach-contacts-section">
        <div data-part="filters">
          <.filter_dropdown
            id="outreach-filters-dropdown"
            available_filters={@available_filters}
            active_filters={@active_filters}
          />

          <div data-part="search">
            <.form id="outreach-contact-search-form" for={@search_form} phx-change="filter_contacts">
              <.text_input
                id="outreach-contact-search"
                field={@search_form[:query]}
                type="search"
                placeholder={gettext("Search by contact or company...")}
                show_suffix={false}
                phx-debounce="250"
              />
            </.form>
          </div>
        </div>

        <div :if={@active_filters != []} data-part="active-filters">
          <.active_filter :for={filter <- @active_filters} filter={filter} />
        </div>

        <div id="outreach-contacts-table-region" data-part="outreach-table-region">
          <.table
            id={
              if(@contacts_empty?,
                do: "outreach-contacts-empty-table",
                else: "outreach-contacts-table"
              )
            }
            rows={if(@contacts_empty?, do: [], else: @contacts)}
            row_navigate={fn {_dom_id, contact} -> ~p"/gtm/outreach/#{contact.id}" end}
          >
            <:col
              :let={{_dom_id, contact}}
              label={gettext("Contact")}
              patch={column_patch_sort(assigns, "full_name")}
              sort_order={@sort_by == "full_name" && @sort_order}
            >
              <.text_and_description_cell
                label={contact.full_name}
                description={contact.title || contact.email || gettext("No title")}
              >
                <:image>
                  <.avatar
                    id={"outreach-contact-avatar-#{contact.id}"}
                    name={contact.full_name}
                    image_href={Avatar.gravatar_url(contact.email)}
                    size="small"
                  />
                </:image>
              </.text_and_description_cell>
            </:col>
            <:col :let={{_dom_id, contact}} label={gettext("Account")}>
              <.text_and_description_cell
                label={contact.account.name}
                description={contact.account.primary_domain || gettext("Prospect account")}
              />
            </:col>
            <:col :let={{_dom_id, contact}} label={gettext("Stage")}>
              <.badge_cell
                label={outreach_status_label(contact.outreach_status)}
                color={outreach_status_color(contact.outreach_status)}
                style="light-fill"
              />
            </:col>
            <:col
              :let={{_dom_id, contact}}
              label={gettext("Last activity")}
              patch={column_patch_sort(assigns, "last_outreach_at")}
              sort_order={@sort_by == "last_outreach_at" && @sort_order}
            >
              <.text_cell label={format_datetime(contact.last_outreach_at)} />
            </:col>
            <:col
              :let={{_dom_id, contact}}
              label={gettext("Added")}
              patch={column_patch_sort(assigns, "outreach_enrolled_at")}
              sort_order={@sort_by == "outreach_enrolled_at" && @sort_order}
            >
              <.text_cell label={format_datetime(contact.outreach_enrolled_at)} />
            </:col>
            <:empty_state :if={@contacts_empty?}>
              <.table_empty_state
                icon="users"
                title={gettext("No outreach contacts yet")}
                subtitle={
                  gettext(
                    "Contacts discovered through Apollo and added to outreach will appear here."
                  )
                }
              />
            </:empty_state>
          </.table>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :contact, :map, required: true
  attr :events, :any, required: true
  attr :events_empty?, :boolean, required: true
  attr :event_form, :map, required: true
  attr :staged_screenshots, :list, required: true
  attr :screenshot_processing, :boolean, required: true
  attr :screenshot_error, :string, default: nil
  attr :recommendation, :map, default: nil
  attr :recommendation_form, :map, required: true
  attr :recommendation_processing, :boolean, required: true
  attr :recommendation_notice, :map, default: nil

  defp contact_view(assigns) do
    ~H"""
    <section data-part="contact-page-section">
      <div data-part="contact-header">
        <div data-part="contact-heading">
          <.avatar
            id="outreach-contact-avatar"
            name={@contact.full_name}
            image_href={Avatar.gravatar_url(@contact.email)}
            size="large"
          />
          <div data-part="contact-heading-copy">
            <h1 data-part="contact-name">{@contact.full_name}</h1>
            <div data-part="contact-meta">
              <span>{@contact.title}</span>
              <span :if={@contact.title && @contact.account.name}>·</span>
              <.link navigate={~p"/sales/accounts/#{@contact.account.id}"}>
                {@contact.account.name}
              </.link>
            </div>
          </div>
        </div>

        <div data-part="contact-actions">
          <.button
            :if={@contact.linkedin_url}
            id="outreach-contact-linkedin"
            label={gettext("Open LinkedIn")}
            variant="secondary"
            href={@contact.linkedin_url}
            target="_blank"
            rel="noreferrer"
          >
            <:icon_right><.external_link /></:icon_right>
          </.button>
        </div>
      </div>

      <section data-part="contact-layout">
        <div data-part="contact-main">
          <.card
            title={gettext("Next step")}
            icon="bulb"
            data-part="next-step-card"
          >
            <.next_step
              contact={@contact}
              recommendation={@recommendation}
              recommendation_form={@recommendation_form}
              recommendation_processing={@recommendation_processing}
              recommendation_notice={@recommendation_notice}
            />
          </.card>

          <.card title={gettext("History")} icon="history" data-part="contact-history-card">
            <.card_section data-part="timeline-section">
              <div id="outreach-contact-events" phx-update="stream" data-part="timeline">
                <div :for={{dom_id, event} <- @events} id={dom_id} data-part="timeline-item">
                  <div data-part="timeline-marker"><span></span></div>
                  <div data-part="timeline-content">
                    <div data-part="timeline-heading">
                      <.link
                        :if={event.url}
                        href={event.url}
                        target="_blank"
                        rel="noreferrer"
                        data-part="event-title"
                      >
                        {event.title}
                      </.link>
                      <span :if={!event.url} data-part="event-title">{event.title}</span>
                      <span data-part="event-time">{format_datetime(event.occurred_at)}</span>
                    </div>
                    <p :if={event.metadata["subject"]} data-part="event-subject">
                      <span>{gettext("Subject:")}</span> {event.metadata["subject"]}
                    </p>
                    <div :if={event.body} data-part="event-body">{event_body_html(event.body)}</div>
                    <span data-part="event-meta">
                      {event_source_label(event.source, event.author)}
                    </span>
                  </div>
                </div>
              </div>

              <div :if={@events_empty?} id="outreach-events-empty" data-part="empty-state">
                <span data-part="empty-title">{gettext("No outreach activity yet")}</span>
                <span data-part="empty-description">
                  {gettext("Start with a connection request that has no sales pitch.")}
                </span>
              </div>
            </.card_section>
          </.card>
        </div>

        <aside data-part="contact-side">
          <.card title={gettext("Add activity")} icon="circle_plus" data-part="activity-form-card">
            <.card_section data-part="activity-form-section">
              <.form
                id="outreach-event-form"
                for={@event_form}
                phx-submit="record_event"
                phx-hook="ScreenshotPaste"
              >
                <div data-part="activity-form-fields">
                  <div data-part="activity-kind-field">
                    <.label label={gettext("Activity")} required />
                    <.select
                      id="outreach-event-kind"
                      name="event[kind]"
                      label={gettext("Select activity")}
                      value={@event_form[:kind].value}
                    >
                      <:item
                        :for={kind <- Outreach.event_kinds()}
                        value={kind}
                        label={event_kind_label(kind)}
                      />
                    </.select>
                  </div>

                  <div data-part="activity-outcome-field">
                    <.label label={gettext("Response outcome")} />
                    <.select
                      id="outreach-event-response-outcome"
                      name="event[response_outcome]"
                      label={gettext("Unclassified response")}
                      value=""
                      hint={gettext("Use this when adding a received message so Atlas can learn.")}
                    >
                      <:item
                        :for={outcome <- Outreach.response_outcomes()}
                        value={outcome}
                        label={response_outcome_label(outcome)}
                      />
                    </.select>
                  </div>

                  <.text_area
                    id="outreach-event-body"
                    field={@event_form[:body]}
                    label={gettext("Message or note")}
                    placeholder={
                      gettext(
                        "Paste the message or a screenshot so the conversation stays understandable later."
                      )
                    }
                    rows={5}
                    max_length={4000}
                  />

                  <div
                    :if={@staged_screenshots != []}
                    id="outreach-screenshot-tray"
                    data-part="timeline-screenshot-tray"
                    aria-label={gettext("Staged screenshots")}
                  >
                    <div data-part="timeline-screenshot-tray-header">
                      <span data-part="timeline-screenshot-count">
                        {Screenshots.count_label(length(@staged_screenshots))}
                      </span>
                      <button
                        id="outreach-screenshot-clear"
                        data-part="timeline-screenshot-clear"
                        type="button"
                        phx-click="clear_staged_screenshots"
                        disabled={@screenshot_processing}
                      >
                        {gettext("Clear")}
                      </button>
                    </div>
                    <div data-part="timeline-screenshot-list">
                      <div
                        :for={screenshot <- @staged_screenshots}
                        id={"outreach-staged-#{screenshot.id}"}
                        data-part="timeline-screenshot"
                      >
                        <img
                          data-part="timeline-screenshot-preview"
                          src={Screenshots.preview_src(screenshot)}
                          alt={gettext("Pasted screenshot")}
                        />
                        <button
                          id={"outreach-remove-#{screenshot.id}"}
                          data-part="timeline-screenshot-remove"
                          type="button"
                          phx-click="remove_staged_screenshot"
                          phx-value-id={screenshot.id}
                          aria-label={gettext("Remove screenshot")}
                          disabled={@screenshot_processing}
                        >
                          <.icon name="close" />
                        </button>
                      </div>
                    </div>
                  </div>

                  <div
                    :if={@screenshot_processing}
                    id="outreach-screenshot-processing"
                    data-part="timeline-note-processing"
                    aria-live="polite"
                  >
                    <span data-part="timeline-note-spinner" aria-hidden="true"></span>
                    <span>
                      {Screenshots.analysis_label(length(@staged_screenshots))}
                    </span>
                  </div>

                  <div
                    :if={@screenshot_error}
                    id="outreach-screenshot-error"
                    data-part="timeline-note-error"
                    role="alert"
                  >
                    {@screenshot_error}
                  </div>

                  <div data-part="timeline-note-actions">
                    <.button
                      :if={@screenshot_error && @staged_screenshots != []}
                      id="outreach-screenshot-retry"
                      label={gettext("Try screenshot again")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="draft_from_screenshots"
                      disabled={@screenshot_processing}
                    >
                      <:icon_left><.icon name="photo" /></:icon_left>
                    </.button>
                    <.button
                      id="outreach-event-submit"
                      label={gettext("Add to history")}
                      size="small"
                      type="submit"
                      disabled={@screenshot_processing}
                    />
                  </div>
                </div>
              </.form>
            </.card_section>
          </.card>

          <.card title={gettext("Contact details")} icon="user" data-part="contact-details-card">
            <.card_section data-part="contact-details-section">
              <div data-part="detail-row">
                <span data-part="detail-label">{gettext("Email")}</span>
                <span data-part="detail-value">{@contact.email || gettext("Not available")}</span>
              </div>
              <div data-part="detail-row">
                <span data-part="detail-label">{gettext("Source")}</span>
                <span data-part="detail-value">{source_label(@contact.source)}</span>
              </div>
              <div data-part="detail-row">
                <span data-part="detail-label">{gettext("Added")}</span>
                <span data-part="detail-value">{format_datetime(@contact.outreach_enrolled_at)}</span>
              </div>
            </.card_section>
          </.card>
        </aside>
      </section>
    </section>
    """
  end

  attr :contact, :map, required: true
  attr :recommendation, :map, default: nil
  attr :recommendation_form, :map, required: true
  attr :recommendation_processing, :boolean, required: true
  attr :recommendation_notice, :map, default: nil

  defp next_step(assigns) do
    ~H"""
    <.card_section id="outreach-next-step" data-part="next-step-section">
      <p :if={@recommendation} data-part="next-step-caption">
        {gettext("Prepared from your history and relevant public sources")}
      </p>

      <div
        :if={@recommendation_processing}
        id="outreach-recommendation-processing"
        data-part="recommendation-processing"
        aria-live="polite"
      >
        <span data-part="timeline-note-spinner" aria-hidden="true"></span>
        <div data-part="recommendation-processing-copy">
          <span data-part="recommendation-processing-title">
            {gettext("Researching public signals")}
          </span>
          <span>
            {gettext(
              "Checking company sources, personal sites, authored work, and GitHub. You can safely leave this page."
            )}
          </span>
        </div>
      </div>

      <p
        :if={@recommendation_notice}
        id="outreach-recommendation-notice"
        data-part="recommendation-notice"
        data-status={@recommendation_notice.status}
        aria-live="polite"
      >
        {@recommendation_notice.message}
      </p>

      <div :if={@recommendation} id="outreach-recommendation" data-part="recommendation">
        <div data-part="recommendation-heading">
          <span data-part="recommendation-title">{@recommendation.title}</span>
          <span data-part="recommendation-due">
            {recommendation_due_label(@recommendation)}
          </span>
        </div>
        <p data-part="next-step-guidance">{@recommendation.guidance}</p>
        <div data-part="recommendation-reasoning">
          <span data-part="recommendation-label">{gettext("Why now")}</span>
          <p data-part="recommendation-rationale">{@recommendation.rationale}</p>
        </div>
        <div
          :if={recommendation_message_form?(@recommendation)}
          data-part="recommendation-draft"
        >
          <.form
            id="outreach-recommendation-completion-form"
            for={@recommendation_form}
            phx-submit="complete_recommendation"
          >
            <input
              id="outreach-recommendation-id"
              type="hidden"
              name="recommendation_id"
              value={@recommendation.id}
            />
            <.text_input
              :if={recommendation_subject_form?(@recommendation)}
              {%{maxlength: 120}}
              id="outreach-recommendation-sent-subject"
              field={@recommendation_form[:sent_subject]}
              label={gettext("Subject")}
              required
            />
            <.text_area
              id="outreach-recommendation-sent-message"
              field={@recommendation_form[:sent_message]}
              label={recommendation_message_label(@recommendation)}
              hint={
                gettext("Edit this to match what you actually send. Atlas learns from this version.")
              }
              rows={5}
              max_length={recommendation_message_max_length(@recommendation)}
              required
            />
            <.button
              id="complete-outreach-recommendation"
              label={recommendation_completion_label(@recommendation)}
              size="small"
              type="submit"
            />
          </.form>
        </div>
        <div data-part="recommendation-meta">
          <span>{recommendation_action_label(@recommendation.action_type)}</span>
          <span>·</span>
          <span>{recommendation_confidence_label(@recommendation.confidence)}</span>
        </div>

        <div data-part="recommendation-actions">
          <.button
            :if={!recommendation_message_form?(@recommendation)}
            id="complete-outreach-recommendation"
            label={gettext("Mark done")}
            phx-click="complete_recommendation"
            phx-value-id={@recommendation.id}
            size="small"
          />
          <.button
            id="refresh-outreach-recommendation"
            label={gettext("Try another")}
            phx-click="refresh_recommendation"
            variant="secondary"
            size="small"
            disabled={@recommendation_processing}
          />
          <.button
            id="dismiss-outreach-recommendation"
            label={gettext("Dismiss")}
            phx-click="dismiss_recommendation"
            phx-value-id={@recommendation.id}
            variant="secondary"
            size="small"
          />
        </div>
      </div>

      <div
        :if={!@recommendation && !@recommendation_processing}
        id="outreach-recommendation-empty"
        data-part="recommendation-empty"
      >
        <div data-part="recommendation-empty-icon" aria-hidden="true">
          <.search />
        </div>
        <div data-part="recommendation-empty-copy">
          <span data-part="recommendation-empty-title">
            <%= if @contact.outreach_recommendations_checked_at do %>
              {gettext("Search for a stronger signal")}
            <% else %>
              {gettext("Research public signals")}
            <% end %>
          </span>
          <p data-part="next-step-guidance">
            {gettext(
              "Atlas will verify the person and look across company sources, personal sites, authored work, and GitHub before suggesting one useful action."
            )}
          </p>
        </div>
        <div data-part="recommendation-empty-action">
          <.button
            id="generate-outreach-recommendation"
            label={gettext("Research person")}
            phx-click="refresh_recommendation"
            size="small"
          >
            <:icon_left><.search /></:icon_left>
          </.button>
        </div>
      </div>
    </.card_section>
    """
  end

  defp event_form do
    Outreach.change_event()
    |> to_form(as: :event)
  end

  defp assign_recommendation(socket, recommendation) do
    socket
    |> assign(:recommendation, recommendation)
    |> assign(:recommendation_form, recommendation_form(recommendation))
  end

  # Rebuilding the form resets the textarea to the stored draft, so leave it
  # alone when the poll came back with the suggestion the operator is editing.
  defp assign_recommendation(socket, %{id: id} = recommendation, previous_id) when id == previous_id do
    assign(socket, :recommendation, recommendation)
  end

  defp assign_recommendation(socket, recommendation, _previous_id), do: assign_recommendation(socket, recommendation)

  defp recommendation_form(%{draft_subject: draft_subject, draft_message: draft_message}) do
    to_form(
      %{"sent_subject" => draft_subject || "", "sent_message" => draft_message || ""},
      as: :completion
    )
  end

  defp recommendation_form(_recommendation) do
    to_form(%{"sent_subject" => "", "sent_message" => ""}, as: :completion)
  end

  defp recommendation_message_form?(%{recommended_event_kind: "connection_requested", draft_message: draft_message}),
    do: is_binary(draft_message) and draft_message != ""

  defp recommendation_message_form?(%{recommended_event_kind: "message_sent"}), do: true
  defp recommendation_message_form?(_recommendation), do: false

  defp recommendation_subject_form?(%{action_type: "inmail"}), do: true
  defp recommendation_subject_form?(_recommendation), do: false

  defp recommendation_message_label(%{recommended_event_kind: "connection_requested"}),
    do: gettext("Connection request message")

  defp recommendation_message_label(%{action_type: "inmail"}), do: gettext("InMail message")

  defp recommendation_message_label(_recommendation), do: gettext("Message to send")

  defp recommendation_message_max_length(%{recommended_event_kind: "connection_requested"}), do: 200
  defp recommendation_message_max_length(_recommendation), do: 1_500

  defp recommendation_completion_label(%{recommended_event_kind: "connection_requested"}),
    do: gettext("Mark request sent")

  defp recommendation_completion_label(%{action_type: "inmail"}), do: gettext("Mark InMail sent")

  defp recommendation_completion_label(_recommendation), do: gettext("Mark sent")

  defp recommendation_due_label(%{due_at: %DateTime{} = due_at}) do
    gettext("Due %{date}", date: Calendar.strftime(due_at, "%b %-d"))
  end

  defp recommendation_due_label(_recommendation), do: gettext("When useful")

  defp recommendation_action_label("inmail"), do: gettext("InMail")

  defp recommendation_action_label(action) do
    action
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp recommendation_confidence_label(%Decimal{} = confidence) do
    percentage = confidence |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_string(:normal)
    gettext("%{percentage}% confidence", percentage: percentage)
  end

  defp recommendation_confidence_label(_confidence), do: gettext("Evidence-based suggestion")

  defp maybe_schedule_recommendation_poll(socket, true), do: start_recommendation_poll(socket)
  defp maybe_schedule_recommendation_poll(socket, false), do: socket

  defp start_recommendation_poll(socket) do
    deadline = System.monotonic_time(:millisecond) + @recommendation_poll_timeout_ms

    socket
    |> assign(:recommendation_poll_deadline, deadline)
    |> assign(:recommendation_notice, nil)
    |> schedule_recommendation_poll()
  end

  defp schedule_recommendation_poll(socket) do
    if connected?(socket), do: Process.send_after(self(), :poll_recommendation, @recommendation_poll_ms)
    socket
  end

  # A job can sit in `retryable` across several backoffs, and jobs enqueued by
  # enrollment or the periodic sweep put the card into the processing state too.
  # Give up after the deadline so the card always returns to something the
  # operator can act on instead of spinning indefinitely.
  defp keep_polling_recommendation(socket) do
    deadline = socket.assigns.recommendation_poll_deadline

    if is_integer(deadline) and System.monotonic_time(:millisecond) >= deadline do
      socket
      |> assign(:recommendation_processing, false)
      |> assign(:recommendation_poll_deadline, nil)
      |> assign_recommendation_notice(
        :info,
        gettext("Atlas is still preparing a next step. Reload this page in a moment to see it.")
      )
    else
      schedule_recommendation_poll(socket)
    end
  end

  defp finish_recommendation_poll(socket, contact_id, status) do
    case Outreach.get_contact(contact_id) do
      nil ->
        socket
        |> put_flash(:error, gettext("Contact not found."))
        |> push_navigate(to: ~p"/gtm/outreach")

      contact ->
        previous_id = recommendation_id(socket.assigns.recommendation)
        recommendation = Outreach.current_recommendation(contact)

        socket
        |> assign(:contact, contact)
        |> assign(:events_empty?, contact.events == [])
        |> assign(:recommendation_processing, false)
        |> assign(:recommendation_poll_deadline, nil)
        |> assign_recommendation(recommendation, previous_id)
        |> recommendation_notice(status, recommendation, previous_id)
        |> stream(:events, contact.events, reset: true)
    end
  end

  # The dashboard layout does not render flash, so the outcome of a generation
  # has to be told inside the next step card to reach anyone.
  defp recommendation_notice(socket, :failed, _recommendation, _previous_id) do
    Logger.warning("Outreach recommendation generation did not complete for contact #{socket.assigns.contact.id}")

    assign_recommendation_notice(
      socket,
      :error,
      gettext("Atlas could not prepare a next step. Check that the language model is configured, then try again.")
    )
  end

  defp recommendation_notice(socket, _status, nil, _previous_id) do
    assign_recommendation_notice(
      socket,
      :info,
      gettext("Atlas could not find a safe, useful next step in the available history or public sources.")
    )
  end

  defp recommendation_notice(socket, _status, %{id: id}, previous_id) when id == previous_id do
    assign_recommendation_notice(
      socket,
      :info,
      gettext("The current suggestion is still the strongest next step.")
    )
  end

  defp recommendation_notice(socket, _status, _recommendation, _previous_id),
    do: assign(socket, :recommendation_notice, nil)

  defp assign_recommendation_notice(socket, status, message),
    do: assign(socket, :recommendation_notice, %{status: status, message: message})

  defp recommendation_id(%{id: id}), do: id
  defp recommendation_id(_recommendation), do: nil

  defp start_screenshot_analysis(socket) do
    staged_screenshots = socket.assigns.staged_screenshots

    cond do
      socket.assigns.screenshot_processing ->
        socket

      staged_screenshots == [] ->
        socket

      true ->
        contact = socket.assigns.contact
        min_ms = @screenshot_min_processing_ms

        socket
        |> assign(:screenshot_processing, true)
        |> assign(:screenshot_error, nil)
        |> start_async(:screenshot_analysis, fn ->
          started_at = System.monotonic_time(:millisecond)

          screenshots =
            Enum.map(staged_screenshots, fn screenshot ->
              %{data: screenshot.data, media_type: screenshot.media_type}
            end)

          result =
            screenshot_note_agent().draft_note_from_screenshots(screenshots, %{
              id: contact.account.id,
              name: contact.account.name,
              contact_name: contact.full_name
            })

          elapsed = System.monotonic_time(:millisecond) - started_at
          if elapsed < min_ms, do: Process.sleep(min_ms - elapsed)
          result
        end)
    end
  end

  defp screenshot_note_agent do
    :atlas
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:screenshot_note_agent, ScreenshotNoteAgent)
  end

  defp refresh_outreach_data(socket) do
    status = active_filter_value(socket.assigns.active_filters, "stage")

    {contacts, _meta} =
      Outreach.list_contacts(
        query: socket.assigns.query,
        status: status,
        sort_by: socket.assigns.sort_by,
        sort_order: socket.assigns.sort_order,
        limit: 100
      )

    {candidates, candidates_meta} =
      socket.assigns.candidates_meta.current_page
      |> list_candidate_page()

    socket
    |> assign(:contacts_empty?, contacts == [])
    |> assign(:candidates_empty?, candidates == [])
    |> assign(:candidates_meta, candidates_meta)
    |> stream(:candidates, candidates, reset: true)
    |> stream(:contacts, contacts, reset: true)
  end

  defp list_candidate_page(page) do
    {candidates, meta} =
      Outreach.list_candidates(
        status: "pending",
        page: page,
        page_size: @candidates_page_size
      )

    if candidates == [] and meta.total_pages > 0 and page > meta.total_pages do
      Outreach.list_candidates(
        status: "pending",
        page: meta.total_pages,
        page_size: @candidates_page_size
      )
    else
      {candidates, meta}
    end
  end

  defp candidate_action_error_message(:contact_identity_required),
    do: gettext("Apollo did not return a LinkedIn profile or email for this candidate.")

  defp candidate_action_error_message(:apollo_api_key_not_configured),
    do: gettext("Apollo is not configured for this environment.")

  defp candidate_action_error_message(_reason), do: gettext("Could not update the candidate. Please try again.")

  defp candidate_location(candidate) do
    [candidate.metadata["city"], candidate.metadata["country"]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(", ")
    |> case do
      "" -> gettext("Location unavailable")
      location -> location
    end
  end

  defp search_segment_label("mobile_mid_large"), do: gettext("200–5,000 employees")
  defp search_segment_label("mobile_giants"), do: gettext("5,000+ employees")
  defp search_segment_label(segment), do: segment

  defp define_filters do
    statuses = Contact.outreach_statuses()

    [
      %Filter.Filter{
        id: "stage",
        field: :outreach_status,
        display_name: gettext("Stage"),
        type: :option,
        searchable: false,
        options: statuses,
        options_display_names: Map.new(statuses, &{&1, outreach_status_label(&1)}),
        operator: :==,
        value: nil
      }
    ]
  end

  defp active_filter_value(active_filters, id) do
    case Enum.find(active_filters, &(&1.id == id && &1.operator == :==)) do
      %{value: value} when is_binary(value) -> value
      _filter -> nil
    end
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
      |> Kernel.||("")
      |> URI.decode_query()
      |> Map.put("sort-by", column)
      |> Map.put("sort-order", next_order)

    "?" <> URI.encode_query(query_params)
  end

  defp outreach_path(query, active_filters, sort_by, sort_order) do
    params =
      %{}
      |> Query.put_present("q", Query.present_string(query))
      |> Query.put_present("sort-by", sort_by)
      |> Query.put_present("sort-order", if(sort_by, do: sort_order))
      |> Map.merge(Filter.Operations.encode_filters_to_query(active_filters))

    if map_size(params) == 0, do: ~p"/gtm/outreach", else: ~p"/gtm/outreach?#{params}"
  end

  defp normalize_sort_by(value) when value in ~w(full_name last_outreach_at outreach_enrolled_at), do: value
  defp normalize_sort_by(_value), do: nil

  defp normalize_sort_order("asc"), do: "asc"
  defp normalize_sort_order(_value), do: "desc"

  defp outreach_status_label("not_contacted"), do: gettext("Not contacted")
  defp outreach_status_label("connection_requested"), do: gettext("Connection sent")
  defp outreach_status_label("connected"), do: gettext("Connected")
  defp outreach_status_label("conversation_started"), do: gettext("Conversation started")
  defp outreach_status_label("replied"), do: gettext("Replied")
  defp outreach_status_label("interested"), do: gettext("Interested")
  defp outreach_status_label("not_interested"), do: gettext("Not interested")
  defp outreach_status_label(_status), do: gettext("Unknown")

  defp outreach_status_color("replied"), do: "success"
  defp outreach_status_color("interested"), do: "success"
  defp outreach_status_color("conversation_started"), do: "information"
  defp outreach_status_color("connected"), do: "focus"
  defp outreach_status_color("connection_requested"), do: "warning"
  defp outreach_status_color("not_interested"), do: "destructive"
  defp outreach_status_color(_status), do: "neutral"

  defp event_kind_label("connection_requested"), do: gettext("Connection request sent")
  defp event_kind_label("connection_accepted"), do: gettext("Connection accepted")
  defp event_kind_label("message_sent"), do: gettext("Message sent")
  defp event_kind_label("message_received"), do: gettext("Message received")
  defp event_kind_label("note"), do: gettext("Internal note")

  defp response_outcome_label("replied"), do: gettext("Reply, unclear intent")
  defp response_outcome_label("positive_reply"), do: gettext("Positive reply")
  defp response_outcome_label("objection"), do: gettext("Objection")
  defp response_outcome_label("not_interested"), do: gettext("Not interested")

  defp source_label("apollo"), do: "Apollo"
  defp source_label("manual"), do: gettext("Manual")
  defp source_label(source), do: source

  defp event_source_label("linkedin", _author), do: "LinkedIn"
  defp event_source_label("apollo", _author), do: "Apollo"
  defp event_source_label("web", _author), do: gettext("Public web")
  defp event_source_label(_source, %{name: name}) when is_binary(name) and name != "", do: name
  defp event_source_label(_source, %{email: email}) when is_binary(email), do: email
  defp event_source_label(_source, _author), do: gettext("Atlas")

  defp event_body_html(body) when is_binary(body) and body != "" do
    body
    |> normalize_legacy_html_emphasis()
    |> MDEx.to_html!(
      extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> raw()
  end

  defp event_body_html(_body), do: nil

  defp normalize_legacy_html_emphasis(body) do
    body
    |> String.replace(~r/<(strong|b)\b[^>]*>/i, "**")
    |> String.replace(~r/<\/(strong|b)>/i, "**")
    |> String.replace(~r/<(em|i)\b[^>]*>/i, "*")
    |> String.replace(~r/<\/(em|i)>/i, "*")
  end

  defp format_datetime(nil), do: gettext("No activity yet")
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y · %H:%M")
  defp format_datetime(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y · %H:%M")
end
