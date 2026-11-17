defmodule TuistWeb.IntegrationInstallationAccountsLive do
  @moduledoc """
  The account list of the integration installation chooser, embedded in
  `TuistWeb.IntegrationInstallationController.show/2`. It re-reads the eligible accounts while the
  page is open, so an organization created in another tab, or one the user is made an admin of,
  appears without starting the installation again. Selection still posts to the controller, which
  rechecks the pending proof and authorization.
  """
  use TuistWeb, :live_view
  use Noora

  alias TuistWeb.IntegrationInstallationController

  @refresh_interval to_timeout(second: 5)

  on_mount {TuistWeb.Authentication, :ensure_authenticated}

  @impl true
  def mount(_params, %{"integration_installation_expires_at" => expires_at}, socket) do
    socket = assign(socket, expires_at: expires_at, accounts: [])
    if connected?(socket), do: schedule_refresh(socket)
    {:ok, assign_accounts(socket), layout: false}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh(socket)
    {:noreply, assign_accounts(socket)}
  end

  # The pending proof is only valid until `expires_at`, so polling stops with it.
  defp schedule_refresh(socket) do
    if System.system_time(:second) < socket.assigns.expires_at do
      Process.send_after(self(), :refresh, @refresh_interval)
    end
  end

  defp assign_accounts(socket) do
    assign(socket, accounts: IntegrationInstallationController.eligible_accounts(socket.assigns.current_user))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-part="organizations">
      <form :for={account <- @accounts} method="post" action={~p"/integrations/installation"}>
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="account_id" value={account.id} />
        <button type="submit" data-part="organization">
          <.avatar id={"installation-account-#{account.id}"} name={account.name} size="medium" />
          <span data-part="organization-details">
            <span data-part="organization-name">{account.name}</span>
            <span data-part="organization-type">
              {if account.organization_id,
                do: dgettext("dashboard_auth", "Organization"),
                else: dgettext("dashboard_auth", "Personal account")}
            </span>
          </span>
          <.chevron_right />
        </button>
      </form>
    </div>
    <span :if={@accounts == []} data-part="empty-state">
      {dgettext("dashboard_auth", "You need administrator access to connect an integration.")}
    </span>
    """
  end
end
