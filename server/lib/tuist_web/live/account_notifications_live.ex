defmodule TuistWeb.AccountNotificationsLive do
  @moduledoc """
  The signed-in user's push notification preferences and the app installations
  (devices) registered to receive them. Only shown on the user's own account.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Notifications
  alias Tuist.Push

  @kind "new_preview"

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if selected_account.user_id != current_user.id do
      raise TuistWeb.Errors.NotFoundError, dgettext("dashboard_account", "The page you are looking for doesn't exist.")
    end

    socket =
      socket
      |> assign_preferences()
      |> assign_devices()
      |> assign(:head_title, "#{dgettext("dashboard_account", "Notifications")} · #{selected_account.name} · Tuist")

    {:ok, socket}
  end

  @impl true
  # Noora's toggle only sends `checked`, so the account ID travels in the event name.
  def handle_event("toggle_account:" <> account_id, %{"checked" => checked}, socket) do
    _ =
      Notifications.update_account_preference(socket.assigns.current_user, @kind, String.to_integer(account_id), checked)

    {:noreply, assign_preferences(socket)}
  end

  def handle_event("reset_project", %{"data" => project_id}, socket) do
    _ = Notifications.update_project_preference(socket.assigns.current_user, @kind, String.to_integer(project_id), nil)
    {:noreply, assign_preferences(socket)}
  end

  def handle_event("remove_device", %{"id" => registration_id}, socket) do
    :ok = Push.remove_device(socket.assigns.current_user, registration_id)
    {:noreply, assign_devices(socket)}
  end

  defp assign_preferences(socket) do
    assign(socket, :preferences, Notifications.preferences(socket.assigns.current_user, @kind))
  end

  defp account_description(%{organization_id: nil}),
    do: dgettext("dashboard_account", "Previews of your personal projects")

  defp account_description(_account), do: dgettext("dashboard_account", "Previews of this organization's projects")

  defp assign_devices(socket) do
    assign(socket, :devices, Push.live_installations(socket.assigns.current_user.id))
  end

  defp device_name(%{device_name: nil, platform: "ios"}), do: dgettext("dashboard_account", "iOS device")
  defp device_name(%{device_name: nil}), do: dgettext("dashboard_account", "Android device")
  defp device_name(%{device_name: name}), do: name

  defp platform_label("ios"), do: "iOS"
  defp platform_label(_platform), do: "Android"
end
