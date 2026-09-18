defmodule AtlasWeb.SessionsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.AgentSessionComponents
  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Agents.Sessions
  alias AtlasWeb.Utilities.Query

  @page_size 20

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Sessions"))}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    page = Query.parse_page(params["page"])

    {sessions, sessions_meta} = Sessions.list_sessions(page: page, page_size: @page_size)

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:sessions, sessions)
     |> assign(:sessions_meta, sessions_meta)
     |> assign(:sessions_page, page)}
  end

  def render(assigns) do
    ~H"""
    <div id="agent-sessions">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Sessions")}</h1>
          <p data-part="description">
            {gettext(
              "Audit trail of every Condukt-driven agent run: prompt, tool calls, and outcome."
            )}
          </p>
        </div>
      </div>

      <.card title={gettext("Recent runs")} icon="message_circle" data-part="sessions-card">
        <.card_section data-part="sessions-table-section">
          <.agent_sessions_table
            id="agent-sessions-table"
            sessions={@sessions}
            row_navigate={fn session -> ~p"/admin/sessions/#{session.id}" end}
          />
          <.pagination_group
            :if={@sessions_meta.total_pages > 1}
            current_page={@sessions_page}
            number_of_pages={@sessions_meta.total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "page", page)}" end}
          />
        </.card_section>
      </.card>
    </div>
    """
  end
end
