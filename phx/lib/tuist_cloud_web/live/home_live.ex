defmodule TuistCloudWeb.HomeLive do
  use TuistCloudWeb, :live_view

  def render(assigns) do
    ~H"""
    Home
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
