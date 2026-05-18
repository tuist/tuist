defmodule TuistWeb.WebhookEndpointForm do
  @moduledoc """
  Shared form body for creating and editing a webhook endpoint.

  Used by `TuistWeb.WebhooksLive` (Add endpoint modal) and
  `TuistWeb.WebhookLive` (Edit endpoint modal). The form covers the name,
  URL, and event-subscription checkboxes; the surrounding `<.modal>` shell,
  the footer actions, and the create-modal's secret-disclosure step stay
  with each caller so they can branch on their own state machine.

  Callers pass the assigns to bind against plus the phx-click event names
  to wire up. IDs on the inputs and checkboxes are derived from
  `id_prefix` so two instances can coexist on the same page without
  colliding (e.g. the edit modal sitting on a detail page).
  """
  use TuistWeb, :live_component
  use Noora

  import Noora.CheckboxControl

  attr :id_prefix, :string,
    required: true,
    doc: ~s{Prefix used for the input and checkbox DOM ids (e.g. "webhook" or "webhook-edit").}

  attr :event_groups, :list, required: true, doc: "The event catalog, grouped by resource."
  attr :name, :string, required: true, doc: "Current value of the name input."
  attr :url, :string, required: true, doc: "Current value of the endpoint URL input."

  attr :event_types, :list,
    required: true,
    doc: "Currently-selected event type strings."

  attr :error, :string, default: nil, doc: "Top-of-form error message; hidden when nil."

  attr :events_label, :string,
    required: true,
    doc: ~s{Label above the event checkboxes (e.g. "Events to listen for" or "Selected events").}

  attr :on_name_change, :string, required: true, doc: "phx-keyup event for the name input."
  attr :on_url_change, :string, required: true, doc: "phx-keyup event for the URL input."

  attr :on_toggle_event_type, :string,
    required: true,
    doc: "phx-click event for individual event-type checkboxes."

  attr :on_toggle_event_group, :string,
    required: true,
    doc: "phx-click event for the per-group select-all checkbox."

  def webhook_endpoint_form(assigns) do
    ~H"""
    <div class="webhook-endpoint-form">
      <.alert
        :if={@error}
        status="error"
        type="secondary"
        size="small"
        title={@error}
      />
      <.text_input
        id={"#{@id_prefix}-endpoint-name"}
        name="name"
        type="basic"
        label={dgettext("dashboard_account", "Name")}
        sublabel={dgettext("dashboard_account", "How this endpoint will be listed in the table.")}
        value={@name}
        placeholder={dgettext("dashboard_account", "Webhook name")}
        phx-keyup={@on_name_change}
        phx-debounce="300"
      />
      <.text_input
        id={"#{@id_prefix}-endpoint-url"}
        name="url"
        type="basic"
        label={dgettext("dashboard_account", "Endpoint URL")}
        sublabel={
          dgettext("dashboard_account", "HTTPS only. Tuist will POST signed JSON envelopes here.")
        }
        value={@url}
        placeholder="https://example.com/tuist-webhook"
        phx-keyup={@on_url_change}
        phx-debounce="300"
      />
      <div data-part="event-types">
        <span data-part="label">{@events_label}</span>
        <span data-part="sublabel">
          {dgettext(
            "dashboard_account",
            "Only the selected events trigger a delivery to this endpoint."
          )}
        </span>
        <div :for={group <- @event_groups} data-part="event-group">
          <h3 data-part="event-group-label">{group.label}</h3>
          <div data-part="event-checkbox-list">
            <label
              id={"#{@id_prefix}-event-group-#{group.key}"}
              data-part="event-checkbox"
              data-role="select-all"
              phx-click={@on_toggle_event_group}
              phx-value-data={group.key}
            >
              <.checkbox_control
                checked={all_group_events_selected?(group, @event_types)}
                indeterminate={group_partially_selected?(group, @event_types)}
              />
              <div data-part="body">
                <span data-part="label">
                  {dgettext("dashboard_account", "Select all %{group} events", group: group.label)}
                </span>
              </div>
            </label>
            <label
              :for={event <- group.events}
              id={"#{@id_prefix}-event-#{event.type}"}
              data-part="event-checkbox"
              phx-click={@on_toggle_event_type}
              phx-value-data={event.type}
            >
              <.checkbox_control checked={event.type in @event_types} />
              <div data-part="body">
                <%!-- Render the canonical event type as the label — same string --%>
                <%!-- that lands in the `type` field of the webhook payload, so --%>
                <%!-- the UI and receiver code stay in sync. --%>
                <code data-part="label">{event.type}</code>
                <span data-part="description">{event.description}</span>
              </div>
            </label>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Returns true if every event in `group` is in the `selected` list.
  Drives the group-level "Select all" checkbox state.
  """
  def all_group_events_selected?(group, selected), do: Enum.all?(group.events, &(&1.type in selected))

  @doc """
  Returns true when some but not all events in `group` are selected — the
  group checkbox renders in its indeterminate state.
  """
  def group_partially_selected?(group, selected) do
    types = Enum.map(group.events, & &1.type)
    selected_count = Enum.count(types, &(&1 in selected))
    selected_count > 0 and selected_count < length(types)
  end
end
