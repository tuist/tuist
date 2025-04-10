defmodule TuistWeb.NooraBillingLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora

  @impl true
  def mount(_params, _uri, socket) do
    socket = assign(socket, selected_tab: "billing")
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    Billing
    """
  end
end
