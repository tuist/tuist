defmodule AtlasWeb.SessionLive do
  use AtlasWeb, :live_view

  import AtlasWeb.AgentSessionComponents

  alias Atlas.Agents.Sessions

  def mount(%{"id" => id}, _session, socket) do
    case Sessions.get_session(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Agent session not found."))
         |> push_navigate(to: ~p"/admin/sessions")}

      session ->
        {:ok,
         socket
         |> assign(:page_title, short_agent(session.agent))
         |> assign(:session, session)}
    end
  end

  def render(assigns) do
    ~H"""
    <.agent_session_detail
      id="agent-session"
      session={@session}
      back_label={gettext("Back to sessions")}
      back_path={~p"/admin/sessions"}
    />
    """
  end

  defp short_agent(agent) when is_binary(agent), do: agent |> String.split(".") |> List.last()
  defp short_agent(_), do: "-"
end
