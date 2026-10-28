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
    socket =
      socket |> assign(assigns) |> assign(error: nil, disconnect_error: nil, form_version: 0, token_changed: false)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("edit", _, socket),
    do: {:noreply, socket |> load() |> assign(error: nil) |> push_event("open-modal", %{id: "connect-amp-modal"})}

  def handle_event("cancel", _, socket),
    do: {:noreply, socket |> assign(disconnect_error: nil, error: nil) |> close_connection_modal()}

  def handle_event("validate", %{"provider_token" => token}, socket),
    do: {:noreply, assign(socket, token_changed: String.trim(token) != "")}

  def handle_event("save", %{"provider_token" => ""}, socket), do: {:noreply, socket}

  def handle_event("confirm-disconnect", _, socket),
    do:
      {:noreply,
       socket |> load() |> assign(disconnect_error: nil) |> push_event("open-modal", %{id: "disconnect-amp-modal"})}

  def handle_event("cancel-disconnect", _, socket),
    do: {:noreply, socket |> assign(disconnect_error: nil) |> push_event("close-modal", %{id: "disconnect-amp-modal"})}

  def handle_event("save", %{"provider_token" => token}, socket) do
    case AmpIntegrations.connect(socket.assigns.account.id, socket.assigns.current_user, token) do
      {:ok, _} ->
        {:noreply, socket |> load() |> assign(error: nil) |> close_connection_modal()}

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
        {:noreply,
         socket
         |> load()
         |> assign(disconnect_error: nil, error: nil)
         |> push_event("close-modal", %{id: "disconnect-amp-modal"})}

      _ ->
        {:noreply,
         assign(socket,
           disconnect_error:
             dgettext("dashboard_integrations", "You no longer have permission to disconnect this integration.")
         )}
    end
  end

  defp close_connection_modal(socket) do
    socket
    |> push_event("close-modal", %{id: "connect-amp-modal"})
    |> assign(form_version: socket.assigns.form_version + 1, token_changed: false)
  end

  defp load(socket) do
    account = Repo.get!(Account, socket.assigns.account.id)

    if Authorization.authorize(:account_update, socket.assigns.current_user, account) != :ok do
      raise UnauthorizedError
    end

    integration = account.id |> AmpIntegrations.get() |> AmpIntegrations.public_status()
    assign(socket, account: account, integration: integration, available: FeatureFlags.sandboxes_enabled?(account))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      hidden={not @available}
      id={@id}
      data-part="amp-card-section"
      class="noora-card__section"
    >
      <form
        id={"amp-settings-form-#{@form_version}"}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        autocomplete="off"
      >
        <div data-part="header-row">
          <div data-part="header">
            <span data-part="title">Amp</span>
            <span data-part="subtitle">
              {dgettext("dashboard_integrations", "Run your Amp workspace’s Orbs on Tuist sandboxes.")}
            </span>
          </div>
          <div data-part="actions">
            <.button
              :if={@integration && @integration.enabled}
              type="button"
              label={dgettext("dashboard_integrations", "Disconnect")}
              variant="secondary"
              phx-click="confirm-disconnect"
              phx-target={@myself}
            />
            <.button
              :if={@available && !(@integration && @integration.enabled)}
              type="button"
              label={dgettext("dashboard_integrations", "Connect")}
              variant="primary"
              phx-click="edit"
              phx-target={@myself}
            />
          </div>
        </div>
        <.alert
          :if={@error && @integration && @integration.enabled}
          status="error"
          type="secondary"
          size="small"
          title={@error}
        />
        <.alert
          :if={@integration && @integration.status == :error}
          status="warning"
          type="secondary"
          size="small"
          title={
            dgettext(
              "dashboard_integrations",
              "Tuist could not prepare or stop the provider. Retrying automatically."
            )
          }
        />
        <div :if={@integration && @integration.enabled} data-part="fields">
          <.text_input
            id={"amp-saved-provider-token-#{@form_version}"}
            name="provider_token"
            type="password"
            input_type="password"
            label={dgettext("dashboard_integrations", "Orb provider token")}
            placeholder="••••••••••••"
            value=""
          />
        </div>
        <div :if={@integration && @integration.enabled} data-part="actions">
          <.button
            type="submit"
            label={dgettext("dashboard_integrations", "Save changes")}
            variant="primary"
            disabled={not @token_changed}
          />
        </div>
      </form>
      <.modal
        :if={@available}
        id="connect-amp-modal"
        title={dgettext("dashboard_integrations", "Connect Amp")}
        header_size="large"
      >
        <:trigger :let={attrs}>
          <button type="button" hidden aria-hidden="true" tabindex="-1" {attrs} />
        </:trigger>
        <.line_divider />
        <form
          id={"amp-token-form-#{@form_version}"}
          phx-submit="save"
          phx-target={@myself}
          data-part="amp-form"
          autocomplete="off"
        >
          <.alert
            :if={@error && !(@integration && @integration.enabled)}
            status="error"
            type="secondary"
            size="small"
            title={@error}
          />
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
                "Stored encrypted and never shown again."
              )
            }
          />
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
              label={dgettext("dashboard_integrations", "Connect")}
              variant="primary"
            />
          </div>
        </form>
      </.modal>
      <.modal
        :if={@available}
        id="disconnect-amp-modal"
        title={dgettext("dashboard_integrations", "Disconnect")}
        header_size="large"
      >
        <:trigger :let={attrs}>
          <button type="button" hidden aria-hidden="true" tabindex="-1" {attrs} />
        </:trigger>
        <.line_divider />
        <div data-part="amp-form">
          <.alert
            :if={@disconnect_error}
            status="error"
            type="secondary"
            size="small"
            title={@disconnect_error}
          />
          <p>
            {dgettext(
              "dashboard_integrations",
              "This stops new work and pauses this integration’s running Orbs. Saved disks remain until you delete them. The token stored in Tuist will be removed."
            )}
          </p>
        </div>
        <.line_divider />
        <div data-part="amp-form">
          <div data-part="actions">
            <.button
              type="button"
              label={dgettext("dashboard_integrations", "Cancel")}
              variant="secondary"
              phx-click="cancel-disconnect"
              phx-target={@myself}
            />
            <.button
              type="button"
              label={dgettext("dashboard_integrations", "Disconnect")}
              variant="primary"
              phx-click="disconnect"
              phx-target={@myself}
            />
          </div>
        </div>
      </.modal>
    </section>
    """
  end
end
