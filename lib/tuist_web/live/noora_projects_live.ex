defmodule TuistWeb.NooraProjectsLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora

  @impl true
  def mount(_params, _uri, socket) do
    socket = assign(socket, selected_tab: "projects")
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    Projects
    """
  end
end
