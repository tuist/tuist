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
  # Noora's toggle only sends `checked`, so the IDs travel in the event name.
  def handle_event("toggle_account:" <> account_id, %{"checked" => checked}, socket) do
    _ =
      Notifications.update_account_preference(socket.assigns.current_user, @kind, String.to_integer(account_id), checked)

    {:noreply, assign_preferences(socket)}
  end

  # As in the apps, a project switch that matches its account's switch follows
  # the account, and one that differs overrides it.
  def handle_event("toggle_project:" <> ids, %{"checked" => checked}, socket) do
    [account_id, project_id] = ids |> String.split(":") |> Enum.map(&String.to_integer/1)

    case Enum.find(socket.assigns.preferences, &(&1.account.id == account_id)) do
      %{enabled: account_enabled} ->
        override = if checked == account_enabled, do: nil, else: checked
        _ = Notifications.update_project_preference(socket.assigns.current_user, @kind, project_id, override)

      nil ->
        :ok
    end

    {:noreply, assign_preferences(socket)}
  end

  def handle_event("toggle_open_account", %{"id" => account_id}, socket) do
    account_id = String.to_integer(account_id)
    open = if socket.assigns.open_account_id == account_id, do: nil, else: account_id
    {:noreply, assign(socket, :open_account_id, open)}
  end

  def handle_event("remove_device", %{"id" => registration_id}, socket) do
    :ok = Push.remove_device(socket.assigns.current_user, registration_id)
    {:noreply, assign_devices(socket)}
  end

  # Like the apps, only accounts with projects have anything to choose.
  defp assign_preferences(socket) do
    preferences =
      socket.assigns.current_user
      |> Notifications.preferences(@kind)
      |> Enum.reject(&(&1.projects == []))

    socket
    |> assign(:preferences, preferences)
    |> assign_new(:open_account_id, fn -> nil end)
  end

  # "On" or "Off" when every project agrees, "Custom" otherwise.
  defp account_summary(%{projects: projects}) do
    cond do
      Enum.all?(projects, & &1.enabled) -> dgettext("dashboard_account", "On")
      Enum.all?(projects, &(not &1.enabled)) -> dgettext("dashboard_account", "Off")
      true -> dgettext("dashboard_account", "Custom")
    end
  end

  defp account_kind(%{organization_id: nil}), do: dgettext("dashboard_account", "Personal")
  defp account_kind(_account), do: dgettext("dashboard_account", "Organization")

  attr :preference, :map, required: true
  attr :all_label, :string, required: true

  defp account_projects(%{preference: %{account: account}} = assigns) do
    assigns = assign(assigns, :account, account)

    ~H"""
    <div
      id={"new-previews-account-projects-#{@account.id}"}
      data-part="account-projects"
      data-enabled={to_string(@preference.enabled)}
    >
      <%!-- Noora's toggle only reads `checked` when it mounts, so the state is part of
      the id: a switch remounts when a change elsewhere, such as All projects, moves it. --%>
      <.toggle
        id={"new-previews-account-toggle-#{@account.id}-#{@preference.enabled}"}
        label={@all_label}
        description={dgettext("dashboard_account", "New projects follow this setting.")}
        checked={@preference.enabled}
        data-on-checked-change={"toggle_account:#{@account.id}"}
      />
      <div data-part="projects">
        <span data-part="projects-label">{dgettext("dashboard_account", "Projects")}</span>
        <div
          :for={%{project: project, enabled: enabled} <- @preference.projects}
          id={"new-previews-project-#{project.id}"}
          data-enabled={to_string(enabled)}
        >
          <.toggle
            id={"new-previews-project-toggle-#{project.id}-#{enabled}"}
            label={project.name}
            checked={enabled}
            data-on-checked-change={"toggle_project:#{@account.id}:#{project.id}"}
          />
        </div>
      </div>
    </div>
    """
  end

  defp assign_devices(socket) do
    assign(socket, :devices, Push.live_installations(socket.assigns.current_user.id))
  end

  defp device_name(%{device_name: nil, platform: "ios"}), do: dgettext("dashboard_account", "iOS device")
  defp device_name(%{device_name: nil}), do: dgettext("dashboard_account", "Android device")
  defp device_name(%{device_name: name}), do: name

  defp platform_label("ios"), do: "iOS"
  defp platform_label(_platform), do: "Android"
end
