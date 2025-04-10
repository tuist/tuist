defmodule TuistWeb.NooraSettingsLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora

  @impl true
  def mount(_params, _uri, socket) do
    socket = assign(socket, selected_tab: "settings")
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    Settings
    """
  end
end
