defmodule TuistWeb.Components.AmpIntegration do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Accounts.Account
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes.AmpIntegrations
  alias TuistWeb.Errors.UnauthorizedError

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns) |> assign(error: nil, editing: false, confirm_disconnect: false, form_version: 0)
    {:ok, load(socket)}
  end

  @impl true
  def handle_event("edit", _, socket), do: {:noreply, socket |> load() |> assign(editing: true, error: nil)}

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing: false, confirm_disconnect: false, error: nil)}

  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}
  def handle_event("confirm-disconnect", _, socket), do: {:noreply, socket |> load() |> assign(confirm_disconnect: true)}

  def handle_event("save", %{"provider_token" => token}, socket) do
    case AmpIntegrations.connect(socket.assigns.account.id, socket.assigns.current_user, token) do
      {:ok, _} ->
        socket = socket |> load() |> assign(editing: false, error: nil, form_version: socket.assigns.form_version + 1)
        {:noreply, socket}

      {:error, _} ->
        # Never assign the submitted token or its changeset to the LiveView.
        {:noreply,
         assign(socket,
           error:
             dgettext(
               "dashboard_integrations",
               "Could not save the connection. Check your provider token, account permissions, and whether this provider is already connected to another account."
             )
         )}
    end
  end

  def handle_event("disconnect", _, socket) do
    case AmpIntegrations.disconnect(socket.assigns.account.id, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> load() |> assign(confirm_disconnect: false, editing: false, error: nil)}

      _ ->
        {:noreply,
         assign(socket,
           error: dgettext("dashboard_integrations", "You no longer have permission to disconnect this integration.")
         )}
    end
  end

  defp load(socket) do
    account = Repo.get!(Account, socket.assigns.account.id)

    if Authorization.authorize(:account_update, socket.assigns.current_user, account) != :ok do
      raise UnauthorizedError
    end

    integration = account.id |> AmpIntegrations.get() |> AmpIntegrations.public_status()
    assign(socket, account: account, integration: integration, available: FeatureFlags.sandboxes_enabled?(account))
  end

  defp status(nil), do: dgettext("dashboard_integrations", "Not connected")
  defp status(%{status: :pending}), do: dgettext("dashboard_integrations", "Starting provider")
  defp status(%{status: :running}), do: dgettext("dashboard_integrations", "Provider running")
  defp status(%{status: :error}), do: dgettext("dashboard_integrations", "Needs attention")
  defp status(%{status: :disconnecting}), do: dgettext("dashboard_integrations", "Disconnecting")
  defp status(%{status: :disconnected}), do: dgettext("dashboard_integrations", "Disconnected")
  defp status(%{status: :suspended}), do: dgettext("dashboard_integrations", "Suspended")

  @impl true
  def render(assigns) do
    ~H"""
    <section
      hidden={not @available and is_nil(@integration)}
      id={@id}
      data-part="amp-card-section"
      class="noora-card__section"
    >
      <div data-part="header">
        <div data-part="heading">
          <span data-part="title">Amp</span>
          <span data-part="status">{status(@integration)}</span>
        </div>
        <p data-part="subtitle">
          {dgettext(
            "dashboard_integrations",
            "Run your Amp workspace’s Orbs on Tuist sandboxes. Your files and processes are preserved when an Orb pauses."
          )}
        </p>
        <a href="https://ampcode.com/docs/orbs/self-hosted" target="_blank" rel="noopener noreferrer">{dgettext(
          "dashboard_integrations",
          "Amp setup guide"
        )}</a>
      </div>
      <div data-part="content">
        <.alert :if={@error} status="error" type="secondary" size="small" title={@error} />
        <.alert
          :if={@integration && @integration.status == :error}
          status="warning"
          type="secondary"
          size="small"
          title={
            dgettext(
              "dashboard_integrations",
              "Tuist could not prepare or stop the provider. Retrying automatically; refresh to check its status."
            )
          }
        />
        <p :if={@integration && @integration.status == :pending}>
          {dgettext(
            "dashboard_integrations",
            "Your token is saved. Tuist is preparing the provider. Once it connects, choose it under Self-Hosted in Amp."
          )}
        </p>
        <p :if={@integration && @integration.status == :running}>
          {dgettext(
            "dashboard_integrations",
            "The provider process is running. Check its connection in Amp’s workspace settings, then select it when starting a thread."
          )}
        </p>
        <p :if={@integration && @integration.status == :disconnecting}>
          {dgettext(
            "dashboard_integrations",
            "Provider access has been revoked. Orbs are being paused and their saved disks are retained. You can manage or delete them from Sandboxes."
          )}
        </p>
        <p :if={@integration && @integration.status == :disconnected}>
          {dgettext(
            "dashboard_integrations",
            "Provider access has been revoked and Orbs are paused. Their saved disks are retained. You can manage or delete them from Sandboxes."
          )}
        </p>
        <p :if={not @available}>
          {dgettext(
            "dashboard_integrations",
            "Sandboxes are not enabled for this account. New Orb sessions are unavailable."
          )}
        </p>
        <div :if={not @editing && not @confirm_disconnect} data-part="actions">
          <.button
            :if={@integration}
            label={dgettext("dashboard_integrations", "Refresh status")}
            variant="secondary"
            phx-click="refresh"
            phx-target={@myself}
          />
          <.button
            :if={@integration && @integration.enabled}
            label={dgettext("dashboard_integrations", "Disconnect")}
            variant="secondary"
            phx-click="confirm-disconnect"
            phx-target={@myself}
          />
          <.button
            :if={@available}
            label={
              if @integration && @integration.enabled,
                do: dgettext("dashboard_integrations", "Replace token"),
                else: dgettext("dashboard_integrations", "Connect Amp")
            }
            variant="primary"
            phx-click="edit"
            phx-target={@myself}
          />
        </div>
        <form
          :if={@editing && @available}
          id={"amp-token-form-#{@form_version}"}
          phx-submit="save"
          phx-target={@myself}
          data-part="form"
          autocomplete="off"
        >
          <ol>
            <li>
              {dgettext(
                "dashboard_integrations",
                "In Amp, open Workspace Settings → Orbs and add an Orb provider."
              )}
            </li>
            <li>
              {dgettext(
                "dashboard_integrations",
                "Copy the provider token and paste it below. Tuist will run the provider for this account."
              )}
            </li>
          </ol>
          <.text_input
            id={"amp-provider-token-#{@form_version}"}
            name="provider_token"
            type="password"
            input_type="password"
            label={dgettext("dashboard_integrations", "Orb provider token")}
            placeholder="aop_live_…"
            value=""
            required
            show_required
            hint={
              dgettext(
                "dashboard_integrations",
                "Stored encrypted and never shown again. No Tuist login or API token is needed."
              )
            }
          />
          <p>
            {dgettext(
              "dashboard_integrations",
              "Anyone who can use this provider in your Amp workspace can run Orbs under this Tuist account."
            )}
          </p>
          <div data-part="actions">
            <.button
              type="button"
              label={dgettext("dashboard_integrations", "Cancel")}
              variant="secondary"
              phx-click="cancel"
              phx-target={@myself}
            />
            <.button
              type="submit"
              label={dgettext("dashboard_integrations", "Save connection")}
              variant="primary"
            />
          </div>
        </form>
        <div :if={@confirm_disconnect} data-part="form">
          <p>
            {dgettext(
              "dashboard_integrations",
              "Disconnect Amp? This stops new work and pauses this integration’s running Orbs. Saved disks remain until you delete them. The token stored in Tuist will be removed."
            )}
          </p>
          <div data-part="actions">
            <.button
              label={dgettext("dashboard_integrations", "Cancel")}
              variant="secondary"
              phx-click="cancel"
              phx-target={@myself}
            />
            <.button
              label={dgettext("dashboard_integrations", "Disconnect Amp")}
              variant="primary"
              phx-click="disconnect"
              phx-target={@myself}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end
end
