defmodule AtlasWeb.DemoLive do
  use AtlasWeb, :live_view

  alias Atlas.Demo

  def mount(_params, _session, socket) do
    path = if Demo.enabled?(), do: ~p"/commercial/sales/accounts", else: ~p"/"
    {:ok, redirect(socket, to: path)}
  end

  def render(assigns) do
    ~H"""
    <div />
    """
  end
end
