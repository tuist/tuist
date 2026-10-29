defmodule AtlasWeb.DemoLiveGuard do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Atlas.Demo
  alias AtlasWeb.Layouts

  def attach(socket) do
    if Demo.allowed_view?(socket.view) do
      {:cont,
       socket
       |> assign(:demo_mode, true)
       |> attach_hook(:demo_events, :handle_event, &handle_event/3)
       |> attach_hook(:demo_paths, :handle_params, &handle_params/3), layout: {Layouts, :demo_dashboard}}
    else
      {:halt, redirect(socket, to: "/commercial/sales/accounts")}
    end
  end

  defp handle_event(event, _params, socket) do
    if Demo.allowed_event?(socket.view, event) do
      {:cont, socket}
    else
      {:halt, put_flash(socket, :info, "This is a read-only demo. Changes, uploads, and integrations are unavailable.")}
    end
  end

  defp handle_params(_params, url, socket) do
    if Demo.dashboard_path?(URI.parse(url).path) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/commercial/sales/accounts")}
    end
  end
end
