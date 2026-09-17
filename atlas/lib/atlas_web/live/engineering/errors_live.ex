defmodule AtlasWeb.Engineering.ErrorsLive do
  @moduledoc """
  Error tracking dashboard. Ported from Hive's `HiveWeb.ErrorsLive.Index`,
  `.Show`, `.Event`, and `.EventPanels` down to the core interactions:
  browse issues, show an issue's metadata + recent events, and drill into
  a single event's payload.

  Hive's Grafana annotations, alert-rule side panels, and AI-summary
  panes are out of scope for this port — they can come back once Atlas
  grows equivalents.
  """

  use AtlasWeb, :live_view

  alias Atlas.Engineering.Errors

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Errors"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    status = param_status(params["status"])
    project_id = params["project_id"]

    issues =
      Errors.list_issues(
        project_id: project_id,
        status: status,
        search: params["q"],
        limit: 50
      )

    socket
    |> assign(:issues, issues)
    |> assign(:filter_status, status || :all)
    |> assign(:query, params["q"] || "")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case Errors.fetch_issue(id) do
      {:ok, issue} ->
        events = safe_list_events(issue.id)

        socket
        |> assign(:issue, issue)
        |> assign(:events, events)
        |> assign(:page_title, issue.title)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Issue not found."))
        |> push_navigate(to: ~p"/engineering/errors")
    end
  end

  defp apply_action(socket, :event, %{"id" => issue_id, "event_id" => event_id}) do
    case Errors.fetch_issue(issue_id) do
      {:ok, issue} ->
        event = Errors.fetch_event(issue.id, event_id)

        socket
        |> assign(:issue, issue)
        |> assign(:event, event)
        |> assign(:page_title, issue.title)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Issue not found."))
        |> push_navigate(to: ~p"/engineering/errors")
    end
  end

  defp param_status("unresolved"), do: :unresolved
  defp param_status("resolved"), do: :resolved
  defp param_status("ignored"), do: :ignored
  defp param_status(_), do: nil

  defp safe_list_events(issue_id) do
    Errors.list_events_for_issue(issue_id, limit: 25)
  rescue
    _ -> []
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Errors")}</h1>

      <div class="mt-6 space-y-2">
        <%= for issue <- @issues do %>
          <div class="border rounded p-4 hover:bg-neutral-50">
            <div class="flex items-center justify-between">
              <.link navigate={~p"/engineering/errors/#{issue.id}"} class="font-medium">
                {issue.title}
              </.link>
              <span class="text-xs text-neutral-400">{issue.status}</span>
            </div>
            <p :if={issue.culprit} class="text-sm text-neutral-500 mt-1">{issue.culprit}</p>
            <p class="text-xs text-neutral-400 mt-2">
              {gettext("Events")}: {issue.event_count} &middot; {gettext("Last seen")}: {relative_time(
                issue.last_seen
              )}
            </p>
          </div>
        <% end %>

        <p :if={@issues == []} class="text-sm text-neutral-500">
          {gettext("No issues match these filters.")}
        </p>
      </div>
    </div>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-8 space-y-6">
      <div>
        <.link navigate={~p"/engineering/errors"} class="text-sm text-neutral-500">
          &larr; {gettext("Errors")}
        </.link>
        <h1 class="text-2xl font-semibold mt-2">{@issue.title}</h1>
        <p :if={@issue.culprit} class="text-neutral-500">{@issue.culprit}</p>
        <p class="text-xs text-neutral-400 mt-2">
          {@issue.status} &middot; {@issue.level} &middot; {@issue.event_count} {gettext("events")}
        </p>
      </div>

      <section>
        <h2 class="text-lg font-medium">{gettext("Recent events")}</h2>
        <ul class="mt-2 space-y-1">
          <%= for event <- @events do %>
            <li class="text-sm">
              <.link navigate={~p"/engineering/errors/#{@issue.id}/events/#{event.event_id}"}>
                {event.timestamp} &middot; {event.exception_type}
              </.link>
            </li>
          <% end %>
          <li :if={@events == []} class="text-sm text-neutral-500">
            {gettext("No events yet or ClickHouse disabled on this instance.")}
          </li>
        </ul>
      </section>
    </div>
    """
  end

  def render(%{live_action: :event} = assigns) do
    ~H"""
    <div class="p-8 space-y-6">
      <div>
        <.link navigate={~p"/engineering/errors/#{@issue.id}"} class="text-sm text-neutral-500">
          &larr; {@issue.title}
        </.link>
      </div>

      <section :if={@event}>
        <h2 class="text-lg font-medium">{@event.exception_type}: {@event.exception_value}</h2>
        <p class="text-xs text-neutral-400 mt-1">
          {@event.timestamp} &middot; {@event.level} &middot; {@event.environment}
        </p>

        <pre class="mt-4 bg-neutral-50 border rounded p-3 text-xs overflow-x-auto"><%= inspect(@event.payload, pretty: true) %></pre>
      </section>

      <p :if={is_nil(@event)} class="text-sm text-neutral-500">
        {gettext("Event not found.")}
      </p>
    </div>
    """
  end

  defp relative_time(nil), do: ""
  defp relative_time(%DateTime{} = dt), do: DateTime.to_string(dt)
end
